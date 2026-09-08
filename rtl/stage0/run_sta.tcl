read_liberty /data/sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /data/rtl/stage0/traffic_light_synth.v
link_design traffic_light
read_sdc /data/rtl/stage0/traffic_light.sdc

report_checks -path_delay max
report_checks -path_delay min
report_wns
report_tns
