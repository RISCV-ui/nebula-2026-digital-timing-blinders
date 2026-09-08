# Design-local PDN -- soc_top, sky130hd.
#
# This is platforms/sky130hd/pdn.tcl with two design-specific additions.
#
# 1. vccd1 / vssd1 global connections.
#
# The OpenRAM macros name their supplies vccd1 and vssd1. None of the platform
# pin patterns (VDD, VDDPE, VDDCE, VPWR, VPB, VSS, VSSE, VGND, VNB) matches
# either name, so without the two extra add_global_connection lines below the
# macros are simply never tied to the core supplies.
#
# 2. A met4 strap over R90 macros (CORE_macro_grid_2).
#
# The ten macros are placed R90 -- see macro_placement_r90.tcl for why -- and
# the stock grid_2 cannot power them in that orientation:
#
#   [WARNING PDN-0232] The grid "CORE_macro_grid_2 - d_cache_0/i_mem_0/u_macro"
#   (Instance) does not contain any shapes or vias.
#   [ERROR PDN-0233] Failed to generate full power grid.
#
# The macros carry power on met4: vccd1 and vssd1 are 1.74 um wide bars running
# the full 226.435 um height at the macro's left and right edges (RECT 0.0 0.0
# 1.74 226.435 and RECT 2227.02 0.0 2228.76 226.435). Unrotated those bars
# stand vertical, cross the horizontal met5 core straps (pitch 27.2) many times
# over, and grid_2's met4->met5 connect has plenty of crossings to via onto.
# Rotated R90 the bars lie flat -- 1.74 um tall, parallel to met5 -- and a
# 1.74 um band lands on a 27.2 um pitch only about 6% of the time, so most
# macros get no via at all and PDN gives up.
#
# Giving grid_2 its own met4 straps fixes it. met4 runs vertical, so the straps
# cross the now-horizontal macro power bars on the same layer (a direct
# overlap, no via required) and cross the met5 core straps above them, which is
# where the met4->met5 connect drops its vias. Pitch and offset match the core
# grid's met4 straps so the two line up rather than interleave.
#
# CORE_macro_grid_1 is left exactly as the platform has it. Nothing in this
# design is placed R0/R180/MX/MY, so it goes unused here, but keeping it intact
# means this file stays a drop-in replacement for the platform's.
####################################
# global connections
####################################
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDPE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDCE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPWR}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VPB}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vccd1$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSSE$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VGND}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VNB}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^vssd1$}
global_connect
####################################
# voltage domains
####################################
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}
####################################
# standard cell grid
####################################
define_pdn_grid -name {grid} -voltage_domains {CORE} -pins {met5}
add_pdn_stripe -grid {grid} -layer {met1} -width {0.48} -pitch {5.44} -offset {0} -followpins
add_pdn_stripe -grid {grid} -layer {met4} -width {1.600} -pitch {27.140} -offset {13.570}
add_pdn_stripe -grid {grid} -layer {met5} -width {1.600} -pitch {27.200} -offset {13.600}
add_pdn_connect -grid {grid} -layers {met1 met4}
add_pdn_connect -grid {grid} -layers {met4 met5}
####################################
# macro grids
####################################
####################################
# grid for: CORE_macro_grid_1
####################################
define_pdn_grid -name {CORE_macro_grid_1} -voltage_domains {CORE} -macro \
  -orient {R0 R180 MX MY} -halo {2.0 2.0 2.0 2.0} -default -grid_over_boundary
add_pdn_connect -grid {CORE_macro_grid_1} -layers {met4 met5}
####################################
# grid for: CORE_macro_grid_2
####################################
define_pdn_grid -name {CORE_macro_grid_2} -voltage_domains {CORE} -macro \
  -orient {R90 R270 MXR90 MYR90} -halo {2.0 2.0 2.0 2.0} -default -grid_over_boundary
add_pdn_stripe  -grid {CORE_macro_grid_2} -layer {met4} -width {1.600} \
  -pitch {27.140} -offset {13.570}
add_pdn_connect -grid {CORE_macro_grid_2} -layers {met4 met5}
