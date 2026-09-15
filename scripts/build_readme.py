#!/usr/bin/env python3
"""Write README.md -- the one entry document -- from the report's own numbers.

The repo had two entry documents (README.md and SUBMISSION_PACKAGE_README.md),
both written by hand against the v1 submission, and both already disagreed
with the report after the v2 benchmark and the v3 routes landed. A reviewer
who reads a stale headline number before opening the PDF has been handed a
contradiction by us, so the README is generated from report/generated/
numbers.tex exactly like every figure in the report.

    usage: scripts/build_readme.py [--out README.md]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NUMBERS = ROOT / "report" / "generated" / "numbers.tex"


def macros() -> dict[str, str]:
    out = {}
    for m in re.finditer(r"\\newcommand\{\\(\w+)\}\{(.*)\}", NUMBERS.read_text()):
        val = m.group(2)
        val = val.replace(r"\,", ",").replace(r"\_", "_").replace(r"\%", "%")
        val = re.sub(r"\\[a-zA-Z]+\{([^}]*)\}", r"\1", val)
        out[m.group(1)] = val.strip()
    return out


def need(n: dict, *keys: str) -> None:
    missing = [k for k in keys if k not in n]
    if missing:
        raise SystemExit("numbers.tex is missing: " + ", ".join(missing) +
                         " -- run scripts/build_report.py first")


TEMPLATE = """\
# Constraint Optimization through RTL Enhancement Using Generative AI

**Astera Labs Nebula 2026 — Digital Track**
**Team Timing Blinders:** Shubhanshu Shivhare, Nagarjun BV — IIT Bombay

An LLM proposes RTL timing fixes. Deterministic EDA and formal tools decide
which of them are allowed to survive. The input RTL is frozen. No edit
reaches the reported design without passing structural validation, formal
equivalence (or an explicitly declared latency contract), CDC and clock-
structure checks, and a full OpenROAD route.

## Read this first

**`report/nebula_report.pdf`** is the submission. Every number in it is
regenerated from the run artifacts in this repository by `scripts/build_report.py`;
none is typed into the LaTeX source, and a missing artifact renders as a
visible `[pending]` marker rather than as a zero. This README is generated the
same way, from the same file, so the two cannot drift apart.

Three commands, no toolchain and no API key, from a clean clone:

```sh
git clone https://github.com/RISCV-ui/nebula-2026-digital-timing-blinders.git
cd nebula-2026-digital-timing-blinders
python3 scripts/submission_check_v2.py   # must print READY
python3 demo_v2.py                       # eight acts over the recorded runs
open report/nebula_report.pdf            # the report itself
```

The check re-derives every number in the PDF from the artifacts committed here
and fails if any of them no longer matches. The evidence those two commands
read is tracked in git on purpose, including the per-candidate proposals and
the OpenROAD reports; only the multi-gigabyte tool databases are left out.

## Headline

| | |
|---|---|
| Candidate edits proposed | {numcandidates} |
| Accepted after all gates | {numaccepted} |
| Rejected by the latency contract alone | {numcontractkills} |
| Best per-domain gain | `{bestclock}` {bestdelta} ns ({bestfmaxfrom} → {bestfmaxto} MHz) |
| Two independent models, same transform, netlists agree within | {bestagreement} ns |
| Module-level netlist equivalence | {eqyproved} proved of {eqychecked} checked |
| Clock-structure audit | {clockverdict}, {clockfindings} findings, {clockglitchy} glitchy |
| Runt-pulse simulation | {runtsfixed} runts in the repaired design, {runtscontrol} in the negative control |
| Model API spend, whole bake-off | ${bakeoffspend} |

The baseline worst negative slack is {baselinewns} ns on a divider path, and
that path does **not** close. See "What this does not claim" in the report.
Gains are per-domain; the chip is still governed by its slowest domain.

## What is in this repository

| Path | What it is |
|---|---|
| `report/` | The report, its LaTeX source, and `generated/`, which holds every table and number as an `\\input` fragment |
| `bench/rtl_v2/` | The frozen benchmark RTL: five asynchronous masters, generated clocks, CDC, dividers |
| `bench/constraints/nebula.sdc` | The constraint set the whole flow is timed against |
| `bench/scripts/loop.py` | The proposer loop and the system prompt the model is held to |
| `bench/scripts/metrics.py`, `ppa_report.py` | Post-route metric extraction and the before/after comparison |
| `demo_v2.py` | The interactive demo: eight acts over the recorded artifacts, about a second, no network |
| `scripts/` | Report, figure, README, packaging and verification scripts |
| `artifacts/bakeoff_v2*/`, `artifacts/divider_run/` | The runs the report counts, one `history.jsonl` per arm |
| `artifacts/metrics_v2_*/` | Post-route metrics for the pair the headline is taken from |
| `artifacts/metrics_v3_*/` | Post-route metrics for the second, wider-floorplan generation |
| `artifacts/model_ppa_v3/pnr_*/reports/` | OpenROAD reports and logs for those routes |
| `artifacts/eqy/shards/`, `artifacts/eqy_v2_serial_partial.log` | Netlist-vs-RTL equivalence evidence |
| `artifacts/clockcheck_v2.json`, `artifacts/clocksim.json` | Clock-structure audit and the runt-pulse simulation |
| `output/rtl_variants_v2/` | The RTL trees actually routed, one per accepted variant |
| `docs/`, `WORKLOG.md` | Design notes and the dated build log |

Tool workdirs (`.odb`, `.def`, `.gds`) are deliberately excluded: they are
gigabytes and are reproducible from the flow below.

## Reproducing

```sh
# 1. the loop, one model, over the sliced targets
python3 bench/scripts/loop.py --targets artifacts/paths/v2_targets.json \\
    --rtl bench/rtl_v2 --backend anthropic:sonnet-direct \\
    --out artifacts/run --g1-timeout 300 --order closeable

# 2. build the verified RTL variants from the gate decisions
python3 scripts/prepare_variants_v2.py

# 3. place and route each variant, then compare against the baseline
bash scripts/run_variant_pnr.sh <variant> <ppa-dir> nebula_bench_v2

# 4. netlist-vs-RTL equivalence, module by module
python3 scripts/eqy_netlist.py --rtl <variant>/rtl --netlist <1_2_yosys.v> \\
    --liberty sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib --depth 5

# 5. regenerate every table, figure, number and this README
python3 scripts/build_report.py && python3 scripts/build_figures.py
python3 scripts/build_readme.py
latexmk -pdf report/nebula_report.tex
```

Steps 1–4 need the toolchain (OSS CAD Suite, EQY, OpenROAD-flow-scripts) and
hours of compute. Step 5 needs only Python and LaTeX and rebuilds the whole
document from the artifacts already committed here.

## The demo

```sh
python3 demo_v2.py            # all eight acts
python3 demo_v2.py --act 3    # just the gate funnel
```

Read-only, from the artifacts in this repository: no API key, no network, no
toolchain. Act 8 re-derives the report's own macros from those artifacts and
diffs them against `report/generated/numbers.tex` on screen.

## Verifying this repository

```sh
python3 scripts/submission_check_v2.py
```

It re-derives the report's numbers from the artifacts, compares them against
the shipped `report/generated/`, and fails if anything in the PDF is no longer
backed by the evidence beside it.

## API keys

No key is in this repository, and `scripts/package_submission_v2.py` refuses to
build an archive that contains a key-shaped string. `bench/scripts/loop.py` reads
credentials from the environment only.

---
*Generated by `scripts/build_readme.py` from `report/generated/numbers.tex`,
{reportgenerated}.*
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=ROOT / "README.md")
    args = ap.parse_args()

    if not NUMBERS.is_file():
        raise SystemExit("run scripts/build_report.py first")
    n = macros()
    need(n, "numaccepted", "numcandidates", "numcontractkills", "bestclock",
         "bestdelta", "bestfmaxfrom", "bestfmaxto", "bestagreement",
         "eqyproved", "eqychecked", "clockverdict", "clockfindings",
         "clockglitchy", "runtsfixed", "runtscontrol", "bakeoffspend",
         "baselinewns", "reportgenerated")
    args.out.write_text(TEMPLATE.format(**n))
    print(f"WROTE {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
