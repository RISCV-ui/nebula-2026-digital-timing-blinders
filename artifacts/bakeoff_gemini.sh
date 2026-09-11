#!/bin/bash
# Gemini arms of the bake-off. These run tonight because the Gemini key is the
# only one on this machine; the twenty open-weight arms need an OpenRouter key
# and the Claude arm needs an Anthropic key, both of which arrive later.
#
# Config is copied from run_dryrun5.sh so this arm is comparable to the runs
# already in the report: same targets file, same clock, same target budget,
# same G1 timeout and G1c depth. The only variable is the model.
set -e
cd /Users/shubhanshu/Desktop/Nebula/digital
set -a; . ~/.config/nebula/env; set +a
exec python3 bench/scripts/bakeoff.py \
  --targets artifacts/paths/baseline.json \
  --clock clk_s5 --max-targets 3 --retries 2 \
  --out artifacts/bakeoff --fresh \
  --loop-arg=--g1-timeout --loop-arg=2400 \
  --loop-arg=--g1c-depth --loop-arg=16 \
  --arms gemini:gemini-flash gemini:gemini-pro
