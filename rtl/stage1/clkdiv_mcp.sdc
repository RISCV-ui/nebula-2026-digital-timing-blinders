# Stage 1 exercise SDC — generated clock + multicycle path

# master clock: 2ns period (500MHz)
create_clock -name clk -period 2.0 [get_ports clk]

# clk_div2 is a real divide-by-2 generated clock off clk. Must be defined at
# the actual toggle-flop's Q pin (post-synthesis cell _528_), NOT the
# clk_div2_out port — a generated clock only propagates forward from where
# it's declared, and the port is a downstream fanout tap with nothing behind
# it, so declaring it there would leave every accumulator flop unclocked
# from the STA tool's point of view.
create_generated_clock -name clk_div2 -source [get_ports clk] -divide_by 2 [get_pins _528_/Q]

# I/O timing budgets on the divided-clock domain
set_input_delay  -clock clk_div2 0.3 [get_ports operand]
set_input_delay  -clock clk_div2 0.3 [get_ports accept]
set_output_delay -clock clk_div2 0.3 [get_ports acc_out]

# the accumulator's combinational adder tree is allowed 2 clk_div2 cycles:
# accept only pulses once every 2 cycles, so the acc->acc path legitimately
# gets 2 clock periods to settle instead of 1.
set_multicycle_path 2 -setup -from [get_clocks clk_div2] -to [get_clocks clk_div2]
set_multicycle_path 1 -hold  -from [get_clocks clk_div2] -to [get_clocks clk_div2]
