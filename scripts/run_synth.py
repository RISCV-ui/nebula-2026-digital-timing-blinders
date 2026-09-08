#!/usr/bin/env python3
"""
run_synth(rtl_files, top, liberty, out) -> synthesized gate-level netlist.

Wraps Yosys. This build of OSS CAD Suite's Yosys has no Tcl support (no -c
flag, no `tcl` command -- confirmed via `yosys -help` / `help tcl`), so the
synthesis script is Yosys's own native command DSL, not Tcl. Parameterization
(which RTL files, which liberty, which top) is done here in Python instead,
mirroring run_sta.py's pattern: this script builds the .ys text and hands it
to Yosys via subprocess.

This is the first half of the project's eventual resynth_and_check() tool
(CLAUDE.md architecture) -- the "resynth" part. The "check" part (re-run STA,
compare slack, gate on EQY) still lives in run_sta.py / the not-yet-built EQY
wrapper.
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
YOSYS = REPO_ROOT / "oss-cad-suite" / "bin" / "yosys"

# each pass explained (why it's in the pipeline, not just that it's called):
#   proc          - convert always blocks into an internal netlist form
#                    (RTLIL processes), first thing any Yosys flow needs
#   opt           - cheap local optimization pass, run repeatedly between
#                    stages to keep the design small before heavier passes
#   fsm           - detect and re-encode explicit state machines. OFF whenever
#                    the netlist has to be equivalence-checked module by
#                    module, or compared against the RTL as a baseline: FSM
#                    re-encoding changes the state bits themselves, so the
#                    netlist is no longer the design we asked the LLM to
#                    optimize. The loop's own FSM-optimization technique is a
#                    deliberate RTL edit, not a silent synthesis pass.
#   memory        - map memory-inference patterns to explicit RAM cells
#   techmap       - map generic RTLIL cells to a technology-independent
#                    gate library (still not the real standard cells yet)
#   dfflibmap     - map generic flip-flops to the real liberty's actual
#                    sequential cells (e.g. sky130_fd_sc_hd__dfxtp_1)
#   abc -liberty  - technology mapping + logic optimization against the real
#                    liberty's combinational cells (this is where cell
#                    selection / area / delay tradeoffs actually happen)
#   clean         - drop now-dead wires/cells left behind by the above
#   read_liberty -lib   - read a macro's liberty as a BLACKBOX: Yosys learns the
#                    module's port list and directions but nothing about its
#                    contents, so it instantiates the macro instead of trying
#                    to synthesize one. This is how a hard macro (an SRAM
#                    compiled by OpenRAM, here) enters the flow. The macro's
#                    behavioural .v must NOT be read as RTL -- it would be
#                    flattened into flip-flops, which is exactly what the
#                    macro exists to avoid.
YS_TEMPLATE = """\
{macro_lines}
{read_lines}
hierarchy -check -top {top}
proc; opt{fsm}; opt; memory; opt
techmap; opt
dfflibmap -liberty {liberty}
abc -liberty {liberty}
clean
write_verilog -noattr {out}
stat -liberty {liberty}
"""


def run_synth(
    rtl_files: list[str],
    top: str,
    liberty: str,
    out: str,
    macro_libs: list[str] | None = None,
    timeout: int = 120,
    fsm_opt: bool = True,
) -> str:
    macro_lines = "\n".join(f"read_liberty -lib {m}" for m in (macro_libs or []))
    read_lines = "\n".join(f"read_verilog {f}" for f in rtl_files)
    ys = YS_TEMPLATE.format(
        macro_lines=macro_lines,
        read_lines=read_lines,
        top=top,
        liberty=liberty,
        out=out,
        fsm="; fsm" if fsm_opt else "",
    )

    with tempfile.NamedTemporaryFile(
        "w", dir=REPO_ROOT, suffix=".ys", delete=False
    ) as f:
        f.write(ys)
        ys_path = Path(f.name)

    try:
        result = subprocess.run(
            [str(YOSYS), "-s", str(ys_path)],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    finally:
        ys_path.unlink(missing_ok=True)

    if result.returncode != 0:
        raise RuntimeError(f"Yosys failed:\n{result.stderr}\n{result.stdout}")

    return result.stdout


def parse_stat(yosys_output: str) -> dict:
    """Pull cell count and chip area out of the `stat -liberty` block.

    Hierarchy is preserved (nothing here ever runs `flatten`), so `stat` emits
    one block per module and then a `design hierarchy` block whose first line
    is the top's count and area INCLUDING submodules. Reading the first
    per-module block instead would report whichever module sorted first --
    for soc_top that was 1038 cells against a real 71,961.
    """
    hier = re.search(
        r"=== design hierarchy ===.*?^\s*(\d+)\s+(\S+)\s+" + r"\S+\s*$",
        yosys_output,
        re.M | re.S,
    )
    area_match = re.search(r"Chip area for top module.*?:\s*([\d.]+)", yosys_output)
    if area_match is None:
        area_match = re.search(r"Chip area for.*?:\s*([\d.]+)", yosys_output)
    # the per-module blocks print this line too; only the one under
    # "Chip area for top module" is the whole design's.
    seq = re.search(
        r"Chip area for top module.*?used for sequential elements:\s*([\d.]+)",
        yosys_output,
        re.S,
    )

    if hier is not None:
        num_cells = int(hier.group(1))
    else:
        m = re.search(r"^\s*(\d+)(?:\s+\S+)?\s+cells\s*$", yosys_output, re.M)
        num_cells = int(m.group(1)) if m else None

    return {
        "num_cells": num_cells,
        "area_um2": float(area_match.group(1)) if area_match else None,
        "seq_area_um2": float(seq.group(1)) if seq else None,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rtl", nargs="+", required=True, help="repo-relative RTL file(s)")
    ap.add_argument("--top", required=True, help="top module name")
    ap.add_argument("--liberty", required=True, help="repo-relative liberty path")
    ap.add_argument("--out", required=True, help="repo-relative output netlist path")
    ap.add_argument(
        "--macro-lib",
        nargs="*",
        default=[],
        help="liberty file(s) for hard macros, read as blackboxes. Their "
        "behavioural .v must be left out of --rtl.",
    )
    ap.add_argument(
        "--timeout", type=int, default=120, help="Yosys wall-clock limit, seconds"
    )
    ap.add_argument(
        "--no-fsm",
        action="store_true",
        help="skip the fsm pass. Required whenever the netlist is going to be "
        "equivalence-checked module by module against the RTL.",
    )
    args = ap.parse_args()

    raw = run_synth(args.rtl, args.top, args.liberty, args.out, args.macro_lib, args.timeout, not args.no_fsm)
    stat = parse_stat(raw)
    print(f"synthesized {args.top} -> {args.out}: {stat}", file=sys.stderr)


if __name__ == "__main__":
    main()
