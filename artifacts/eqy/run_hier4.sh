#!/bin/bash
# Fourth hierarchical RTL-vs-netlist sweep. Two changes from hier3, both fixes:
#
#  1. eqy_hier.py now writes into cutpoints.v only the proved *children* of the
#     module being checked. The accumulated file was leaving gold carrying
#     blackboxes for modules it does not instantiate, and EQY stopped at
#     "Unmatched module exists in gold that does not exist in gate" before it
#     ran a single solver call -- on every module.
#
#  2. The gate netlist is artifacts/synth/soc_top_named.v, synthesised with
#     hierarchy and net names kept, instead of the ORFS 1_2_yosys.v. ORFS
#     flattens and lets ABC rename, so EQY finds no internal match points and
#     has to prove each module as one partition with all state unmatched.
#     mem_axi_slave: UNPROVEN against ORFS at depth 5 and at depth 20,
#     PROVED_EQUIVALENT in 9.0s against this netlist.
cd /Users/shubhanshu/Desktop/Nebula/digital
exec python3 scripts/eqy_hier.py \
  --rtl bench/rtl \
  --netlist artifacts/synth/soc_top_named.v \
  --liberty sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib \
  --macro-stub macros/macro_blackbox_stubs.v \
  --depth 5 --timeout 600 \
  --workdir artifacts/eqy/hier_work4 \
  --out artifacts/eqy/soc_top_hier4.json
