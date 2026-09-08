create_clock -name clk -period 1.0 [get_ports clk]
set_input_delay -clock clk 1.0 [get_ports rst_n]
set_output_delay -clock clk 1.0 [get_ports {red yellow green}]
