#!/usr/bin/env python3
"""
slicer.py -- gate-level critical path -> the RTL that has to change.

A timing report names 200 gates. An LLM given those 200 gates has no idea which
file to edit, because the gate names Yosys invents (_1370_, place25344) exist
nowhere in the source. What it needs is: which RTL module burns the time, and
what that module's source says.

The bridge is the instance path. dot_0/fp4_dot_0/add2/_1370_/COUT is a cell
Yosys named, but everything before it is RTL hierarchy that survived synthesis
because SYNTH_HIERARCHICAL=1 and SYNTH_ARGS=-nofsm are set. hierarchy.py turns
that prefix into a module name; this script sums the path delay per module and
hands back the source of whichever module dominates.

Two things in the output matter as much as the delay ranking:

  * the module chain for the startpoint and the endpoint, because a path that
    starts or ends inside asynchronous_fifo_gen is a clock-domain crossing and
    a pipeline stage inserted there is a silicon bug the equivalence check
    cannot see;
  * per-module share, because a proposal aimed at a module holding 4% of the
    path is wasted even if it is accepted.

Usage:
    slicer.py --odb ...5_1_grt.odb --sdc ...5_1_grt.sdc --paths 20 \\
              --out artifacts/paths/baseline.json
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hierarchy

FLOW = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "orfs", "flow"))
LIBERTY = os.path.join(FLOW, "platforms", "sky130hd", "lib", "sky130_fd_sc_hd__tt_025C_1v80.lib")

# Modules that carry a clock-domain crossing. A transform touching one of these
# is refused before it is ever proposed -- G2 exists to catch what slips past,
# but not offering the path in the first place is cheaper than rejecting it.
CDC_MODULES = {"asynchronous_fifo_gen"}

# What a gate-level pass can actually recover on this path, as a fraction of
# the path's own combinational delay.
#
# The number is deliberately generous. sky130hd is a single-Vt library, so the
# usual gate-level levers -- upsizing, buffer insertion, cell swaps, a tighter
# placement for the offending net -- have no low-Vt cells to reach for and are
# left with drive strength and wire length. Published numbers for that class of
# fix on an open PDK land near 10-15%; 20% is the optimistic end, chosen so the
# selector errs toward "try the cheap lever first" and only sends a path to the
# LLM when even the optimistic gate-level bound falls short.
GATE_HEADROOM = 0.20

# Below this, the path is one deep cell or a wire, not a structure. Pipelining
# a two-stage path buys a register's clk-to-q and setup back for nothing.
MIN_STAGES_FOR_RTL = 4


def lever(p):
    """
    Which lever closes this path: the gate-level flow, or an RTL rewrite?

    This is the question the flow exists to answer, and answering it per path
    is what keeps the LLM off work the synthesiser was already going to do.
    Three cases, in order:

    `none`  -- the path meets timing. Nothing to close. Eleven of this design's
               twelve targets sit here, and every LLM call spent on one of them
               would change a number nobody reports.

    `gate`  -- the path misses, but by less than an optimistic gate-level pass
               could plausibly recover. Upsizing and buffering are free, run
               automatically, and carry no equivalence risk; sending this to a
               model spends a call and a proof to duplicate them.

    `rtl`   -- the path misses by more than any gate-level move can reach, so
               the structure itself has to change. `clk_s5` is the case that
               makes this concrete: it needs 12.5 ns and takes 32.196 ns, a
               2.6x overrun, with 85.7% of it inside three chained `fp8_adder`
               instances. No amount of sizing closes a 19.7 ns gap; only
               cutting the chain does.

    The stage count is the one veto. A path can overrun badly and still be a
    single deep cell or a long wire, and there is no structure there to
    restructure -- that one goes back to the gate-level flow however bad the
    slack is, and the reason says so rather than pretending an RTL edit exists.
    """
    slack = p.get("slack_ns")
    delay = p.get("combinational_delay_ns") or 0.0
    if slack is None:
        return {"lever": "unknown", "reason": "no slack reported for this path"}
    if slack >= 0:
        return {"lever": "none",
                "reason": f"slack {slack:+.3f} ns -- path already meets timing",
                "gap_ns": 0.0}

    gap = -slack
    reach = GATE_HEADROOM * delay
    t = p.get("target") or {}
    share = t.get("share_pct", 0.0)
    n_inst = len(t.get("instances") or []) or 1

    d = {"gap_ns": round(gap, 4),
         "gate_reach_ns": round(reach, 4),
         "overrun_ratio": round(gap / (delay + slack), 3) if delay + slack > 0 else None}

    if gap <= reach:
        d.update(lever="gate",
                 reason=(f"needs {gap:.3f} ns; sizing and buffering can "
                         f"plausibly recover {reach:.3f} ns "
                         f"({GATE_HEADROOM:.0%} of {delay:.3f} ns) -- inside "
                         f"the gate-level flow's own reach"))
        return d

    if p.get("stages", 0) < MIN_STAGES_FOR_RTL:
        d.update(lever="gate",
                 reason=(f"needs {gap:.3f} ns, past the {reach:.3f} ns "
                         f"gate-level reach, but the path is only "
                         f"{p.get('stages',0)} stages -- there is no structure "
                         f"to restructure, so the gap is drive and wire"))
        return d

    d.update(lever="rtl",
             reason=(f"needs {gap:.3f} ns, {gap/reach:.1f}x what the "
                     f"gate-level flow can reach ({reach:.3f} ns); "
                     f"{share:.1f}% of the path sits in {t.get('module','?')} "
                     f"across {n_inst} instance{'s' if n_inst != 1 else ''}, "
                     f"so the structure is what has to change"))
    return d


TCL = """
read_liberty {liberty}
read_db {odb}
read_sdc {sdc}
{signoff_setup}
report_checks -path_delay max -sort_by_slack -group_path_count {n} \\
              -format full -digits 4
"""

PIN = re.compile(r"^\s*(-?[\d.]+)\s+(-?[\d.]+)\s+[\^v]\s+(\S+)\s+\((\S+)\)\s*$")


def signoff_setup(odb):
    """Restore the RC and clock state that ORFS adds after saving 6_final."""
    spef = os.path.splitext(os.path.abspath(odb))[0] + ".spef"
    if not os.path.isfile(spef):
        return ""
    # Target selection must see the same critical path as signoff. Without the
    # adjacent SPEF, every model in a bake-off answers a stale ideal-clock
    # problem even though the final PPA comparison uses extracted parasitics.
    return f"read_spef {spef}\nset_propagated_clock [all_clocks]"


def run_sta(odb, sdc, n):
    tcl = TCL.format(liberty=LIBERTY, odb=os.path.abspath(odb),
                     sdc=os.path.abspath(sdc), n=n,
                     signoff_setup=signoff_setup(odb))
    with tempfile.NamedTemporaryFile("w", suffix=".tcl", delete=False) as f:
        f.write(tcl)
        p = f.name
    try:
        r = subprocess.run(["openroad", "-no_init", "-exit", p],
                           capture_output=True, text=True, timeout=3600)
    finally:
        os.unlink(p)
    if "Startpoint:" not in r.stdout:
        sys.stderr.write(r.stdout[-3000:] + r.stderr[-3000:])
        raise SystemExit("no timing paths in report -- see output above")
    return r.stdout


def split_paths(out):
    chunks, cur = [], None
    for line in out.splitlines():
        if line.startswith("Startpoint:"):
            if cur:
                chunks.append(cur)
            cur = [line]
        elif cur is not None:
            cur.append(line)
    if cur:
        chunks.append(cur)
    return chunks


def owner(inst_path, top, tree):
    """Deepest RTL module containing this cell, plus the full chain."""
    prefix = inst_path.rsplit("/", 1)[0] if "/" in inst_path else ""
    chain = hierarchy.resolve(prefix, top, tree) if prefix else []
    if not chain:
        return top, [], top
    inst = "/".join(seg for seg, _ in chain)
    return chain[-1][1], chain, inst


def parse_path(lines, top, tree):
    text = "\n".join(lines)
    p = {}
    m = re.search(r"Startpoint:\s*(\S+)", text)
    p["startpoint"] = m.group(1) if m else None
    m = re.search(r"Endpoint:\s*(\S+)", text)
    p["endpoint"] = m.group(1) if m else None
    m = re.search(r"Path Group:\s*(\S+)", text)
    p["clock"] = m.group(1) if m else None
    m = re.search(r"(-?[\d.]+)\s+slack", text)
    p["slack_ns"] = float(m.group(1)) if m else None

    per_mod, total, stages = {}, 0.0, 0
    for line in lines:
        mm = PIN.match(line)
        if not mm:
            continue
        delay = float(mm.group(1))
        mod, _, inst = owner(mm.group(3), top, tree)
        key = f"{inst}:{mod}"
        per_mod[key] = per_mod.get(key, 0.0) + delay
        total += delay
        stages += 1

    p["combinational_delay_ns"] = round(total, 4)
    p["stages"] = stages
    p["modules"] = [
        {"instance": k.split(":", 1)[0], "module": k.split(":", 1)[1],
         "delay_ns": round(v, 4),
         "share_pct": round(100.0 * v / total, 1) if total else 0.0}
        for k, v in sorted(per_mod.items(), key=lambda kv: -kv[1])
    ]

    for end, name in (("startpoint", "start"), ("endpoint", "end")):
        _, chain, _ = owner(p[end] or "", top, tree)
        p[name + "_chain"] = [{"instance": i, "module": mo} for i, mo in chain]

    touched = {d["module"] for d in p["modules"]}
    touched |= {c["module"] for c in p["start_chain"] + p["end_chain"]}
    p["cdc_modules_on_path"] = sorted(touched & CDC_MODULES)
    p["crosses_cdc"] = bool(p["cdc_modules_on_path"])

    # Instances are what the timing report names; modules are what gets edited.
    # add2, add5 and add6 are three instances of one fp8_adder, so one rewrite
    # of that module fixes all three -- and asking the model once instead of
    # three times is the difference between a loop that fits in a call budget
    # and one that does not. The cost of editing the module is that every
    # instance changes, including instances off the critical path; G3 measures
    # that as area and will reject a bad trade.
    by_mod = {}
    for d in p["modules"]:
        e = by_mod.setdefault(d["module"], {"module": d["module"],
                                            "instances": [], "delay_ns": 0.0})
        e["instances"].append(d["instance"])
        e["delay_ns"] = round(e["delay_ns"] + d["delay_ns"], 4)
    for e in by_mod.values():
        e["share_pct"] = round(100.0 * e["delay_ns"] / total, 1) if total else 0.0
    p["module_totals"] = sorted(by_mod.values(), key=lambda e: -e["delay_ns"])

    # The module worth editing: the biggest share that is not a CDC structure.
    p["target"] = next((e for e in p["module_totals"]
                        if e["module"] not in CDC_MODULES), None)
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--odb", required=True)
    ap.add_argument("--sdc", required=True)
    ap.add_argument("--top", default="soc_top")
    ap.add_argument("--paths", type=int, default=20)
    ap.add_argument("--rtl", default=None, help="emit source of each target module here")
    ap.add_argument("--no-module-collapse", action="store_true",
                    help="report every path, not one per target module")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    mods = hierarchy.load_modules(a.rtl or hierarchy.RTL_DIR)
    tree = hierarchy.instantiations(mods)

    paths = [parse_path(c, a.top, tree)
             for c in split_paths(run_sta(a.odb, a.sdc, a.paths))]
    paths = [p for p in paths if p["slack_ns"] is not None]
    paths.sort(key=lambda p: p["slack_ns"])

    # 20 endpoints of the same FIFO word are 20 reports of one logical path.
    # Collapsing them by signature is what stops the loop spending 20 LLM calls
    # to fix the same adder chain twice.
    uniq, seen = [], {}
    for p in paths:
        sig = (p["clock"],
               "/".join(c["instance"] for c in p["start_chain"]),
               (p.get("target") or {}).get("module"),
               round(p["combinational_delay_ns"], 1))
        if sig in seen:
            seen[sig]["endpoint_count"] += 1
            continue
        p["endpoint_count"] = 1
        seen[sig] = p
        uniq.append(p)
    paths = uniq

    # Second collapse, and the one that decides the call budget: two paths whose
    # worst module is the same module are two symptoms of one edit. The loop
    # keeps the worst path per target module and records how many paths that
    # module was blamed for, so a module holding fifteen near-critical paths is
    # visibly worth more than one holding a single path at the same slack.
    if not a.no_module_collapse:
        best = {}
        for p in paths:
            key = (p.get("target") or {}).get("module") or p["endpoint"]
            if key in best:
                best[key]["paths_covered"] += 1
                best[key]["endpoint_count"] += p["endpoint_count"]
                continue
            p["paths_covered"] = 1
            best[key] = p
        paths = sorted(best.values(), key=lambda p: p["slack_ns"])

    for i, p in enumerate(paths):
        p["id"] = f"P{i:03d}"
        p["lever"] = lever(p)
        t = p.get("target")
        if t:
            src = mods.get(t["module"])
            p["target_source_file"] = src["file"] if src else None
            p["target_source_lines"] = src["body"].count("\n") + 1 if src else None

    doc = {"top": a.top, "path_count": len(paths), "paths": paths}
    text = json.dumps(doc, indent=2)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(text + "\n")

    for p in paths:
        t = p.get("target") or {}
        flag = " CDC" if p["crosses_cdc"] else ""
        print(f'{p["id"]} {p["clock"]:<12} slack {p["slack_ns"]:>9.3f}  '
              f'{p["stages"]:>3} stages  target {t.get("module","-"):<24} '
              f'{t.get("share_pct",0):>5.1f}% x{len(t.get("instances",[])) or 1}'
              f'  covers {p.get("paths_covered",1)}p/{p["endpoint_count"]}ep{flag}'
              f'  lever {p["lever"]["lever"]}')
    if a.out:
        print(f"\nwrote {a.out}")


if __name__ == "__main__":
    main()
