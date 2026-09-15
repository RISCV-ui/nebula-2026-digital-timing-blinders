#!/usr/bin/env bash
# Deliverable 6 for the v2 track: formal equivalence evidence for a routed
# variant, RTL against its own synthesised netlist.
#
# This is a different claim from the G1 gate inside the loop, and the report
# needs both:
#
#   G1 (loop)  optimised RTL == frozen RTL      -- the edit preserved function
#   this       netlist == optimised RTL          -- synthesis preserved the edit
#
# Neither implies the other, and only the pair covers frozen RTL -> GDS.
#
# The netlist is the variant's own 1_2_yosys.v, not orfs/flow/results as in the
# v1 run: each variant is routed into its own WORK_HOME, so reading the shared
# flow directory would check whichever variant happened to run last against
# this variant's RTL.
#
#   usage: scripts/eqy_v2.sh <variant> [ppa_out_root]
set -euo pipefail

VARIANT="${1:?usage: eqy_v2.sh <variant> [ppa_out_root]}"
ROOT=/Users/shubhanshu/Desktop/Nebula/digital
PPA_OUT="${2:?usage: eqy_v2.sh <variant> <ppa_out_root>}"
DESIGN=nebula_bench_v2

RTL="$ROOT/output/rtl_variants_v2/$VARIANT/rtl"
NETLIST="$PPA_OUT/pnr_$VARIANT/results/sky130hd/$DESIGN/$VARIANT/1_2_yosys.v"

[ -d "$RTL" ]     || { echo "no RTL tree at $RTL" >&2; exit 1; }
[ -f "$NETLIST" ] || { echo "no synth netlist at $NETLIST (did PnR run?)" >&2; exit 1; }

cd "$ROOT"
exec python3 scripts/eqy_netlist.py \
  --rtl "$RTL" \
  --netlist "$NETLIST" \
  --liberty sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib \
  --macro-stub macros/macro_blackbox_stubs.v \
  --depth 5 --timeout 900 \
  --workdir "artifacts/eqy/v2_work_$VARIANT" \
  --out "artifacts/eqy/v2_${VARIANT}.json"
