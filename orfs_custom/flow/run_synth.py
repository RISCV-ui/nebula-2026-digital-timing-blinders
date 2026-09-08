#!/usr/bin/env python3
"""
Stage 3: wraps Yosys (via run_synth.tcl) for fast standalone re-synthesis --
the "resynth" half of resynth_and_check in the Stage 8 loop. Not the full
ORFS flow (that is the expensive final PPA run, Stage 5); this is a quick
synth-only pass used to get a flat netlist + area/cell-count numbers after
each LLM RTL edit, cheap enough to run every retry.

Usage:
    python3 run_synth.py --verilog designs/src/gcd/gcd.v --top gcd \
        --liberty platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
        --run-id gcd_base --out artifacts/synth/gcd_base.json

Multiple source files: repeat --verilog.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

FLOW_DIR = Path(__file__).resolve().parent
TCL_SCRIPT = FLOW_DIR / "run_synth.tcl"


def find_yosys(explicit):
    if explicit:
        return explicit
    candidate = FLOW_DIR.parent / "tools/install/yosys/bin/yosys"
    if candidate.exists():
        return str(candidate)
    raise FileNotFoundError(f"yosys not found at {candidate}; pass --yosys")


def run_synth(yosys_exe, verilog_files, top, liberty, out_v, cwd, strategy=None, abc_period_ps=None,
              blackbox_files=None):
    import os

    env = os.environ.copy()
    env["SYNTH_VERILOG"] = ":".join(str(v) for v in verilog_files)
    env["SYNTH_TOP"] = top
    env["SYNTH_LIBERTY"] = str(liberty)
    env["SYNTH_OUT_V"] = str(out_v)
    # Hard macros (the OpenRAM SRAMs) come in as port-only stubs; see the
    # SYNTH_BLACKBOX_V comment in run_synth.tcl for why the .v must not be
    # synthesized. Their .v files must also be left out of verilog_files.
    if blackbox_files:
        env["SYNTH_BLACKBOX_V"] = ":".join(str(b) for b in blackbox_files)
    if strategy:
        env["SYNTH_STRATEGY"] = strategy
    if abc_period_ps:
        env["SYNTH_ABC_PERIOD_PS"] = str(abc_period_ps)

    result = subprocess.run(
        [str(yosys_exe), "-q", "-c", str(TCL_SCRIPT)],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=600,
    )
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verilog", action="append", required=True, help="RTL source file (repeatable)")
    ap.add_argument("--top", required=True)
    ap.add_argument("--liberty", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--out", required=True, help="path to write result JSON")
    ap.add_argument("--out-netlist", help="path for synthesized netlist (default: <out>.v)")
    ap.add_argument("--yosys")
    ap.add_argument("--strategy", choices=["default", "retime", "timing_driven"], default="default",
                     help="synthesis-only retry variant (no RTL change)")
    ap.add_argument("--abc-period-ps", type=float, help="required for --strategy timing_driven")
    ap.add_argument("--blackbox", action="append", default=[],
                    help="stub file read with -lib so its modules stay black boxes "
                         "(repeatable; use for hard macros such as the OpenRAM SRAMs)")
    args = ap.parse_args()

    yosys_exe = find_yosys(args.yosys)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_v = Path(args.out_netlist) if args.out_netlist else out_path.with_suffix(".v")
    out_v.parent.mkdir(parents=True, exist_ok=True)

    verilog_abs = [str(Path(v).resolve()) for v in args.verilog]

    result = run_synth(yosys_exe, verilog_abs, args.top, Path(args.liberty).resolve(), out_v.resolve(), cwd=FLOW_DIR,
                        strategy=args.strategy, abc_period_ps=args.abc_period_ps,
                        blackbox_files=[str(Path(b).resolve()) for b in args.blackbox])

    record = {
        "run_id": args.run_id,
        "strategy": args.strategy,
        "top": args.top,
        "verilog": verilog_abs,
        "liberty": str(Path(args.liberty).resolve()),
        "netlist": str(out_v),
        "returncode": result.returncode,
        "warnings": [l for l in result.stdout.splitlines() if l.startswith("Warning:")],
    }

    if result.returncode != 0:
        record["ok"] = False
        record["error"] = result.stdout[-4000:] + result.stderr[-2000:]
        out_path.write_text(json.dumps(record, indent=2))
        print(f"SYNTH FAILED (rc={result.returncode}) -- see {out_path}", file=sys.stderr)
        sys.exit(1)

    stat_json_path = Path(f"{out_v}.stat.json")
    stat = json.loads(stat_json_path.read_text())
    top_key = f"\\{args.top}"
    if top_key not in stat["modules"]:
        # fall back to the (only) module present, in case of name mangling
        top_key = next(iter(stat["modules"]))
    mod = stat["modules"][top_key]

    # stat counts internal bookkeeping pseudo-cells (e.g. $scopeinfo, added by
    # `flatten`) alongside real standard-cell instances -- exclude anything
    # whose type starts with "$" so num_cells reflects physical cells only.
    cells_by_type = {
        k: v for k, v in mod.get("num_cells_by_type", {}).items() if not k.startswith("$")
    }

    record["ok"] = True
    record["num_cells"] = sum(cells_by_type.values())
    record["area"] = mod.get("area")
    record["sequential_area"] = mod.get("sequential_area")
    record["num_cells_by_type"] = cells_by_type

    out_path.write_text(json.dumps(record, indent=2))
    print(
        f"Wrote {out_path} -- {record['num_cells']} cells, area={record['area']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
