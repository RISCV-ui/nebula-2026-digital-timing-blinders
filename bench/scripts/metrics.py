#!/usr/bin/env python3
"""
metrics.py -- one PPA record for one design state.

G3, the post-place-and-route gate, decides whether a GenAI proposal is worth
keeping by diffing two of these records: the baseline and the candidate. So the
record has to be produced the same way every time, from the database rather
than from whatever the flow happened to print, and it has to work at any stage
so an early reject does not need a full route.

Everything timing-, area- and power-related is read out of the ODB through
OpenROAD. Wirelength and DRC only exist once routing has run, so those are
scraped from the stage logs when they are there and left null when they are
not -- a null is honest, a zero would look like a passing result.

Usage:
    metrics.py --odb results/.../5_1_grt.odb --sdc results/.../5_1_grt.sdc \\
               --logs logs/sky130hd/nebula_bench/base --tag baseline \\
               --out artifacts/metrics/baseline.json
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

FLOW = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "orfs", "flow"))
LIBERTY = os.path.join(FLOW, "platforms", "sky130hd", "lib", "sky130_fd_sc_hd__tt_025C_1v80.lib")

# OpenROAD must see the liberty before the database or linking the design fails
# with STA-0453 on the first standard cell it meets.
TCL = r"""
read_liberty {liberty}
read_db {odb}
read_sdc {sdc}

puts "NEBULA_BEGIN"

puts "instances [llength [[ord::get_db_block] getInsts]]"
puts "nets [llength [[ord::get_db_block] getNets]]"

# Ideal clocks. The candidate and the baseline are compared to each other, not
# to signoff, and propagating a clock on a pre-CTS netlist reports a clock
# network delay that is pure fiction -- 114 ns was observed here once.
puts "SETUP"
report_worst_slack -max -digits 4
report_tns -max -digits 4
puts "HOLD"
report_worst_slack -min -digits 4
report_tns -min -digits 4
puts "SLACKEND"

# Per clock, so a proposal that buys time on one domain by spending it on
# another is visible rather than averaged away. OpenSTA creates one path group
# per clock automatically, so the worst endpoint in a group is that clock's WNS.
foreach clk [sta::all_clocks] {{
    set nm [get_name $clk]
    puts "CLKGROUP $nm [get_property $clk period]"
    report_checks -path_group $nm -endpoint_path_count 1 -digits 4 -format end
    puts "CLKEND"
}}

puts "AREA"
report_design_area
puts "NEBULA_END"
"""


def run_openroad(odb, sdc):
    tcl = TCL.format(liberty=LIBERTY, odb=os.path.abspath(odb), sdc=os.path.abspath(sdc))
    with tempfile.NamedTemporaryFile("w", suffix=".tcl", delete=False) as f:
        f.write(tcl)
        path = f.name
    try:
        p = subprocess.run(["openroad", "-no_init", "-exit", path],
                           capture_output=True, text=True, timeout=1800)
    finally:
        os.unlink(path)
    if "NEBULA_END" not in p.stdout:
        sys.stderr.write(p.stdout[-4000:] + "\n" + p.stderr[-4000:] + "\n")
        raise SystemExit("openroad did not reach NEBULA_END -- see output above")
    return p.stdout


def parse_openroad(out):
    body = out.split("NEBULA_BEGIN", 1)[1].split("NEBULA_END", 1)[0]
    m = {"clocks": {}}
    cur = None
    sec = None
    for line in body.splitlines():
        t = line.split()
        if not t:
            continue
        if t[0] in ("SETUP", "HOLD", "SLACKEND"):
            sec = None if t[0] == "SLACKEND" else t[0].lower()
            continue
        if sec and t[0] == "worst" and t[1] == "slack":
            m["wns" if sec == "setup" else "wns_hold"] = float(t[-1])
            continue
        if sec and t[0] == "tns":
            m["tns" if sec == "setup" else "tns_hold"] = float(t[-1])
            continue
        if t[0] == "CLKGROUP":
            cur = t[1]
            m["clocks"][cur] = {"period_ns": float(t[2]), "wns_ns": None}
            continue
        if t[0] == "CLKEND":
            cur = None
            continue
        if cur is not None:
            mm = re.search(r"(-?[0-9.]+)\s+\((?:MET|VIOLATED)\)\s*$", line)
            if mm and m["clocks"][cur]["wns_ns"] is None:
                m["clocks"][cur]["wns_ns"] = float(mm.group(1))
            continue
        if t[0] in ("instances", "nets") and len(t) >= 2:
            m[t[0]] = int(t[1])
        elif t[0] == "Design" and t[1] == "area":
            m["area_um2"] = float(t[2])
            mm = re.search(r"([0-9.]+)%", line)
            if mm:
                m["utilization_pct"] = float(mm.group(1))
    return m


def scrape_logs(logdir):
    """Wirelength, power and DRC live in the stage logs, not the database."""
    out = {"wirelength_um": None, "drc_violations": None,
           "antenna_violations": None, "power_total_w": None}
    if not logdir or not os.path.isdir(logdir):
        return out

    def read(name):
        p = os.path.join(logdir, name)
        return open(p, errors="ignore").read() if os.path.isfile(p) else ""

    grt = read("5_1_grt.log")
    m = re.search(r"Total wirelength:\s*([0-9]+)", grt)
    if m:
        out["wirelength_um"] = int(m.group(1))

    for name in ("5_2_route.log", "5_2_route.tmp.log"):
        drt = read(name)
        if not drt:
            continue
        m = re.findall(r"Total wire length =\s*([0-9]+)", drt)
        if m:
            out["wirelength_um"] = int(m[-1])
        m = re.findall(r"Number of violations =\s*([0-9]+)", drt)
        if m:
            out["drc_violations"] = int(m[-1])

    for name in ("5_3_fillcell.log", "5_2_route.log", "5_1_grt.log"):
        m = re.findall(r"Found (\d+) net\(s\) violating", read(name))
        if m:
            out["antenna_violations"] = int(m[-1])
            break

    # Power is reported at the end of whichever stage ran last that reports it.
    for name in ("6_report.log", "5_2_route.log", "4_1_cts.log"):
        m = re.findall(r"^Total\s+\S+\s+\S+\s+\S+\s+([0-9.e+-]+)\s+100",
                       read(name), re.M)
        if m:
            out["power_total_w"] = float(m[-1])
            break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--odb", required=True)
    ap.add_argument("--sdc", required=True)
    ap.add_argument("--logs", default=None)
    ap.add_argument("--tag", default="unnamed")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    rec = {"tag": a.tag,
           "odb": os.path.abspath(a.odb),
           "sdc": os.path.abspath(a.sdc),
           "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S")}
    rec.update(parse_openroad(run_openroad(a.odb, a.sdc)))
    rec.update(scrape_logs(a.logs))

    text = json.dumps(rec, indent=2, sort_keys=True)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(text + "\n")
        print(f"wrote {a.out}")
    print(text)


if __name__ == "__main__":
    main()
