#!/usr/bin/env python3
"""
Lint gate: wraps Verilator (--lint-only) to catch classes of bug that
neither EQY (SAT equivalence -- blind to X-optimism/uninitialized-state
differences masked by setundef, and only ever compares two specific RTL
snapshots) nor OpenSTA (timing only, assumes the netlist is functionally
sane) will ever flag on their own: inferred latches, real combinational
loops, multi-driven nets, incomplete case coverage.

Not used as a blanket pass/fail gate -- pre-existing designs (gcd.v) already
carry warnings that predate this pipeline, and blocking on those forever
would just make the gate permanently red. Instead: classify warnings into
"hard" (real correctness risk) vs "informational" (width/unused-signal
noise), and let the caller diff hard-warning counts against a baseline --
only NEW hard warnings introduced by an edit should block acceptance.

Usage:
    python3 run_lint.py --verilog designs/src/nebula_soc/nebula_soc.v \
        --top nebula_soc --run-id nebula_soc_baseline --out artifacts/lint/x.json
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

FLOW_DIR = Path(__file__).resolve().parent

# Warning classes that indicate a real functional-correctness risk an LLM
# edit could silently introduce. Everything else Verilator reports (width
# mismatches, unused bits/signals, style) is noise for our purposes -- this
# benchmark's own RTL already trips several of those harmlessly.
HARD_CODES = {
    "LATCH",         # inferred latch -- not all paths of a combinational always assign
    "COMBDLY",       # non-blocking assignment in combinational block
    "BLKSEQ",        # blocking assignment in sequential block
    "MULTIDRIVEN",   # net driven from more than one place
    "CASEINCOMPLETE",
    "CASEOVERLAP",
    "UNOPTFLAT",     # genuine combinational loop (vs. benign ring wiring, still worth a look)
}

WARNING_RE = re.compile(
    r"%Warning-(?P<code>[A-Z0-9]+):\s*(?P<file>[^:]+):(?P<line>\d+):\d+:\s*(?P<msg>.*)"
)


def find_verilator(explicit):
    if explicit:
        return explicit
    candidate = FLOW_DIR.parent.parent / "oss-cad-suite/bin/verilator"
    if candidate.exists():
        return str(candidate)
    raise FileNotFoundError(f"verilator not found at {candidate}; pass --verilator")


def run_lint(verilator_exe, verilog_files, top, extra_args):
    cmd = [str(verilator_exe), "--lint-only", "-Wall"] + extra_args + \
          ["--top-module", top] + [str(v) for v in verilog_files]
    result = subprocess.run(cmd, cwd=FLOW_DIR, capture_output=True, text=True, timeout=120)
    return result


def parse_warnings(stderr_text):
    warnings = []
    for m in WARNING_RE.finditer(stderr_text):
        warnings.append({
            "code": m.group("code"),
            "file": m.group("file"),
            "line": int(m.group("line")),
            "msg": m.group("msg").strip(),
        })
    return warnings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verilog", action="append", required=True, help="RTL source file (repeatable)")
    ap.add_argument("--top", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--verilator")
    ap.add_argument("--ignore", action="append", default=[],
                     help="Verilator warning code to suppress (repeatable), e.g. --ignore BADVLTPRAGMA")
    args = ap.parse_args()

    verilator_exe = find_verilator(args.verilator)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    extra_args = []
    for code in args.ignore:
        extra_args += [f"-Wno-{code}"]

    result = run_lint(verilator_exe, args.verilog, args.top, extra_args)
    warnings = parse_warnings(result.stderr)
    hard = [w for w in warnings if w["code"] in HARD_CODES]

    record = {
        "run_id": args.run_id,
        "top": args.top,
        "verilog": args.verilog,
        "returncode": result.returncode,
        "num_warnings": len(warnings),
        "num_hard_warnings": len(hard),
        "warnings": warnings,
        "hard_warnings": hard,
    }
    out_path.write_text(json.dumps(record, indent=2))
    print(f"Wrote {out_path} -- {len(warnings)} warnings ({len(hard)} hard: "
          f"{sorted(set(w['code'] for w in hard))})", file=sys.stderr)


if __name__ == "__main__":
    main()
