# Design-local global-route setup -- soc_top, sky130hd.
#
# Same as platforms/sky130hd/fastroute.tcl except for the per-layer capacity
# derate. The platform applies a flat 20% derate to every routing layer:
#
#   set_global_routing_layer_adjustment met1-met5 0.2
#
# That derate exists to reserve room for what global routing cannot see yet --
# detailed-routing detours, via pillars, and the power grid. On this design it
# is too pessimistic on the two layers that carry no power grid at all. From
# pdn.tcl, the straps sit on met1 (followpins), met4 and met5; met2 and met3
# carry nothing but signal, yet still lose a fifth of their capacity.
#
# That matters because of how run 4 failed. Of its 12,627 congested tiles,
# 8,894 -- 70% -- are over capacity by only 1 or 2 tracks, and just 2,153 are
# over by 5 or more. A 15% capacity return on met2/met3 is aimed squarely at
# that first group. met2 is also the layer that has dominated every congestion
# report so far (119,223 of 167,419 on run 3).
#
# met1, met4 and met5 keep the platform's 0.2: the power grid really is there,
# and met1 additionally carries the followpin rails.
set_global_routing_layer_adjustment met1 0.20
set_global_routing_layer_adjustment met2 0.05
set_global_routing_layer_adjustment met3 0.05
set_global_routing_layer_adjustment met4 0.20
set_global_routing_layer_adjustment met5 0.20

set_routing_layers -clock $::env(MIN_CLK_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER)
set_routing_layers -signal $::env(MIN_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER)
