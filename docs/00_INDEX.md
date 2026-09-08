# Nebula Runbook — Master Index & Topic Scope

**Start here**: `01_pipeline_overview.md` — the full end-to-end pipeline map
(all 10 steps, every tool, every file, exactly where the LLM enters and what
its input/output is). Read that first, then use this index for stage-by-
stage depth.

Tracks every concept/tool this project touches, whether it has a detailed
runbook doc yet, and where it will be covered. Update this file whenever a
new topic gets introduced anywhere in the project (a stage, a tool, a
technique) — nothing should be used without eventually getting a "what/why/
how/code" writeup here. This is the master list the final "book" gets
assembled from.

Each topic doc must cover, at minimum: **what it is, why it's needed, exact
commands/code used, how to read its output/report, problems hit + fixes.**

## Status legend
- Done — doc written, content verified against actual project files
- In progress — doc exists but incomplete, or concept covered but no
  hands-on run yet
- Planned — not yet started, but scheduled at a specific stage

## Topics

| Topic | Covered in | Status |
|---|---|---|
| STA fundamentals (slack, WNS/TNS, setup/hold, arrival/required time) | `runbook_stage0_sta_fundamentals.md` | Done |
| SDC basics (`create_clock`, `set_input_delay`/`set_output_delay`) | `runbook_stage0_sta_fundamentals.md` | Done |
| Generated clocks (`create_generated_clock`) | `runbook_stage1_sdc_constraints.md` | Done |
| Multicycle path exceptions (`set_multicycle_path`) | `runbook_stage1_sdc_constraints.md` | Done |
| Retiming (as an RTL-fix technique) | `runbook_stage0_sta_fundamentals.md` | Done |
| CDC (clock domain crossing, synchronizers, async FIFO) | `runbook_stage6_prep_soc_cdc_concepts.md` | In progress (concepts only, no code yet — code comes with Stage 6 RTL) |
| Why 5 clocks / ~10 domains / ~50k cells (benchmark sizing) | `runbook_stage6_prep_soc_cdc_concepts.md` | Done |
| TCL fundamentals (needed to script Yosys/OpenSTA/EQY) | — | Planned — Stage 2 |
| Yosys synthesis scripting (beyond the one-off scripts used in Stage 0/1) | — | Planned — Stage 3, incl. `run_synth.py`/script wrapper |
| OpenSTA scripting for structured JSON output (the LLM's input format) | — | Planned — Stage 4, incl. `run_sta.py`/script wrapper |
| **Clock gating** | — | Planned — not yet hit in ORFS default flow; add when Stage 6 RTL adds power-aware gating |
| **CTS — Clock Tree Synthesis** (skew, insertion delay, buffer insertion) | `runbook_stage5_orfs_ppa_flow.md` | Done — native `gcd` run, 0.01ns setup skew, WNS -1.39ns post-CTS |
| Floorplanning, placement, routing | `runbook_stage5_orfs_ppa_flow.md` | Done |
| PPA reporting (area/power/timing) — reading ORFS's final reports | `runbook_stage5_orfs_ppa_flow.md` | Done — real numbers: 4977um² @ 85% util, 8.56mW, WNS -1.47ns |
| Full 5-domain/50k-cell benchmark RTL — actual code, actual SDC | — | Planned — Stage 6 |
| SymbiYosys/EQY formal equivalence checking (script, `.sby` config, pass/fail reading) | — | Planned — Stage 7, must be built before Stage 8 per project's non-negotiable design rule |
| Claude API tool-use agentic loop (`run_sta`→`propose_and_apply_edit`→`resynth_and_check`) | — | Planned — Stage 8 |
| Python orchestration / glue / end-to-end demo command | — | Planned — Stage 9 |
| ORFS native-build toolchain setup (CUDD, zstd, icu4c, boost::stacktrace, pinned-Yosys `-c` flag) | `runbook_stage5_orfs_ppa_flow.md` | Done |

## Rule going forward
Any time a new tool, script, report type, or concept gets used anywhere in
this project (including ones not yet anticipated — e.g. floorplan-specific
concepts, power analysis, DFT if it comes up), add a row here immediately,
then fill in its doc once that part of the work is actually done and
verified (not before — docs describe what was actually run, not planned
work).
