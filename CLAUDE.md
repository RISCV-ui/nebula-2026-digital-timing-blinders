# CLAUDE.md — Nebula 2026 Digital Track Project

This file gives Claude Code full context on this project. Read this before doing
any work in this repo.

**If this folder was just unzipped onto a new machine, read
`LAPTOP_HANDOFF.md` first** — it covers what's missing (toolchain
binaries, intentionally excluded) and exact steps to reinstall + restore our
custom work before doing anything else.

## Competition

**Astera Labs Nebula 2026** — a chip-design hackathon/competition with three
tracks (Digital, Analog, Software). This repo is for the **Digital track**.

- **Team name:** Timing Blinders
- **Team members:** Shubhanshu Shivhare, Nagarjun BV
- **Shubhanshu:** M.Tech Electronics Systems, 2nd year, IIT Bombay. Also works
  as EE department sysadmin/web developer at IIT Bombay, and is deep in
  VLSI/digital design coursework (RTL, synthesis, STA, FPGA). Prefers hands-on,
  step-by-step explanations over dense theory dumps — explain one concept fully,
  confirm understanding, then move on. Currently on macOS.
- **Synopsis deadline:** August 6, 2026 (form-only submission — see below)
- **We also separately registered for the Analog track** ("Straw Hats" team
  name, topic: AI/ML for Analog Circuit Design / PCIe equalizer) — that is a
  DIFFERENT project, not part of this repo.

## The Problem Statement (Digital Track)

**Topic: "Constraint Optimization through RTL Enhancement Using Generative AI"**

Timing closure — making a chip design run at its target clock speed — is one
of the most manual, iterative parts of chip design. Engineers analyze timing
reports, find critical paths (signals that don't arrive before the next clock
edge), and manually rewrite RTL to fix them, then re-run synthesis and repeat.

**Our job:** build a system where an LLM does this instead — reads timing
violations, proposes an RTL fix, and an automated toolchain verifies the fix
actually helps AND doesn't break functional correctness, before accepting it.

### The four allowed RTL-fix techniques
- **Pipelining** — insert a register mid-path to split one slow cycle into two
- **Logic restructuring** — rewrite logic to be functionally identical but
  shorter critical path
- **Retiming** — move existing registers earlier/later without adding new ones
- **FSM optimization** — re-encode state machine states (e.g. one-hot vs binary)

### Required benchmark RTL (what we test the system on)
- 5 independent asynchronous master clock domains
- ≥1 generated clock per master
- Clock domain crossings (CDC) between domains
- Clock divider logic at multiple ratios
- ~50,000 standard cells (realistic SoC-subsystem scale, not a toy example)

### Official Nebula deliverables (score against this checklist)
1. RTL timing analysis framework
2. GenAI-based RTL optimization engine
3. Critical path and timing violation analysis
4. Optimized RTL implementation
5. Timing, frequency and PPA comparison (before/after)
6. Formal equivalence verification report (proves optimized RTL == original)
7. Interactive demo showcasing the RTL optimization workflow

### Official tools listed by Nebula
Verilog/SystemVerilog, OpenSTA, Yosys, OpenROAD, SymbiYosys/EQY, Python,
LLM/GenAI frameworks.

## Architecture We're Building

```
run_sta(netlist, sdc)
    → wraps OpenSTA, returns ranked critical paths + slack as structured JSON

propose_and_apply_edit(critical_path, rtl_snippet)
    → the LLM call. Constrained to propose ONE of: pipelining, logic
      restructuring, retiming, FSM re-encoding. Emits edited RTL, not prose.

resynth_and_check(original.v, edited.v)
    → wraps Yosys (re-synthesis), OpenSTA (re-run STA, compare slack), and
      EQY (formal equivalence gate). REJECTS the edit if EQY fails.

Loop: run_sta → propose_and_apply_edit → resynth_and_check →
      (if improved AND equivalent) accept, else retry/move to next path →
      repeat until timing closure or iteration budget exhausted.
```

**Non-negotiable design principle:** the EQY formal-equivalence gate must be
built and working BEFORE the LLM loop is wired up. Never let the LLM edit RTL
without the safety net already in place — we should never be demoing on
unverified output.

## Toolchain

- **OSS CAD Suite** — bundles Yosys, OpenSTA, and other tools. Install:
  `curl -L -o oss-cad-suite.tgz https://github.com/YosysHQ/oss-cad-suite-build/releases/latest/download/oss-cad-suite-darwin-arm64.tgz`
  (Shubhanshu is on Apple Silicon Mac — use `-darwin-arm64`, not `-darwin-x64`
  or `-linux-x64`). After extracting: `source oss-cad-suite/environment`, and
  run `xattr -dr com.apple.quarantine oss-cad-suite/` once to avoid Gatekeeper
  popups blocking every binary.
- **OpenROAD-flow-scripts (ORFS)** — full RTL-to-GDS flow, our primary PPA tool.
  Uses **sky130hd** as the default open PDK — use this PDK for the benchmark
  design too, for reproducibility across stages.
  https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts
- **YosysHQ/eqy** and **YosysHQ/sby** — formal equivalence checking
  (github.com/YosysHQ/eqy, github.com/YosysHQ/sby)
- **Icarus Verilog** (`iverilog`/`vvp`) — simulation, bundled in OSS CAD Suite
- **Claude API** — the LLM in the loop (this project uses Claude specifically;
  Anthropic's tool-use / agentic-loop pattern is the reference architecture)

### Alternate combined installer (if OSS CAD Suite setup is painful)
`github.com/nishit0072e/RTL-to-GDSII` — hands-free installer bundling Yosys +
OpenSTA + OpenROAD + GTKWave + KLayout together.

## Project Roadmap (10 stages — see full detail in the study plan PDF)

0. Digital logic & Verilog/RTL refresher
1. STA fundamentals & SDC constraints
2. TCL fundamentals (needed for Yosys/OpenSTA/EQY scripting — all TCL-based)
3. Yosys (synthesis)
4. OpenSTA (timing analysis) — write TCL script that outputs ranked critical
   paths + slack as parseable JSON; this becomes the LLM's input context
5. OpenROAD-flow-scripts (full RTL-to-GDS run, PPA numbers)
6. Build the actual 5-clock-domain, ~50K-cell benchmark RTL
7. SymbiYosys/EQY equivalence checking — build and test the gate BEFORE Stage 8
8. LLM/GenAI agentic loop — wire Claude API tool-use into the actual
   run_sta → propose_and_apply_edit → resynth_and_check loop
9. Python glue — one command that runs the full pipeline end-to-end + demo

A full PDF (`Nebula_Master_Plan.pdf`) with detailed sub-steps, free resources,
video lectures, paid course references, and reading order for all of this
already exists — ask Shubhanshu for it if deeper stage detail is needed than
what's summarized here.

## Key Reference Papers (read in this order)

Core LLM-RTL papers:
1. AiEDA (arxiv.org/html/2412.09745v1) — big-picture survey of LLM+EDA feedback loops
2. AutoChip (arxiv.org/abs/2411.11856) — simplest working example of the
   LLM-writes-code / tool-gives-feedback / LLM-fixes loop. **Clone the actual
   repo** (github.com/shailja-thakur/AutoChip) when building Stage 8 — read
   real working code, not just the paper, at that point.
3. Rethinking LLM-Based RTL Code Optimization (arxiv.org/abs/2507.16808) —
   benchmark + finding that LLMs are weaker specifically on timing-critical
   rewrites
4. SymRTLO (arxiv.org/abs/2504.10369) — RAG + symbolic reasoning, includes an
   FSM state-merging module directly relevant to our "FSM optimization" technique
5. **ViTAD (arxiv.org/pdf/2508.13257) — THE most important paper.** Nearly
   identical architecture to ours: parse Verilog + timing report → build
   dependency graph → LLM infers root cause → generate targeted fix. Reports
   73.68% repair success rate vs. 54.38% for plain-LLM baseline — use this as
   our benchmark to compare against / beat.
6. TIMINGLLM (RAG-based FPGA timing closure) — comparison point to ViTAD
7. ChipSeek (arxiv.org/html/2507.04736v2) — optional, reframes the loop as RL
   reward shaping instead of a hard accept/reject gate
8. Closing the Loop on LLM-Generated RTL Assertions (arxiv.org/pdf/2606.21451)
   — read right before building Stage 7's EQY gate; same "reject low-quality
   AI output via formal check" pattern

Physical Design / PPA literature (separate track, read alongside Stage 5):
9. Timing-Driven Global Placement by Efficient Critical Path Extraction
   (arxiv.org/abs/2503.11674)
10. ML Framework for Register Placement Optimization (arxiv.org/pdf/1801.02620)
    — directly relevant to our "retiming" technique
11. Deep Representation Learning for EDA survey (arxiv.org/pdf/2505.02105)

Agentic-architecture inspiration (read alongside Stage 8):
- SWE-agent (github.com/SWE-agent/SWE-agent) — general autonomous coding-agent
  framework
- "Automated QoR improvement in OpenROAD with coding agents" (arxiv 2601.06268)
  — applies SWE-agent to OpenROAD PPA improvement; methodologically close to us
- ASIC-Agent (arxiv.org/abs/2508.15940) — closest published system to our
  ambition, explicitly Claude-4-Sonnet-powered. **Code repo link unconfirmed**
  — paper claims open-source but URL doesn't resolve via search. If needed,
  email authors: ahmedeallam@aucegypt.edu / youssef-mansour@aucegypt.edu /
  mshalan@aucegypt.edu

Curated repo hubs (search these before doing a fresh web search):
- github.com/FCHXWH823/LLM4ChipDesign (LLM+hardware, primary hub)
- github.com/DfX-NYUAD/LLM4IC (secondary LLM+hardware hub)
- github.com/Thinklab-SJTU/awesome-ai4eda (classical/ML EDA, placement/routing side)

## What Actually Wins (not just what's required)

1. **A clear novelty claim** — e.g. "unlike ViTAD, which only diagnoses root
   cause, we close the loop with formal equivalence checking before accepting
   any edit." The EQY gate is a genuine differentiator vs. most cited papers.
2. **Honest, quantified results** — report actual before/after slack numbers
   and how many of N critical paths closed, not a vague "improved timing"
   claim. Partial success reported honestly (cite ViTAD's 73.68%) is more
   credible than an unsubstantiated claim of full success.
3. **A working live demo** beats a bigger claim with no runnable artifact.
4. **Final report/slides structured around the official Nebula deliverables
   checklist above, item by item** — judges are likely scoring against it directly.

## Coding Conventions / Notes for Claude Code

- All tool orchestration (Yosys, OpenSTA, EQY invocation) should go through
  Python's `subprocess` module — all three tools accept script files/TCL and
  run non-interactively.
- Keep every intermediate artifact (netlist versions, STA reports, EQY logs)
  on disk tagged with a run ID — needed for the demo to show a clear
  before/after diff and the equivalence-check trail.
- TCL is used for the actual Yosys/OpenSTA/EQY scripts themselves (not
  Python) — Python is the orchestration/glue layer calling out to TCL-scripted
  tools via subprocess.
- Prefer building and testing each tool wrapper (`run_sta`, `resynth_and_check`)
  in isolation on a small hand-written test module before wiring the full
  agentic loop — this mirrors the project's own Stage 0→9 incremental order.
- When writing the Claude API integration, follow Anthropic's documented
  tool-use pattern (structured `tool_use` blocks, loop keyed on `stop_reason`)
  rather than a custom ad-hoc protocol.
