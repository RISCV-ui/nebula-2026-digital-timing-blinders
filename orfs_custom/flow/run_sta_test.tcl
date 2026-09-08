read_liberty platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db results/sky130hd/gcd/base/6_final.odb
read_sdc results/sky130hd/gcd/base/6_final.sdc
report_checks -path_delay max -group_count 5 -fields {slew cap input} -digits 4
report_checks -path_delay min -group_count 5 -fields {slew cap input} -digits 4
exit
