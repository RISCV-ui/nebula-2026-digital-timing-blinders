#!/usr/bin/env python3
"""
Stage 7: formal equivalence gate. Wraps EQY (YosysHQ/eqy) to prove a gate
(edited) RTL is functionally equivalent to a gold (pre-edit) RTL, before an
edit is allowed to re-enter synthesis. This is the safety net the LLM loop
in Stage 8 is never allowed to run without.

Usage:
    python3 run_eqy.py --gold gold.v --gate gate.v --top adder \
        --run-id edit_0007 --out artifacts/eqy/edit_0007.json

Exit code mirrors the equivalence result: 0 = proved equivalent, 1 = NOT
equivalent or eqy itself errored. Callers (the retry loop) should branch on
this exit code, not just on the JSON "equivalent" field, so a crashed run
never gets silently treated as a pass.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

FLOW_DIR = Path(__file__).resolve().parent

# {stub} is either empty or a "read_verilog -lib <stubs>" line, repeated in
# both sections: a hard macro must be a black box on BOTH sides or EQY tries
# to prove a macro instance equivalent to inferred flops and always fails.
EQY_TEMPLATE = """\
[gold]
{stub}read_verilog {gold_flags}{gold}
prep -top {top}

[gate]
{stub}read_verilog {gate_flags}{gate}
prep -top {top}

[strategy sat]
use sat
depth {depth}
"""


def find_tool(name, hint_dir):
    exe = shutil.which(name)
    if exe:
        return exe
    candidate = FLOW_DIR.parent / "tools/install" / hint_dir / "bin" / name
    if candidate.exists():
        return str(candidate)
    raise FileNotFoundError(f"{name} not found on PATH or at {candidate}")


def run_eqy(gold, gate, top, run_id, workdir, depth, sv, timeout, macro_stubs=None):
    eqy_exe = find_tool("eqy", "eqy")
    yosys_bin_dir = str((FLOW_DIR.parent / "tools/install/yosys/bin"))

    gold_flags = "-sv " if sv else ""
    gate_flags = "-sv " if sv else ""

    stub = ""
    if macro_stubs:
        stub = "read_verilog -lib " + " ".join(
            str(Path(m).resolve()) for m in macro_stubs) + "\n"

    cfg_text = EQY_TEMPLATE.format(
        gold=Path(gold).resolve(),
        gate=Path(gate).resolve(),
        top=top,
        depth=depth,
        gold_flags=gold_flags,
        gate_flags=gate_flags,
        stub=stub,
    )
    cfg_path = workdir / f"{run_id}.eqy"
    cfg_path.write_text(cfg_text)

    import os

    env = os.environ.copy()
    env["PATH"] = yosys_bin_dir + ":" + str(Path(eqy_exe).parent) + ":" + env.get("PATH", "")

    proc = subprocess.run(
        [eqy_exe, cfg_path.name],
        cwd=workdir,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return proc, cfg_path


def classify(proc):
    log = proc.stdout + proc.stderr
    if re.search(r"Successfully proved designs? equivalent", log):
        return True, "PROVED_EQUIVALENT"
    if re.search(r"Failed to prove equivalence", log) or proc.returncode not in (0,):
        return False, "NOT_EQUIVALENT_OR_ERROR"
    # eqy returned 0 but no clear proof string -- treat as untrusted, not a pass
    return False, "AMBIGUOUS_OUTPUT"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gold", required=True, help="pre-edit RTL (reference)")
    ap.add_argument("--gate", required=True, help="post-edit RTL (candidate)")
    ap.add_argument("--top", required=True, help="top module name (must match in both files)")
    ap.add_argument("--run-id", required=True, help="tag for this check, e.g. edit_0007")
    ap.add_argument("--out", required=True, help="path to write result JSON")
    ap.add_argument("--depth", type=int, default=5, help="SAT strategy unroll depth")
    ap.add_argument("--sv", action="store_true", help="parse inputs as SystemVerilog")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--macro-stub", action="append", default=[],
                    help="stub file read with -lib in both gold and gate so its "
                         "modules stay black boxes (repeatable)")
    ap.add_argument("--keep-workdir", action="store_true", help="don't delete the eqy scratch dir")
    args = ap.parse_args()

    tmp_root = Path(tempfile.mkdtemp(prefix=f"eqy_{args.run_id}_"))
    try:
        proc, cfg_path = run_eqy(
            args.gold, args.gate, args.top, args.run_id, tmp_root, args.depth, args.sv, args.timeout,
            macro_stubs=args.macro_stub,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        result = {
            "run_id": args.run_id,
            "gold": str(Path(args.gold).resolve()),
            "gate": str(Path(args.gate).resolve()),
            "top": args.top,
            "equivalent": False,
            "status": f"ERROR: {e}",
            "returncode": None,
        }
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(result, indent=2))
        print(f"EQY ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    equivalent, status = classify(proc)

    result = {
        "run_id": args.run_id,
        "gold": str(Path(args.gold).resolve()),
        "gate": str(Path(args.gate).resolve()),
        "top": args.top,
        "equivalent": equivalent,
        "status": status,
        "returncode": proc.returncode,
        "log_tail": (proc.stdout + proc.stderr).strip().splitlines()[-15:],
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2))

    if not args.keep_workdir:
        shutil.rmtree(tmp_root, ignore_errors=True)
    else:
        print(f"workdir kept: {tmp_root}", file=sys.stderr)

    print(f"Wrote {out_path} -- equivalent={equivalent} ({status})", file=sys.stderr)
    sys.exit(0 if equivalent else 1)


if __name__ == "__main__":
    main()
