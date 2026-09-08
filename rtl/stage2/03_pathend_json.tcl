# Stage 2/4 drill — build ranked-critical-path JSON directly from OpenSTA's
# Tcl object API instead of regex-scraping report_checks text output.
#
# find_timing_paths returns a list of PathEnd objects. Each one supports
# Tcl method-call syntax ($obj method args) once you know its method set
# (found by deliberately calling an invalid method -- OpenSTA prints the
# valid list in the error). Key methods used here:
#   $path_end pin                 -> endpoint pin
#   $path_end slack                -> slack, in SECONDS (not ns -- multiply
#                                      by 1e9)
#   $path_end data_arrival_time    -> arrival time, seconds
#   $path_end data_required_time   -> required time, seconds
#   $path_end target_clk           -> the Clock object this check is against
#   $path_end min_max              -> "min" or "max" (hold vs setup)
#   $path_end path                 -> the full Path object
#   $path.start_path.pin           -> startpoint pin (the clean way; do NOT
#                                      try to parse it out of `pins`, which
#                                      returns the WHOLE trace including the
#                                      clock network, in endpoint-to-source
#                                      order -- confirmed by probing, easy
#                                      to misread as forward chronological)
#
# Run from repo root: ./sta/sta.sh /data/rtl/stage2/03_pathend_json.tcl

read_liberty /data/sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /data/rtl/stage1/clkdiv_mcp_synth.v
link_design clkdiv_mcp
read_sdc /data/rtl/stage1/clkdiv_mcp.sdc

set paths [find_timing_paths -path_delay min_max -sort_by_slack -group_path_count 30]

puts "===JSON_START==="
puts -nonewline "\["
set first 1
foreach p $paths {
    set pth [$p path]
    set sp [$pth start_path]
    set sp_name [get_full_name [$sp pin]]
    set ep_name [get_full_name [$p pin]]
    set slack_ns [expr {[$p slack] * 1e9}]
    set arr_ns   [expr {[$p data_arrival_time] * 1e9}]
    set req_ns   [expr {[$p data_required_time] * 1e9}]
    set clk_name [get_name [$p target_clk]]
    set path_type [$p min_max]
    set status [expr {$slack_ns >= 0 ? "MET" : "VIOLATED"}]

    if {!$first} { puts -nonewline "," }
    set first 0
    puts -nonewline "\n  {\"startpoint\": \"$sp_name\", \"endpoint\": \"$ep_name\", \"path_group\": \"$clk_name\", \"path_type\": \"$path_type\", \"slack_ns\": [format %.4f $slack_ns], \"arrival_ns\": [format %.4f $arr_ns], \"required_ns\": [format %.4f $req_ns], \"status\": \"$status\"}"
}
puts "\n\]"
puts "===JSON_END==="
exit
