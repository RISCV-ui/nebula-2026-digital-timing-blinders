#!/usr/bin/env python3
"""
fmax.py -- highest frequency each clock domain can actually run at.

The problem statement is "Constraint Optimization through RTL Enhancement", so
the number that answers it is not slack, it is the constraint itself: the
shortest period the RTL closes at. Slack says "this design misses by 19.7 ns";
Fmax says "this design runs at 31.6 MHz and after the rewrite it runs at 86",
which is the same fact stated as the thing the title asks us to optimize.

No re-synthesis and no re-route. The routed database is fixed and only the SDC
period changes, so the number is a property of the placed and routed logic, and
baseline and candidate are measured the same way. Per clock, because five
asynchronous domains do not share a critical path -- clk_s5 is 19.7 ns short
while clk_s4 has 35 ns of headroom, and one design-wide Fmax would hide that.

Bisection rather than a sweep: each probe is a full STA over 480K instances, so
a 0.01 ns answer costs about eleven probes instead of a few thousand.

Usage:
    fmax.py --odb ...6_final.odb --sdc ...6_final.sdc --out artifacts/metrics/fmax.json
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

FLOW = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "orfs", "flow"))
LIBERTY = os.path.join(FLOW, "platforms", "sky130hd", "lib", "sky130_fd_sc_hd__tt_025C_1v80.lib")

PREAMBLE = """
read_liberty {liberty}
read_db {odb}
read_sdc {sdc}
"""

# Only the five masters carry a period. Every generated clock is divide_by 1
# off a master, so scaling the masters scales the whole tree and keeps the
# ratios the constraint file declares -- moving one domain alone would describe
# a design that does not exist.
PERIOD = re.compile(r"(create_clock\s+.*?-period\s+)([0-9.]+)")


def scaled_sdc(sdc_text, scale, path):
    def repl(m):
        return m.group(1) + f"{float(m.group(2)) * scale:.6f}"
    open(path, "w").write(PERIOD.sub(repl, sdc_text))


def sta(script):
    with tempfile.NamedTemporaryFile("w", suffix=".tcl", delete=False) as f:
        f.write(script)
        p = f.name
    try:
        r = subprocess.run(["openroad", "-no_init", "-exit", p],
                           capture_output=True, text=True, timeout=14400)
    finally:
        os.unlink(p)
    return r.stdout + r.stderr


def probe(odb, sdc, scales, workdir):
    """
    One OpenROAD session for every probe. Reading a 480K-instance database
    costs minutes; re-reading an SDC costs nothing, and create_clock on a name
    that already exists replaces its period, which is exactly a period sweep.
    """
    text = open(sdc).read()
    s = PREAMBLE.format(liberty=LIBERTY, odb=os.path.abspath(odb),
                        sdc=os.path.abspath(sdc))
    for sc in scales:
        p = os.path.join(workdir, f"p_{sc}.sdc")
        scaled_sdc(text, sc, p)
        s += f'\nread_sdc {p}\nputs "SCALE {sc}"\n'
        s += """
foreach clk [sta::all_clocks] {
    set nm [get_name $clk]
    puts "CLK $nm [get_property $clk period]"
    report_checks -path_group $nm -endpoint_path_count 1 -digits 4 -format end
    puts "CLKEND"
}
puts "SCALEEND"
"""
    return sta(s)


SLACK = re.compile(r"(-?[0-9.]+)\s+\((?:MET|VIOLATED)\)\s*$")


def parse(out):
    res, sc, clk, per = {}, None, None, None
    for line in out.splitlines():
        t = line.split()
        if not t:
            continue
        if t[0] == "SCALE" and len(t) == 2:
            sc = float(t[1]); res[sc] = {}
        elif t[0] == "SCALEEND":
            sc = None
        elif t[0] == "CLK" and sc is not None and len(t) >= 3:
            clk, per = t[1], float(t[2])
            res[sc][clk] = {"period_ns": per, "slack_ns": None}
        elif t[0] == "CLKEND":
            clk = None
        elif clk is not None and sc is not None:
            m = SLACK.search(line)
            if m and res[sc][clk]["slack_ns"] is None:
                res[sc][clk]["slack_ns"] = float(m.group(1))
    return res


def crossing(res, clk):
    """Largest failing scale and smallest passing scale for one clock."""
    fail, ok = None, None
    for sc in sorted(res):
        v = res[sc].get(clk)
        if not v or v["slack_ns"] is None:
            continue
        if v["slack_ns"] >= 0:
            if ok is None:
                ok = sc
        elif ok is None:
            fail = sc
    return fail, ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--odb", required=True)
    ap.add_argument("--sdc", required=True)
    ap.add_argument("--lo", type=float, default=0.4)
    ap.add_argument("--hi", type=float, default=4.0)
    ap.add_argument("--steps", type=int, default=12)
    ap.add_argument("--refine", type=int, default=3,
                    help="bisection rounds after the coarse ladder")
    ap.add_argument("--tag", default="unnamed")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    work = tempfile.mkdtemp(prefix="fmax_")

    # Coarse ladder first, geometric because the interesting region is a ratio.
    scales = [round(a.lo * (a.hi / a.lo) ** (i / (a.steps - 1)), 4)
              for i in range(a.steps)]
    out = probe(a.odb, a.sdc, scales, work)
    res = parse(out)
    if not res:
        sys.stderr.write(out[-4000:])
        raise SystemExit("no probes came back -- see output above")

    clocks = sorted({c for v in res.values() for c in v})

    # Then bisect each clock's own crossing. Every probe reports every clock,
    # so the refinement scales are pooled and run in one further session.
    for _ in range(a.refine):
        want = set()
        for c in clocks:
            fail, ok = crossing(res, c)
            if fail is not None and ok is not None:
                want.add(round((fail * ok) ** 0.5, 4))
        want -= set(res)
        if not want:
            break
        res.update(parse(probe(a.odb, a.sdc, sorted(want), work)))

    fmax = {}
    for c in clocks:
        _, ok = crossing(res, c)
        if ok is None:
            fmax[c] = {"min_period_ns": None, "fmax_mhz": None,
                       "note": "no probed period closes"}
            continue
        v = res[ok][c]
        fmax[c] = {"min_period_ns": round(v["period_ns"], 4),
                   "fmax_mhz": round(1000.0 / v["period_ns"], 2),
                   "scale": ok,
                   "slack_at_min_ns": round(v["slack_ns"], 4)}

    doc = {"tag": a.tag, "probes": len(res), "fmax": fmax,
           "sweep": {str(k): v for k, v in sorted(res.items())}}
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(json.dumps(doc, indent=2) + "\n")

    print(f"{'clock':<14} {'constrained':>12} {'min period':>12} {'Fmax':>11}")
    print("-" * 53)
    for c in clocks:
        f = fmax[c]
        base = next((res[s][c]["period_ns"] / s for s in sorted(res)
                     if c in res[s]), 0.0)
        if f["fmax_mhz"] is None:
            print(f"{c:<14} {base:>9.2f} ns {'-':>12} {'-':>11}")
        else:
            print(f"{c:<14} {base:>9.2f} ns {f['min_period_ns']:>9.3f} ns "
                  f"{f['fmax_mhz']:>7.1f} MHz")
    print(f"\n{len(res)} probes")
    if a.out:
        print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
