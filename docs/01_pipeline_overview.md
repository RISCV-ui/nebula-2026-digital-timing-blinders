# Pipeline Overview — Full Flow, Tools, Files, and Where the LLM Enters

Read this before diving into individual stage docs — it's the map of how
everything connects end to end. Individual stage docs (`runbook_stageN_*.md`)
go deep on one step at a time; this doc shows how the steps chain together.

## The full pipeline

```
1. RTL source (Verilog)          rtl/stageN/*.v
        |
2. Synthesis (Yosys)             yosys -p "read_verilog...; synth; write_verilog"
   -> gate-level netlist           *_synth.v
        |
3. SDC constraints (hand-written) rtl/stageN/*.sdc
        |
4. STA (OpenSTA, via openroad -exit)
   -> run_sta.tcl script reads netlist+SDC, runs report_checks
   -> structured JSON output       artifacts/*.json  (ranked critical paths + slack)
        |
   ========== THIS JSON IS THE LLM'S INPUT ==========
        |
5. LLM call (Claude API, Stage 8)
   Input:  the JSON (critical path list) + the actual RTL snippet around
           the worst path (file, line range)
   Output: an EDITED RTL snippet, constrained to exactly one of 4 techniques
           (pipelining / restructuring / retiming / FSM re-encode) --
           NOT prose, a tool_use structured code edit
   File that does this: propose_and_apply_edit.py (Stage 8)
        |
6. Re-synthesis + re-STA (same Yosys/OpenSTA scripts as step 2-4, rerun on
   the edited RTL) -- did slack improve?
        |
7. Formal equivalence check (EQY/SymbiYosys, Stage 7)
   .sby config compares original RTL vs edited RTL bit-for-bit logically
   equivalent? If NO -> reject edit, discard, try a different fix or move to
   the next critical path. If YES -> accept edit, keep it.
        |
8. Loop steps 4-7 until timing closes (WNS >= 0) or iteration budget runs out
        |
9. Full PPA flow (OpenROAD via ORFS `make`)
   floorplan -> placement -> CTS -> routing -> final area/power/timing report
   File: flow/designs/<platform>/<design>/config.mk (per-design config)
        |
10. Python glue (Stage 9): one command runs steps 1-9 end-to-end + produces
    the demo (before/after RTL, before/after slack, EQY pass/fail trail)
```

## Build status vs plan (update this table as stages complete)

| Step | What it does | Status |
|---|---|---|
| 1-4: RTL -> synth -> SDC -> STA -> JSON | Single-module hand-run flow | Built and working (Stage 0/1) |
| 5: LLM proposes edit | Claude API tool-use call | Not started (Stage 8) |
| 6: Loop re-check | Re-run steps 2-4 on edited RTL | Not started (Stage 8) |
| 7: EQY formal equivalence gate | Reject bad edits before acceptance | Not started (Stage 7) — must exist before Stage 8 per project rule |
| 9: Full PPA flow (ORFS) | floorplan/place/CTS/route + reports | In progress — native `gcd`/sky130hd run being validated |
| 10: End-to-end glue + demo | One command, full pipeline | Not started (Stage 9) |

## LLM connection — exact mechanics (Stage 8, not yet built)
- **Trigger**: after step 4 produces the ranked critical-path JSON.
- **Input to the LLM**: that JSON (path, slack, involved cells/pins) plus a
  snippet of the actual `.v` source at the flagged lines.
- **Output from the LLM**: a `tool_use` block containing edited RTL text —
  not free-form chat prose — following Anthropic's documented tool-use
  pattern (structured `tool_use` blocks, loop keyed on `stop_reason`, per
  the project's own coding conventions).
- **File responsible**: `propose_and_apply_edit.py` (Anthropic Python SDK),
  called from the Stage 9 orchestration loop. Does not exist yet — comes
  only after the Stage 7 EQY gate is working, by explicit project design
  rule: never let the LLM edit RTL without the safety net already in place.

## On the one-time nature of today's installation work
Everything fixed while getting ORFS to build natively on this Mac (CUDD,
zstd, icu4c, boost::stacktrace, fmt header includes, Anaconda PATH
contamination, the pinned-Yosys `-c` flag incompatibility with mainline
Yosys) is a ONE-TIME native compile of the toolchain binaries
(`tools/install/OpenROAD/bin/openroad`, `tools/install/yosys/bin/yosys`).
Once built, every future `make` run in `flow/` reuses these binaries
directly — no rebuilding, no re-fixing. This would only need repeating if
the `orfs/` repo is wiped or the project moves to a different machine. The
full installation checklist (as a reusable, from-scratch runbook) gets
written up once the current native build is fully confirmed working
end-to-end (see `docs/00_INDEX.md` scope table, last row).
