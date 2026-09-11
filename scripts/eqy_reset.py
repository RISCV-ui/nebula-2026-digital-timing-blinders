#!/usr/bin/env python3
"""Reset-constrained bounded RTL-to-netlist equivalence.

The unrestricted EQY sweep is intentionally stronger: it compares arbitrary
initial states. Synthesis is allowed to remove unreachable state encodings,
though, and that leaves several sequential modules unproved even when their
post-reset behaviour is identical. This runner adds the hardware contract the
chip actually uses: every reset is asserted in the initial formal step, and
outputs are compared only after each clock domain has observed reset.

Every positive proof is paired with a negative control that inverts one output.
The negative control matters because a reset mask or a shallow bound can make a
property vacuous; a checker that cannot reject that mutation has earned no
proof claim.
"""

import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import tempfile
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
YOSYS = REPO_ROOT / "oss-cad-suite" / "bin" / "yosys"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_bounded(command: list[str], cwd: Path, timeout: int) -> tuple[int | None, str, float]:
    start = time.time()
    process = subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout)
        return process.returncode, output, round(time.time() - start, 1)
    except subprocess.TimeoutExpired:
        # Killing the process group prevents solver descendants from surviving
        # a timeout and consuming CPU after the report has moved to a new arm.
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        return None, output, round(time.time() - start, 1)


def verilog_decl(name: str, port: dict, prefix: str = "") -> str:
    width = len(port["bits"])
    vector = "" if width == 1 else f"[{width - 1}:0] "
    return f"{vector}{prefix}{name}"


def reset_pairs(ports: dict) -> list[tuple[str, str]]:
    if "clk" in ports and "rst" in ports:
        return [("clk", "rst")]
    return [
        (clock, f"rst{clock[3:]}")
        for clock in ports
        if clock.startswith("clk_") and f"rst{clock[3:]}" in ports
    ]


def make_miter(module: str, ports: dict, path: Path, corrupt: bool) -> str:
    inputs = [(name, port) for name, port in ports.items() if port["direction"] == "input"]
    outputs = [(name, port) for name, port in ports.items() if port["direction"] == "output"]
    pairs = reset_pairs(ports)
    if not pairs:
        raise ValueError(f"{module}: no clk/rst port pair found")
    if not outputs:
        raise ValueError(f"{module}: no output exists to compare")

    lines = ["module reset_miter(" + ",".join(name for name, _ in inputs) + ");"]
    lines.extend(f"input {verilog_decl(name, port)};" for name, port in inputs)
    for name, port in outputs:
        lines.append(f"wire {verilog_decl(name, port, 'gold_')};")
        lines.append(f"wire {verilog_decl(name, port, 'gate_')};")
    for index, (clock, reset) in enumerate(pairs):
        lines.append(f"reg reset_seen_{index} = 1'b0;")
        lines.append(f"always @(posedge {clock}) if ({reset}) reset_seen_{index} <= 1'b1;")

    for instance, core, prefix in (("gold_i", "gold_core", "gold_"), ("gate_i", "gate_core", "gate_")):
        connections = []
        for name, port in ports.items():
            signal_name = name if port["direction"] == "input" else f"{prefix}{name}"
            connections.append(f".{name}({signal_name})")
        lines.append(f"{core} {instance}(" + ",".join(connections) + ");")

    gold_outputs = [f"gold_{name}" for name, _ in outputs]
    if corrupt:
        gold_outputs[0] = f"~{gold_outputs[0]}"
    gate_outputs = [f"gate_{name}" for name, _ in outputs]
    reset_ready = " && ".join(f"reset_seen_{index}" for index in range(len(pairs)))

    lines.append("always @* begin")
    for _, reset in pairs:
        lines.append(f"  if ($initstate) assume({reset});")
    lines.append(
        f"  if ({reset_ready}) assert({{{','.join(gold_outputs)}}} == "
        f"{{{','.join(gate_outputs)}}});"
    )
    lines.extend(("end", "endmodule"))
    path.write_text("\n".join(lines) + "\n")
    return outputs[0][0]


def make_yosys_script(
    module: str,
    rtl_files: list[Path],
    netlist: Path,
    liberty: Path,
    miter: Path,
    depth: int,
    vcd: Path,
) -> str:
    rtl = " ".join(str(path) for path in rtl_files)
    return f"""read_verilog {rtl}
setattr -mod -unset keep_hierarchy
prep -flatten -top {module}
memory_map
opt -fast
rename {module} gold_core
design -stash gold

read_liberty -ignore_miss_func {liberty}
read_verilog {netlist}
setattr -mod -unset keep_hierarchy
prep -flatten -top {module}
memory_map
opt -fast
rename {module} gate_core
design -stash gate

design -copy-from gold -as gold_core gold_core
design -copy-from gate -as gate_core gate_core
read_verilog -formal {miter}
prep -flatten -top reset_miter
chformal -lower
sat -seq {depth} -set-assumes -prove-asserts -verify -dump_vcd {vcd}
"""


def read_ports(rtl_files: list[Path], work: Path, timeout: int) -> dict:
    metadata = work / "rtl.json"
    script = work / "ports.ys"
    script.write_text(
        f"read_verilog {' '.join(str(path) for path in rtl_files)}\n"
        f"proc\nwrite_json {metadata}\n"
    )
    code, output, _ = run_bounded([str(YOSYS), "-q", "-s", str(script)], work, timeout)
    if code != 0 or not metadata.exists():
        raise RuntimeError(f"could not read RTL ports:\n{output[-2000:]}")
    return json.loads(metadata.read_text())["modules"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rtl", required=True, type=Path)
    parser.add_argument("--netlist", required=True, type=Path)
    parser.add_argument("--liberty", required=True, type=Path)
    parser.add_argument("--modules", required=True, nargs="+")
    parser.add_argument("--depth", type=int, default=5)
    parser.add_argument("--timeout", type=int, default=90)
    parser.add_argument("--base-report", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    args.rtl = args.rtl.resolve()
    args.netlist = args.netlist.resolve()
    args.liberty = args.liberty.resolve()
    args.out = args.out.resolve()
    if args.base_report:
        args.base_report = args.base_report.resolve()

    if not YOSYS.exists():
        raise SystemExit(f"yosys not found at {YOSYS}")
    rtl_files = sorted(args.rtl.glob("*.v")) if args.rtl.is_dir() else [args.rtl]
    if not rtl_files:
        raise SystemExit(f"no RTL files found in {args.rtl}")
    for path in (*rtl_files, args.netlist, args.liberty):
        if not path.exists():
            raise SystemExit(f"missing input: {path}")

    args.out.mkdir(parents=True, exist_ok=True)
    log_dir = args.out / "logs"
    log_dir.mkdir(exist_ok=True)
    results = []

    with tempfile.TemporaryDirectory(prefix="nebula-reset-eqy-") as temp_name:
        work = Path(temp_name)
        modules = read_ports(rtl_files, work, args.timeout)
        for module in args.modules:
            if module not in modules:
                results.append({"module": module, "status": "MISSING_MODULE", "proved": False})
                continue
            ports = modules[module]["ports"]
            attempts = []
            for corrupt, label in ((False, "positive"), (True, "negative_control")):
                miter = work / f"{module}.{label}.v"
                mutation_output = make_miter(module, ports, miter, corrupt)
                script = work / f"{module}.{label}.ys"
                vcd = work / f"{module}.{label}.vcd"
                script.write_text(
                    make_yosys_script(module, rtl_files, args.netlist, args.liberty, miter, args.depth, vcd)
                )
                code, output, seconds = run_bounded(
                    [str(YOSYS), "-s", str(script)], work, args.timeout
                )
                (log_dir / f"{module}.{label}.log").write_text(output)
                proof_success = code == 0 and "SAT proof finished - no model found: SUCCESS!" in output
                counterexample = code not in (None, 0) and "proof did fail" in output
                attempts.append(
                    {
                        "kind": label,
                        "returncode": code,
                        "seconds": seconds,
                        "proof_success": proof_success,
                        "counterexample_found": counterexample,
                    }
                )
            positive, negative = attempts
            proved = positive["proof_success"] and negative["counterexample_found"]
            if proved:
                status = "PROVED_RESET_CONSTRAINED"
            elif positive["returncode"] is None or negative["returncode"] is None:
                status = "TIMEOUT"
            elif not positive["proof_success"]:
                status = "UNPROVEN"
            else:
                status = "NEGATIVE_CONTROL_NOT_DETECTED"
            results.append(
                {
                    "module": module,
                    "status": status,
                    "proved": proved,
                    "depth": args.depth,
                    "negative_control_output": mutation_output,
                    "attempts": attempts,
                }
            )
            print(f"{module}: {status}")

    base_proved = 0
    base_total = None
    base_sha = None
    if args.base_report:
        base = json.loads(args.base_report.read_text())
        base_proved = sum(bool(result.get("equivalent")) for result in base.get("results", []))
        base_total = len(base.get("results", []))
        base_sha = sha256(args.base_report)

    new_proved = sum(result["proved"] for result in results)
    summary = {
        "method": "reset-constrained bounded RTL-to-netlist equivalence",
        "depth": args.depth,
        "reset_contract": "all reset inputs asserted in initial formal step; compare after every domain observes reset",
        "negative_control": "first output inverted; a valid run must find a counterexample",
        "modules_requested": len(args.modules),
        "modules_proved": new_proved,
        "base_unrestricted_proved": base_proved,
        "base_total": base_total,
        "combined_modules_with_formal_evidence": base_proved + new_proved,
        "inputs": {
            "rtl": [{"path": str(path), "sha256": sha256(path)} for path in rtl_files],
            "netlist": {"path": str(args.netlist), "sha256": sha256(args.netlist)},
            "liberty": {"path": str(args.liberty), "sha256": sha256(args.liberty)},
            "base_report": (
                {"path": str(args.base_report), "sha256": base_sha} if args.base_report else None
            ),
        },
        "results": results,
    }
    (args.out / "report.json").write_text(json.dumps(summary, indent=2) + "\n")

    lines = [
        "# Reset-constrained equivalence supplement",
        "",
        f"**{new_proved}/{len(args.modules)} targeted modules proved at depth {args.depth}.**",
        "",
        (
            f"Combined coverage: **{base_proved + new_proved}/{base_total} modules have formal evidence** "
            f"({base_proved} unrestricted EQY proofs plus {new_proved} reset-constrained bounded proofs)."
            if base_total is not None
            else ""
        ),
        "",
        "This does not rewrite the unrestricted EQY result. The supplement declares reset because synthesis removed unreachable state encodings that arbitrary-initial-state induction could not match.",
        "",
        "Each row includes a negative control that inverts the named output. PASS means the real comparison proved and the corrupted comparison produced a counterexample.",
        "",
        "| Module | Result | Depth | Negative control |",
        "|---|---:|---:|---|",
    ]
    for result in results:
        negative = result.get("negative_control_output", "-")
        lines.append(f"| `{result['module']}` | {result['status']} | {result.get('depth', '-')} | invert `{negative}` |")
    lines.extend(("", "Full hashes, timings, and return codes are in `report.json`; raw Yosys transcripts are in `logs/`.", ""))
    (args.out / "report.md").write_text("\n".join(lines))
    return 0 if new_proved == len(args.modules) else 1


if __name__ == "__main__":
    raise SystemExit(main())
