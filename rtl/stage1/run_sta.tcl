read_liberty /data/sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /data/rtl/stage1/clkdiv_mcp_synth.v
link_design clkdiv_mcp
read_sdc /data/rtl/stage1/clkdiv_mcp.sdc

report_checks -path_delay max -format full -group_path_count 30 -path_group {clk clk_div2}
report_wns
report_tns
exit
