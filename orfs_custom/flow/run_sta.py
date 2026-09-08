#!/usr/bin/env python3
"""
Stage 4: wraps OpenSTA (via run_sta.tcl) and turns its report_checks output
into structured JSON -- the ranked critical-path list that is the LLM's
actual input in the Stage 8 loop.

Usage:
    python3 run_sta.py --db results/sky130hd/gcd/base/6_final.odb \
        --sdc results/sky130hd/gcd/base/6_final.sdc \
        --liberty platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
        --openroad ../tools/install/OpenROAD/bin/openroad \
        --out artifacts/sta_gcd.json
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

FLOW_DIR = Path(__file__).resolve().parent
TCL_SCRIPT = FLOW_DIR / "run_sta.tcl"

PATH_BLOCK_RE = re.compile(
    r"Startpoint: (?P<startpoint>\S+)\s+"
    r"\((?P<startpoint_desc>[^)]*)\)\s*\n"
    r"Endpoint: (?P<endpoint>\S+)\s+"
    r"\((?P<endpoint_desc>[^)]*)\)\s*\n"
    r"Path Group: (?P<group>\S+)\s*\n"
    r"Path Type: (?P<path_type>\S+)\s*\n"
    r"(?P<body>.*?)"
    r"slack \((?P<status>MET|VIOLATED)\)",
    re.DOTALL,
)

SLACK_LINE_RE = re.compile(r"^\s*(-?\d+\.\d+)\s+slack \((?:MET|VIOLATED)\)", re.MULTILINE)
ARRIVAL_RE = re.compile(r"(-?\d+\.\d+)\s+data arrival time")
REQUIRED_RE = re.compile(r"(-?\d+\.\d+)\s+data required time")

# each real cell hop line in the delay table, e.g.:
#    0.0046    0.0795    0.3701    0.6119 v _119_/_145_/A (sky130_fd_sc_hd__xnor3_2)
CELL_LINE_RE = re.compile(
    r"^\s*(?P<cap>[\d.]+)?\s*(?P<slew>[\d.]+)?\s+(?P<delay>[\d.]+)\s+(?P<time>[\d.]+)\s+[\^v]\s+"
    r"(?P<pin>\S+)\s+\((?P<cell>[^)]+)\)\s*$",
    re.MULTILINE,
)


def run_sta(openroad_exe, sdc, liberty, group_count, cwd, db=None, netlist=None, top=None, tlef=None, lef=None):
    env = os.environ.copy()
    env["STA_LIBERTY"] = str(liberty)
    env["STA_SDC"] = str(sdc)
    env["STA_GROUP_COUNT"] = str(group_count)
    if db:
        env["STA_DB"] = str(db)
    else:
        env["STA_NETLIST"] = str(netlist)
        env["STA_TOP"] = str(top)
        env["STA_TLEF"] = str(tlef)
        env["STA_LEF"] = str(lef)
    result = subprocess.run(
        [str(openroad_exe), "-exit", str(TCL_SCRIPT)],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"openroad exited {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result.stdout


def extract_section(raw, begin_tag, end_tag):
    start = raw.index(begin_tag) + len(begin_tag)
    end = raw.index(end_tag)
    return raw[start:end]


def parse_paths(section_text, path_delay):
    paths = []
    for m in PATH_BLOCK_RE.finditer(section_text):
        body = m.group("body")
        slack_match = SLACK_LINE_RE.search(body + f"slack ({m.group('status')})")
        # slack value is on the line right before "slack (...)"; grab last numeric
        # line preceding the status marker instead, which is more robust:
        slack_val = None
        for line in reversed(body.strip().splitlines()):
            line = line.strip()
            mm = re.match(r"^(-?\d+\.\d+)$", line)
            if mm:
                slack_val = float(mm.group(1))
                break
        arrival_m = ARRIVAL_RE.search(body)
        required_m = REQUIRED_RE.search(body)
        cells = [
            {
                "pin": c.group("pin"),
                "cell": c.group("cell"),
                "delay": float(c.group("delay")),
                "time": float(c.group("time")),
            }
            for c in CELL_LINE_RE.finditer(body)
        ]
        paths.append(
            {
                "path_delay": path_delay,
                "path_group": m.group("group"),
                "path_type": m.group("path_type"),
                "startpoint": m.group("startpoint"),
                "startpoint_desc": m.group("startpoint_desc").strip(),
                "endpoint": m.group("endpoint"),
                "endpoint_desc": m.group("endpoint_desc").strip(),
                "status": m.group("status"),
                "slack": slack_val,
                "data_arrival_time": float(arrival_m.group(1)) if arrival_m else None,
                "data_required_time": float(required_m.group(1)) if required_m else None,
                "num_cells": len(cells),
                "cells": cells,
            }
        )
    return paths


def parse_wns_tns(section_text):
    wns = {}
    tns = {}
    for line in section_text.strip().splitlines():
        line = line.strip()
        m = re.match(r"wns\s+(\S+)\s+(-?\d+\.\d+)", line)
        if m:
            wns[m.group(1)] = float(m.group(2))
            continue
        m = re.match(r"tns\s+(\S+)\s+(-?\d+\.\d+)", line)
        if m:
            tns[m.group(1)] = float(m.group(2))
    return {"wns": wns, "tns": tns}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", help="post-route .odb (accurate, needs full place & route)")
    ap.add_argument("--netlist", help="synthesized-but-unplaced netlist (fast, no parasitics)")
    ap.add_argument("--top", help="required with --netlist")
    ap.add_argument("--tlef", default=str(FLOW_DIR / "platforms/sky130hd/lef/sky130_fd_sc_hd.tlef"))
    ap.add_argument("--lef", default=str(FLOW_DIR / "platforms/sky130hd/lef/sky130_fd_sc_hd_merged.lef"))
    ap.add_argument("--sdc", required=True)
    ap.add_argument("--liberty", required=True)
    ap.add_argument("--openroad", default=str(FLOW_DIR.parent / "tools/install/OpenROAD/bin/openroad"))
    ap.add_argument("--group-count", type=int, default=20, help="paths per path-group per path-delay")
    ap.add_argument("--out", required=True)
    ap.add_argument("--raw-out", help="optional: also save the raw OpenSTA text output")
    args = ap.parse_args()

    if not args.db and not (args.netlist and args.top):
        ap.error("pass either --db or --netlist together with --top")

    raw = run_sta(
        args.openroad, args.sdc, args.liberty, args.group_count, cwd=FLOW_DIR,
        db=args.db, netlist=args.netlist, top=args.top, tlef=args.tlef, lef=args.lef,
    )

    if args.raw_out:
        Path(args.raw_out).write_text(raw)

    max_section = extract_section(raw, "=== BEGIN MAX PATHS ===", "=== END MAX PATHS ===")
    min_section = extract_section(raw, "=== BEGIN MIN PATHS ===", "=== END MIN PATHS ===")
    wns_tns_section = extract_section(raw, "=== BEGIN WNS TNS ===", "=== END WNS TNS ===")

    max_paths = parse_paths(max_section, "max")
    min_paths = parse_paths(min_section, "min")
    all_paths = max_paths + min_paths
    all_paths.sort(key=lambda p: (p["slack"] if p["slack"] is not None else float("inf")))
    for rank, p in enumerate(all_paths):
        p["rank"] = rank

    summary = parse_wns_tns(wns_tns_section)

    output = {
        "design": args.top if args.netlist else Path(args.db).stem,
        "db": str(args.db) if args.db else None,
        "netlist": str(args.netlist) if args.netlist else None,
        "sdc": str(args.sdc),
        "liberty": str(args.liberty),
        **summary,
        "num_paths": len(all_paths),
        "num_violated": sum(1 for p in all_paths if p["status"] == "VIOLATED"),
        "paths": all_paths,
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(output, indent=2))

    worst = all_paths[0] if all_paths else None
    print(f"Wrote {out_path} -- {len(all_paths)} paths, {output['num_violated']} violated", file=sys.stderr)
    if worst:
        print(
            f"Worst: {worst['startpoint']} -> {worst['endpoint']} "
            f"slack={worst['slack']} ({worst['status']})",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
