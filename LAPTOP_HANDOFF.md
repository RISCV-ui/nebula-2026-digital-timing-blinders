# Handoff — Moving This Project to a Linux Laptop (with sudo)

Read this FIRST if you're Claude Code opening this folder fresh on a new
machine (if Claude Code itself isn't installed yet, see
`CLAUDE_CODE_SETUP.md` first). Read `CLAUDE.md` right after for full project
context (architecture, roadmap, papers). This file covers only: what's in
this zip, what's missing, and exact steps to get the toolchain working on
the new box.

## Why we're moving off the Mac

- OSS CAD Suite + ORFS + OpenRAM's Nix flake all target `x86_64-linux`
  natively. The old working copy was on Apple Silicon (`darwin-arm64`) and
  fought platform-specific build issues throughout (see the Troubleshooting
  chapter in `docs/book/nebula_book.md`).
- We also tried a sudo-less Linux box (`luffy@10.107.2.130`) first. That
  failed: ORFS's native build (`build_openroad.sh --local`) needs `cmake`
  and other system deps only installable via
  `sudo ./tools/OpenROAD/etc/DependencyInstaller.sh` (or ORFS's own
  `sudo ./setup.sh`), and that account had no sudo rights at all
  (`groups` → `luffy eda`, not in `sudo`/`wheel`). A Nix-flake-based
  workaround (`nix develop`, which pulls prebuilt openroad/yosys derivations
  with zero sudo) was in progress but slow/unverified when we switched plans.
  **This laptop has sudo — just run the checklist below normally, no Nix
  workaround needed unless you want one.**

## What's excluded from this zip (don't expect them to be here)

- `orfs/` (9.6GB) — the full OpenROAD-flow-scripts clone + build output.
  Re-clone fresh (step below) — 99% of it is upstream, only ~32MB was ours.
- `oss-cad-suite/` (1.8GB) — prebuilt Yosys/OpenSTA-adjacent/iverilog
  bundle, `darwin-arm64` binaries, useless on Linux anyway. Reinstall fresh
  (`linux-x64` build) — see `NEW_MACHINE_CLAUDE.md`.
- Both are large, platform-specific, and 100% reproducible from a clean
  install — no data loss in leaving them out.

## What's included instead: `orfs_custom/`

This directory holds every file we actually authored inside the old `orfs/`
checkout (everything `git status --short` showed as untracked/modified
against upstream ORFS) — ~32MB, 666 files:

- `flow/llm_loop.py` — Stage 8 agentic loop (run_sta → propose_and_apply_edit
  → resynth_and_check, EQY-gated, `--mock` and real Claude API modes)
- `flow/run_sta.py` / `run_sta.tcl` / `run_sta_test.tcl` — Stage 4 OpenSTA
  wrapper, structured JSON critical-path output
- `flow/run_synth.py` / `run_synth.tcl` — Yosys synthesis wrapper
- `flow/run_eqy.py`, `flow/run_lint.py`, `flow/rtl_hierarchy.py` — Stage 7
  EQY wrapper, lint wrapper, RTL hierarchy helper
- `flow/designs/sky130hd/nebula_soc/`, `flow/designs/src/nebula_soc/` —
  our benchmark design in progress
- `flow/eqy_test/`, `flow/artifacts/`, `flow/book/` — test scaffolding,
  run artifacts, book-adjacent notes generated from inside the ORFS tree
- `tools/eqy_src/` — EQY source/config we added under `tools/`

**This is further along than `docs/00_INDEX.md` admits** — that file still
marks Stage 7/8 "Planned" but `llm_loop.py` etc. already exist and work in
mock mode. Don't trust the doc's status column over the actual code.

## Setup steps on the new laptop

1. Unzip this folder wherever you want the project to live.
2. Run through `NEW_MACHINE_CLAUDE.md` steps 0–4 as written (base apt deps,
   OSS CAD Suite, ORFS clone + `sudo ./setup.sh` + `./build_openroad.sh
   --local`, EQY/sby if not already bundled). This laptop has sudo, so just
   follow it straight — no workarounds needed.
3. Once `orfs/` is freshly cloned and built, **restore our custom work**:
   ```
   cp -R orfs_custom/flow/llm_loop.py orfs_custom/flow/rtl_hierarchy.py \
         orfs_custom/flow/run_eqy.py orfs_custom/flow/run_lint.py \
         orfs_custom/flow/run_sta.py orfs_custom/flow/run_sta.tcl \
         orfs_custom/flow/run_sta_test.tcl orfs_custom/flow/run_synth.py \
         orfs_custom/flow/run_synth.tcl \
         orfs/flow/
   cp -R orfs_custom/flow/designs/sky130hd/nebula_soc orfs/flow/designs/sky130hd/
   cp -R orfs_custom/flow/designs/src/nebula_soc orfs/flow/designs/src/
   cp -R orfs_custom/flow/eqy_test orfs_custom/flow/artifacts orfs_custom/flow/book orfs/flow/
   cp -R orfs_custom/tools/eqy_src orfs/tools/
   ```
4. Continue with Stage 5 onward per `docs/00_INDEX.md` and `CLAUDE.md`'s
   roadmap — verify `llm_loop.py --mock` still runs against the freshly
   built toolchain before doing anything with a real API key.
5. Also needed eventually per `CLAUDE.md`'s tool list: **OpenRAM** (SRAM
   compiler, sky130 support) — not installed anywhere yet, needs Nix first
   (`NEW_MACHINE_CLAUDE.md` steps 5–6). Nix itself is fast/no-sudo either way.

## Session notes worth knowing (not in any doc)

- We also have SSH access to two other boxes from earlier work, unrelated
  to this project but reachable from this network: `luffy@10.107.2.130`
  (key-auth works, no sudo) and `shubhanshu@10.107.2.130` (same host,
  password auth is disabled server-side entirely — `Permission denied
  (publickey)` even with correct password, not a wrong-password issue;
  needs someone with root/console access there to add a pubkey or flip
  `PasswordAuthentication yes` in sshd_config). Not relevant to this
  project's toolchain, just noting so a fresh Claude doesn't re-diagnose
  from scratch if asked to touch that box again.
