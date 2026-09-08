# Stage 2 — TCL fundamentals, drill 2: OpenSTA's Tcl command set
#
# OpenSTA embeds a real Tcl interpreter but adds its own command set on top
# (get_pins, get_clocks, report_checks, ...). Two gotchas hit in Stage 1,
# checked here against this actual OpenSTA build (2.6.2) via `info commands`
# rather than assumed from other tools' conventions:
#
#   1. `report_clocks` is not a real command here -> "invalid command name".
#
#   2. `foreach_in_collection` / `sizeof_collection` (common in other
#      SDC-adjacent tools) do NOT exist in this build either. Verified via
#      `info commands *coll*` / `*each*` -> neither is registered. What
#      get_clocks/get_pins return here prints as a plain space-separated
#      list of SWIG object handles, and plain Tcl `foreach` + `llength`
#      work on it directly. Lesson: don't assume a helper command exists
#      across tools just because it's common elsewhere -- check with
#      `info commands` first, like the checks below do.
#
# Run from repo root: ./sta/sta.sh /data/rtl/stage2/02_opensta_tcl.tcl

read_liberty /data/sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /data/rtl/stage1/clkdiv_mcp_synth.v
link_design clkdiv_mcp
read_sdc /data/rtl/stage1/clkdiv_mcp.sdc

# ---- check a command exists before trusting it ----
if {[llength [info commands report_clocks]] == 0} {
    puts "report_clocks is NOT a real OpenSTA command (confirmed, don't use it)"
}

# ---- collections: get_clocks returns something foreach/llength can use ----
set clks [get_clocks *]
puts "collection: $clks"
puts "count: [llength $clks]"

foreach clk $clks {
    # NOTE: 'period' property reads back 0.000000 for the generated clock
    # (clk_div2) in this OpenSTA build, even though report_checks clearly
    # uses the right 4ns period internally (see stage1 report). Works fine
    # for the plain clk. Property name for derived clocks likely differs --
    # not chased down further, flagged here as a known quirk.
    puts "  clock name: [get_name $clk]  period: [get_property $clk period]"
}

# ---- same pattern for pins on a specific cell ----
set pins [get_pins _528_/*]
puts "pins on cell _528_:"
foreach p $pins {
    puts "  [get_full_name $p]"
}

exit
