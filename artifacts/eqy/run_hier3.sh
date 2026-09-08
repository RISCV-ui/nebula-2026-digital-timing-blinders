#!/bin/bash
# Third hierarchical RTL-vs-netlist run. Differs from hier2 in two ways, both
# fixes rather than parameter changes: eqy_netlist.py now puts
# oss-cad-suite/bin on PATH so the sby strategy's SMT engine actually exists
# (hier2 ran the whole sweep with no solver and never said so), and an
# unproven partition is no longer reported as NOT_EQUIVALENT unless EQY
# actually said "partitions not equivalent".
cd /Users/shubhanshu/Desktop/Nebula/digital
exec python3 scripts/eqy_hier.py \
  --rtl bench/rtl \
  --netlist orfs/flow/results/sky130hd/soc_top/base/1_2_yosys.v \
  --liberty sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib \
  --macro-stub macros/macro_blackbox_stubs.v \
  --depth 5 --timeout 900 \
  --workdir artifacts/eqy/hier_work3 \
  --out artifacts/eqy/soc_top_hier3.json
