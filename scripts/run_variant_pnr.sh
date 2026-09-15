#!/usr/bin/env bash
# One PPA run for one RTL variant from output/rtl_variants/.
#
# The gemini_flash and nemotron_ultra runs were launched by hand; this is the
# same invocation written down so the Claude arms are measured identically and
# the comparison stays apples-to-apples. The only variable between runs is
# NEBULA_RTL.
#
# Target is `do-finish`, not `finish`: `finish` depends on GDS_FINAL_FILE,
# which needs KLayout, and KLayout is not installed here -- that is exactly
# what stopped the gemini_flash run one step after its metrics were already
# written. There is no GDS/DRC/LVS deliverable in the problem statement, so
# do-finish (6_1_fill + 6_report + elapsed) is the whole PPA requirement.
#
# The design defaults to nebula_bench (v1). v2 adds four deep combinational
# blocks and has its own ORFS design directory, so the benchmark is a
# parameter rather than a constant -- the same driver measures both tracks and
# neither run can silently pick up the other's config.
#
# The variant tree root is a parameter for the same reason the design is. v2
# variants are built into output/rtl_variants_v2 by prepare_variants_v2.py,
# and a v1 default here is not merely wrong but silently wrong:
# output/rtl_variants/baseline exists, so a v2 run would route the v1 RTL --
# which has none of the four deep combinational blocks v2 exists to stress --
# under the v2 design config, and report the result as v2 PPA.
#
#   usage: scripts/run_variant_pnr.sh <variant> [out_root] [design] [variants_root]
set -euo pipefail

VARIANT="${1:?usage: run_variant_pnr.sh <variant> [out_root] [design] [variants_root]}"
ROOT=/Users/shubhanshu/Desktop/Nebula/digital
OUT_ROOT="${2:-$ROOT/artifacts/model_ppa_20260913}"
DESIGN="${3:-nebula_bench}"
VARIANTS_ROOT="${4:-$ROOT/output/rtl_variants}"
RTL="$VARIANTS_ROOT/$VARIANT/rtl"
WORK="$OUT_ROOT/pnr_$VARIANT"

[ -d "$RTL" ] || { echo "no RTL tree at $RTL (run the matching prepare_*variants* script)" >&2; exit 1; }
mkdir -p "$WORK"

# shellcheck disable=SC1091
source "$ROOT/orfs/env.sh"

# The target is the 6_report log *file*, not the `do-finish` phony: `do-`
# targets run one step and assume the previous results already exist, so
# do-finish went straight to density fill and died on a missing 5_route.odb.
# Naming the file makes make build the whole synth -> floorplan -> place ->
# cts -> route chain first, and unlike the `finish` target it does not pull in
# GDS_FINAL_FILE, which needs KLayout.
exec make -C "$ROOT/orfs/flow" \
  "$WORK/logs/sky130hd/$DESIGN/$VARIANT/6_report.log" \
  DESIGN_CONFIG="$ROOT/orfs/flow/designs/sky130hd/$DESIGN/config.mk" \
  FLOW_VARIANT="$VARIANT" \
  NEBULA_RTL="$RTL" \
  WORK_HOME="$WORK"
