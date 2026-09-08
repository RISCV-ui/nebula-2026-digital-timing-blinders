#!/usr/bin/env python3
"""
run_sta(netlist, sdc) -> ranked critical paths + slack, as JSON.

Wraps OpenSTA (via the Docker image, sta/sta.sh) per the project architecture
in CLAUDE.md: this is the LLM's input context in the later agentic loop.
Run from the repo root -- all paths are repo-relative.

Stage 4 rewrite: JSON is built INSIDE the Tcl script from OpenSTA's PathEnd/
Path object API (find_timing_paths + method-call syntax), not scraped out of
report_checks' human-readable text with regex. The regex approach (Stage 0/1)
worked but was fragile -- format changes, deprecated-flag warnings, or an
unexpected startpoint/endpoint phrasing would silently break parsing. The
object API is what OpenSTA itself uses to print that text, so it can't drift
out of sync with itself. Key gotcha found while building this: PathEnd's
`pins` (via `$path_end path pins`) returns the WHOLE trace including the
clock network, in endpoint-to-source order -- easy to misread as forward
chronological. `[[$path start_path] pin]` is the clean way to get the
startpoint.
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
STA_WRAPPER = REPO_ROOT / "sta" / "sta.sh"

TCL_TEMPLATE = """\
read_liberty /data/{liberty}
read_verilog /data/{netlist}
link_design {top}
read_sdc /data/{sdc}

set paths [find_timing_paths -path_delay min_max -sort_by_slack -group_path_count {group_count}]

puts "===JSON_START==="
puts -nonewline "\\["
set first 1
foreach p $paths {{
    set pth [$p path]
    set sp [$pth start_path]
    set sp_name [get_full_name [$sp pin]]
    set ep_name [get_full_name [$p pin]]
    set slack_ns [expr {{[$p slack] * 1e9}}]
    set arr_ns   [expr {{[$p data_arrival_time] * 1e9}}]
    set req_ns   [expr {{[$p data_required_time] * 1e9}}]
    set clk_name [get_name [$p target_clk]]
    set path_type [$p min_max]
    set status [expr {{$slack_ns >= 0 ? "MET" : "VIOLATED"}}]

    if {{!$first}} {{ puts -nonewline "," }}
    set first 0
    puts -nonewline "\\n  {{\\"startpoint\\": \\"$sp_name\\", \\"endpoint\\": \\"$ep_name\\", \\"path_group\\": \\"$clk_name\\", \\"path_type\\": \\"$path_type\\", \\"slack_ns\\": [format %.4f $slack_ns], \\"arrival_ns\\": [format %.4f $arr_ns], \\"required_ns\\": [format %.4f $req_ns], \\"status\\": \\"$status\\"}}"
}}
puts "\\n\\]"
puts "===JSON_END==="
exit
"""

JSON_BLOCK_RE = re.compile(r"===JSON_START===\n(.*?)\n===JSON_END===", re.S)


def run_sta(netlist: str, sdc: str, liberty: str, top: str, group_count: int = 30) -> str:
    tcl = TCL_TEMPLATE.format(
        liberty=liberty, netlist=netlist, sdc=sdc, top=top, group_count=group_count
    )
    with tempfile.NamedTemporaryFile(
        "w", dir=REPO_ROOT, suffix=".tcl", delete=False
    ) as f:
        f.write(tcl)
        tcl_path = Path(f.name)

    try:
        result = subprocess.run(
            [str(STA_WRAPPER), f"/data/{tcl_path.name}"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
    finally:
        tcl_path.unlink(missing_ok=True)

    if result.returncode != 0:
        raise RuntimeError(f"OpenSTA failed:\n{result.stderr}\n{result.stdout}")

    return result.stdout


def parse_paths(sta_output: str) -> list[dict]:
    m = JSON_BLOCK_RE.search(sta_output)
    if not m:
        raise RuntimeError(f"no JSON block found in OpenSTA output:\n{sta_output}")
    paths = json.loads(m.group(1))
    paths.sort(key=lambda p: p["slack_ns"])
    return paths


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--netlist", required=True, help="repo-relative path to gate-level netlist")
    ap.add_argument("--sdc", required=True, help="repo-relative path to SDC constraints")
    ap.add_argument("--liberty", required=True, help="repo-relative path to liberty file")
    ap.add_argument("--top", required=True, help="top module name")
    ap.add_argument("--group-count", type=int, default=30)
    ap.add_argument("--out", help="write JSON to this file instead of stdout")
    args = ap.parse_args()

    raw = run_sta(args.netlist, args.sdc, args.liberty, args.top, args.group_count)
    paths = parse_paths(raw)

    report = {
        "top": args.top,
        "num_paths_reported": len(paths),
        "num_violations": sum(1 for p in paths if p["status"] == "VIOLATED"),
        "wns": min((p["slack_ns"] for p in paths), default=0.0),
        "paths": paths,
    }

    out_json = json.dumps(report, indent=2)
    if args.out:
        Path(args.out).write_text(out_json)
        print(f"wrote {args.out} ({len(paths)} paths, {report['num_violations']} violations)", file=sys.stderr)
    else:
        print(out_json)


if __name__ == "__main__":
    main()
