#!/usr/bin/env bash
# The whole v2 run, end to end, unattended.
#
#   arms -> variants -> PPA -> reports
#
# Config is identical to every v1 arm (same retries, same G1 budget, same
# G1c depth) with three deliberate differences, all of them the point of v2:
#
#   --targets v2_targets.json  three RTL targets in three clock domains,
#                              sliced from 1_synth.odb rather than the
#                              post-resizer netlist that hid two of them
#   --rtl bench/rtl_v2         the frozen input with the four deep blocks
#   no --clock                 v1 pinned clk_s5 because that was the only
#                              domain with an RTL-lever path; pinning it here
#                              would throw away two thirds of the point
#
# Arms run in one invocation so a single bakeoff.json covers all four and the
# comparison table is written once, from one run, with nothing to merge.
# g1-timeout is 300 s. The successful proofs on this design take 22 s
# (fp8_adder, SAT), 43 s (fp4_dot_unit, SMTBMC) and 159 s (arbiter, PDR, and
# that one is unbounded); the failures are not slow, they are unbounded-slow,
# sitting on a 32-step combinational divider that no budget closes. 900 s
# bought nothing that 300 s does not, and at nine candidates per arm the
# difference is two hours per arm of pure waiting.
#
# --order closeable spends the call budget on the paths a transform can
# actually reach before the one it cannot. The -147 ns path still runs and is
# still reported; it just runs last.
set -uo pipefail
ROOT=/Users/shubhanshu/Desktop/Nebula/digital
cd "$ROOT"
STAMP=$(date +%Y%m%d_%H%M)
PPA_OUT="$ROOT/artifacts/model_ppa_v2_$STAMP"

# Anything holding the cores makes every step below slower and the PnR steps
# unreliable, so wait rather than compete. The re-proof of the v1 Opus
# candidates is the one likely to still be running when this starts.
while pgrep -f "retry_opus|OpenROAD/bin/openroad" >/dev/null; do sleep 60; done

# shellcheck disable=SC1091
source "$ROOT/orfs/env.sh"
# shellcheck disable=SC1091
source "$ROOT/oss-cad-suite/environment"
set -a; . "$HOME/.config/nebula/env"; set +a

echo "=== [1/4] bake-off: 4 arms over 3 v2 targets ==="
python3 bench/scripts/bakeoff.py \
  --targets artifacts/paths/v2_targets.json \
  --rtl bench/rtl_v2 \
  --max-targets 3 --retries 2 \
  --out artifacts/bakeoff_v2 --fresh \
  --loop-arg=--g1-timeout --loop-arg=300 \
  --loop-arg=--order --loop-arg=closeable \
  --loop-arg=--g1c-depth --loop-arg=16 \
  --arms gemini:gemini-flash openrouter:nemotron-ultra \
         anthropic:sonnet-direct anthropic:opus-direct
echo "bake-off rc=$?"

echo "=== [2/4] build verified RTL variants ==="
python3 scripts/prepare_variants_v2.py || {
  echo "variant build FAILED -- not running PPA on trees nobody can account for"
  exit 1; }

echo "=== [3/4] place and route, one run per variant ==="
# Serial on purpose. Two OpenROAD runs at once on this machine put the load
# average past 50, at which point verilator cannot even exec and the router
# slows down more than the parallelism buys.
for v in $(python3 -c "
import json,sys
d=json.load(open('output/rtl_variants_v2/variants.json'))
# A variant with no accepted edit is the baseline tree byte for byte; routing
# it a second time under another name would cost three hours to reproduce a
# number we already have.
print(' '.join(x['name'] for x in d['variants']
                if x['name'] == 'baseline' or x['accepted']))
"); do
  echo "--- PnR $v ---"
  bash scripts/run_variant_pnr.sh "$v" "$PPA_OUT" nebula_bench_v2 \
    "$ROOT/output/rtl_variants_v2" \
    > "$ROOT/artifacts/pnr_v2_$v.log" 2>&1
  echo "$v rc=$?"
done

echo "=== [4/4] metrics and reports ==="
# ppa_report.py compares two metrics.py dumps, so every routed variant is
# dumped first and then compared against the baseline dump. Comparing each
# variant to the baseline rather than to each other is what makes the numbers
# addable into one table: every row is "this model's delta against the frozen
# input", measured at the same flow stage.
MET="$ROOT/artifacts/metrics_v2_$STAMP"
mkdir -p "$MET"
for v in "$PPA_OUT"/pnr_*; do
  [ -d "$v" ] || continue
  name=$(basename "$v" | sed 's/^pnr_//')
  r="$v/results/sky130hd/nebula_bench_v2/$name"
  [ -f "$r/6_final.odb" ] || r="$v/results/sky130hd/nebula_bench_v2/$name"
  odb=$(ls "$r"/6_*.odb "$r"/5_route.odb 2>/dev/null | tail -1)
  sdc=$(ls "$r"/6_*.sdc "$r"/5_route.sdc 2>/dev/null | tail -1)
  [ -n "$odb" ] || { echo "$name: no routed odb, skipping"; continue; }
  python3 bench/scripts/metrics.py --odb "$odb" --sdc "$sdc" \
    --logs "$v/logs/sky130hd/nebula_bench_v2/$name" \
    --tag "$name" --out "$MET/$name.json" || echo "$name: metrics failed"
done

for f in "$MET"/*.json; do
  name=$(basename "$f" .json)
  [ "$name" = baseline ] && continue
  [ -f "$MET/baseline.json" ] || { echo "no baseline metrics, cannot compare"; break; }
  python3 bench/scripts/ppa_report.py \
    --before "$MET/baseline.json" --after "$f" \
    --out "$ROOT/artifacts/ppa_v2_${STAMP}_$name" 2>&1 | tail -5
done

echo "=== v2 sweep done ==="
echo "  bake-off : artifacts/bakeoff_v2"
echo "  variants : output/rtl_variants_v2"
echo "  PnR      : $PPA_OUT"
echo "  metrics  : $MET"
