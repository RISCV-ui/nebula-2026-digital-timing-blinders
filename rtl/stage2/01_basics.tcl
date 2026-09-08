# Stage 2 — TCL fundamentals, drill 1: vars, strings, lists, control flow, proc
# Run: tclsh 01_basics.tcl

# ---- everything is a string; set has no type ----
set period 2.0
set name   "clk_div2"
puts "clock $name has period $period"

# ---- math needs expr; [ ] runs a command and substitutes its result ----
set half_period [expr {$period / 2.0}]
puts "half period: $half_period"

# ---- lists: space-separated strings under the hood ----
set clocks [list clk clk_div2 clk_div4]
puts "num clocks: [llength $clocks]"
puts "first clock: [lindex $clocks 0]"

foreach c $clocks {
    puts "  clock -> $c"
}

# ---- if/else, string comparison ----
foreach c $clocks {
    if {$c eq "clk"} {
        puts "$c is the master clock"
    } else {
        puts "$c is a derived clock"
    }
}

# ---- proc: this is what SDC helper procs and Yosys TCL scripts use ----
proc period_for_divider {master_period divide_by} {
    return [expr {$master_period * $divide_by}]
}

puts "clk_div2 period: [period_for_divider $period 2]"
puts "clk_div4 period: [period_for_divider $period 4]"

# ---- string ops you'll actually use parsing tool output ----
set line "  0.67    0.67 ^ _528_/Q (sky130_fd_sc_hd__dfxtp_1)"
set trimmed [string trim $line]
puts "trimmed: '$trimmed'"
puts "contains dfxtp: [string match "*dfxtp*" $line]"

# split a "cell/pin" pair like OpenSTA prints
set cellpin "_528_/Q"
set parts [split $cellpin "/"]
puts "cell: [lindex $parts 0], pin: [lindex $parts 1]"
