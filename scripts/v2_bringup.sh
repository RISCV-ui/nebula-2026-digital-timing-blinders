#!/usr/bin/env bash
# v2 bring-up, chained behind whatever PnR is holding the cores.
#
# Everything here needs CPU that the running detail router already owns, and
# verilator's exec fails outright under load average 50+, so the chain waits
# for OpenROAD to go away before it starts rather than competing with it.
#
#   1. verilator lint of the whole v2 tree   -> artifacts/lint_v2.log
#   2. synthesis only (1_synth.odb)          -> v2 netlist
#   3. slicer on the pre-resizer netlist     -> artifacts/paths/v2_targets.json
#
# Step 3 reads 1_synth.odb, not 5_1_grt.odb: the resizer closes the paths it
# can reach before the loop ever sees them, which is what reduced v1 to a
# single RTL target.
set -uo pipefail
ROOT=/Users/shubhanshu/Desktop/Nebula/digital
cd "$ROOT"

while pgrep -f "OpenROAD/bin/openroad" >/dev/null; do sleep 60; done

source oss-cad-suite/environment

# lint.py, not raw verilator: the gate this project has always used is "no
# warning that bench/rtl does not already have", and bench/rtl carries nine
# of its own (cache index widths, an unused dmem address bit). Raw verilator
# exits non-zero on any warning at all and would fail v2 for warnings v1
# shipped with.
echo "=== [1/3] verilator lint (v2 vs v1 baseline) ==="
python3 bench/scripts/lint.py --golden bench/rtl --candidate bench/rtl_v2 \
  --out artifacts/lint_v2 2>&1 | tee artifacts/lint_v2.log
lint_rc=${PIPESTATUS[0]}
echo "lint rc=$lint_rc"
[ "$lint_rc" -eq 0 ] || { echo "LINT FAILED -- stopping before synthesis"; exit 1; }

echo "=== [2/3] synthesis ==="
W="$ROOT/artifacts/v2_synth"
mkdir -p "$W"
make -C "$ROOT/orfs/flow" \
  "$W/results/sky130hd/nebula_bench_v2/base/1_synth.odb" \
  DESIGN_CONFIG="$ROOT/orfs/flow/designs/sky130hd/nebula_bench_v2/config.mk" \
  WORK_HOME="$W" || { echo "SYNTH FAILED"; exit 1; }

echo "=== [3/3] slicer ==="
source "$ROOT/orfs/env.sh"
python3 bench/scripts/slicer.py \
  --odb "$W/results/sky130hd/nebula_bench_v2/base/1_synth.odb" \
  --sdc "$W/results/sky130hd/nebula_bench_v2/base/1_synth.sdc" \
  --paths 200 \
  --out artifacts/paths/v2_targets.json

echo "=== v2 bring-up done ==="
