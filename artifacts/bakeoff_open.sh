#!/bin/bash
# The open-weight arms. Free models only, on purpose: the OpenRouter account
# holds no balance, so a paid model returns 402 rather than a charge, and the
# key carries a $5 ceiling as a second stop. Nothing here can spend money.
#
# Same config as the Gemini arms and as run_dryrun5.sh, so every arm in the
# bake-off answered the same question under the same budget.
set -e
cd /Users/shubhanshu/Desktop/Nebula/digital
set -a; . ~/.config/nebula/env; set +a
exec python3 bench/scripts/bakeoff.py \
  --targets artifacts/paths/baseline.json \
  --clock clk_s5 --max-targets 3 --retries 2 \
  --out artifacts/bakeoff_open --fresh \
  --loop-arg=--g1-timeout --loop-arg=2400 \
  --loop-arg=--g1c-depth --loop-arg=16 \
  --arms openrouter:nemotron openrouter:nemotron-ultra \
         openrouter:nemotron-nano openrouter:gemma-free
