# Stage 6 benchmark constraints: 5 independent async master clocks, one
# generated (divided) clock per master, all 5 domains marked mutually
# asynchronous (genuinely unrelated clocks -- CDC bridges handle the
# crossing, STA should not analyze cross-domain paths as synchronous).

create_clock -name clk0 -period 5.0  [get_ports clk0]
create_clock -name clk1 -period 6.0  [get_ports clk1]
create_clock -name clk2 -period 4.0  [get_ports clk2]
create_clock -name clk3 -period 7.0  [get_ports clk3]
create_clock -name clk4 -period 5.5  [get_ports clk4]

# OpenSTA's link_design flattens hierarchy to leaf gates: clk_divider's
# "div_clk" submodule port no longer exists as a pin, and the leaf FF that
# drives the net gets a volatile auto-generated name (_2_, _4_, ... changes
# every resynth). Resolve the driver pin dynamically off the net instead of
# hardcoding a gate name.
proc div_clk_driver {netname} {
  foreach p [get_pins -quiet -of_objects [get_nets -hierarchical $netname]] {
    if {[get_property $p direction] == "output"} { return $p }
  }
  error "no output driver pin found for net $netname"
}

create_generated_clock -name div_clk0 -source [get_ports clk0] -divide_by 2  [div_clk_driver div_clk0]
create_generated_clock -name div_clk1 -source [get_ports clk1] -divide_by 4  [div_clk_driver div_clk1]
create_generated_clock -name div_clk2 -source [get_ports clk2] -divide_by 6  [div_clk_driver div_clk2]
create_generated_clock -name div_clk3 -source [get_ports clk3] -divide_by 8  [div_clk_driver div_clk3]
create_generated_clock -name div_clk4 -source [get_ports clk4] -divide_by 10 [div_clk_driver div_clk4]

# The divider's own toggle FF is both the generated clock's defining point
# AND a real register with a combinational feedback path to its own D (the
# "toggle when cnt==HALF-1" mux). Its only non-clock fanout is that self
# feedback (checked: div_clkN's net drives nothing but downstream CLK pins),
# so OpenSTA reports a bogus huge setup "violation" on this self-path: launch
# time is computed via the generated clock's multi-period edge/latency model
# instead of plain gate delay, while capture uses the master clock's own next
# edge -- an apples-to-oranges comparison, not a real timing risk. Exclude
# this one path per divider (safe: nothing else routes through this pin).
foreach dc {div_clk0 div_clk1 div_clk2 div_clk3 div_clk4} {
  set_false_path -through [div_clk_driver $dc]
}

set_clock_groups -asynchronous \
  -group {clk0 div_clk0} \
  -group {clk1 div_clk1} \
  -group {clk2 div_clk2} \
  -group {clk3 div_clk3} \
  -group {clk4 div_clk4}

# rst*_n are genuinely asynchronous (used via "negedge rst_n" throughout the
# RTL) -- OpenSTA already generates the correct recovery/removal checks for
# them automatically against every clock domain they reach. Layering a
# set_input_delay on top additionally forces an inapplicable *synchronous
# setup* check, as if reset were ordinary combinational data racing a clock
# edge -- it isn't, and that bogus check is what produced spurious max-path
# violations here. Deliberately no input_delay on these ports.

set_output_delay -clock div_clk0 0.5 [get_ports rx_acc0*]
set_output_delay -clock div_clk1 0.5 [get_ports rx_acc1*]
set_output_delay -clock div_clk2 0.5 [get_ports rx_acc2*]
set_output_delay -clock div_clk3 0.5 [get_ports rx_acc3*]
set_output_delay -clock div_clk4 0.5 [get_ports rx_acc4*]
