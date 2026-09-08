# Reads STA_LIBERTY / STA_SDC / STA_GROUP_COUNT from env, plus either:
#   STA_DB       -- post-route .odb (accurate, real parasitics; Stage 5 output)
# or
#   STA_NETLIST + STA_TOP -- synthesized-but-unplaced Verilog netlist (fast,
#   no parasitics yet; what the Stage 8 retry loop uses on every iteration,
#   since running full place & route per LLM edit is too expensive)
# Prints report_checks (max + min) as plain text for run_sta.py to parse into JSON.

if { ![info exists ::env(STA_LIBERTY)] } {
    puts "ERROR: set STA_LIBERTY env var to the liberty file path"
    exit 1
}
if { ![info exists ::env(STA_SDC)] } {
    puts "ERROR: set STA_SDC env var to the .sdc path"
    exit 1
}

set have_db [info exists ::env(STA_DB)]
set have_netlist [info exists ::env(STA_NETLIST)]

if { !$have_db && !$have_netlist } {
    puts "ERROR: set either STA_DB (.odb) or STA_NETLIST+STA_TOP (synthesized netlist)"
    exit 1
}

set group_count 20
if { [info exists ::env(STA_GROUP_COUNT)] } {
    set group_count $::env(STA_GROUP_COUNT)
}

read_liberty $::env(STA_LIBERTY)

if { $have_db } {
    read_db $::env(STA_DB)
} else {
    if { ![info exists ::env(STA_TOP)] } {
        puts "ERROR: STA_NETLIST requires STA_TOP"
        exit 1
    }
    if { ![info exists ::env(STA_TLEF)] || ![info exists ::env(STA_LEF)] } {
        puts "ERROR: STA_NETLIST also requires STA_TLEF + STA_LEF (tech/cell LEF, needed by OpenROAD to build a db even without placement)"
        exit 1
    }
    read_lef $::env(STA_TLEF)
    read_lef $::env(STA_LEF)
    read_verilog $::env(STA_NETLIST)
    link_design $::env(STA_TOP)
}

read_sdc $::env(STA_SDC)

puts "=== BEGIN MAX PATHS ==="
report_checks -path_delay max -group_path_count $group_count -fields {slew cap input} -digits 4
puts "=== END MAX PATHS ==="

puts "=== BEGIN MIN PATHS ==="
report_checks -path_delay min -group_path_count $group_count -fields {slew cap input} -digits 4
puts "=== END MIN PATHS ==="

puts "=== BEGIN WNS TNS ==="
report_wns
report_tns
puts "=== END WNS TNS ==="

exit
