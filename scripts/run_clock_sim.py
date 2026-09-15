#!/usr/bin/env python3
"""Simulate the clock structures and count runt pulses, old tree vs fixed tree.

clockcheck.py is structural: it recognises shapes. That is cheap and it is what
runs inside the loop, but a shape recogniser saying SAFE_MUX is not evidence
that the waveform is clean -- it is evidence that the RTL matches a pattern
somebody wrote down. This is the evidence.

Both trees are simulated against the same testbench, which changes the divider
select 2 ns after a rising edge -- the selected clock high, exactly the moment a
combinational mux cuts a pulse -- and toggles the gate enable at odd phases. It
measures pulse widths on both outputs and counts anything narrower than a half
period of the undivided clock.

The old tree is run precisely so the test can be shown to fail: a runt check
that passes on a design known to produce runts is measuring nothing.

    usage: scripts/run_clock_sim.py [--out artifacts/clocksim.json]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "bench" / "tb" / "tb_clk.v"
FILES = ["clk_gate.v", "clk_div_mux.v"]

# Wall-clock ceiling per arm. The simulation is ~9 us of model time and takes
# under a second idle; a minute is only there so a wedged run reports instead
# of hanging the pipeline.
TIMEOUT_S = 60


def run(tree: Path, work: Path) -> dict:
    vvp = work / f"{tree.name}.vvp"
    srcs = [str(TB)] + [str(tree / f) for f in FILES]
    comp = subprocess.run(["iverilog", "-g2005", "-o", str(vvp)] + srcs,
                          capture_output=True, text=True)
    if comp.returncode:
        return {"rtl": str(tree), "error": comp.stderr.strip()[:400]}

    sim = subprocess.run(["vvp", str(vvp)], capture_output=True, text=True,
                         timeout=TIMEOUT_S, stdin=subprocess.DEVNULL)
    log = sim.stdout

    def count(kind):
        m = re.search(rf"^{kind}\s*:\s*(\d+) transitions, (\d+) runts$",
                      log, re.M)
        return (int(m.group(1)), int(m.group(2))) if m else (None, None)

    gate_edges, gate_runts = count("gate")
    mux_edges, mux_runts = count("mux")
    ratios = re.findall(r"^sel=(\d+): (\d+) rising edges in (\d+) ns "
                        r"\(expected (\d+)\)$", log, re.M)
    return {
        "rtl": str(tree.relative_to(ROOT)),
        "gate_transitions": gate_edges, "gate_runts": gate_runts,
        "mux_transitions": mux_edges, "mux_runts": mux_runts,
        "ratio_checks": len(ratios),
        "ratio_mismatches": sum(1 for r in ratios if r[1] != r[3]),
        "verdict": "PASS" if "RESULT PASS" in log else "FAIL",
        "log": log.strip().splitlines(),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "artifacts" / "clocksim.json"))
    ap.add_argument("--fixed", default=str(ROOT / "bench" / "rtl_v2"))
    ap.add_argument("--old", default=str(ROOT / "bench" / "rtl"),
                    help="tree with the pre-fix structures, run as a control")
    a = ap.parse_args()

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        res = {"fixed": run(Path(a.fixed), work),
               "control": run(Path(a.old), work)}

    # The pair is the result, not either half of it. The fixed tree must be
    # clean AND the control must be dirty; a control that comes back clean
    # means the stimulus stopped reaching the bug and the PASS above is worth
    # nothing.
    ok = (res["fixed"].get("verdict") == "PASS"
          and res["control"].get("verdict") == "FAIL"
          and not res["fixed"].get("ratio_mismatches"))
    res["verdict"] = "PASS" if ok else "FAIL"
    res["runts_fixed"] = ((res["fixed"].get("gate_runts") or 0)
                          + (res["fixed"].get("mux_runts") or 0))
    res["runts_control"] = ((res["control"].get("gate_runts") or 0)
                            + (res["control"].get("mux_runts") or 0))

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(res, indent=2) + "\n")

    print(f"fixed   {res['fixed'].get('verdict')}  "
          f"{res['runts_fixed']} runt(s), "
          f"{res['fixed'].get('ratio_checks')} ratio checks, "
          f"{res['fixed'].get('ratio_mismatches')} mismatch(es)")
    print(f"control {res['control'].get('verdict')}  "
          f"{res['runts_control']} runt(s)  (expected to fail)")
    print(res["verdict"], "->", out)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
