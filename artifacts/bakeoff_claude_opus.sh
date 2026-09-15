#!/bin/bash
# Claude Opus arm of the bake-off. Same config as bakeoff_gemini.sh / run_dryrun5.sh
# so the arm is comparable to every run already in the report: same targets
# file, same clock, same target budget, same G1 timeout and G1c depth. The
# only variable is the model.
set -e
cd /Users/shubhanshu/Desktop/Nebula/digital
set -a; . ~/.config/nebula/env; set +a
exec python3 bench/scripts/bakeoff.py \
  --targets artifacts/paths/baseline.json \
  --clock clk_s5 --max-targets 3 --retries 2 \
  --out artifacts/bakeoff --fresh \
  --loop-arg=--g1-timeout --loop-arg=2400 \
  --loop-arg=--g1c-depth --loop-arg=16 \
  --arms anthropic:opus-direct
