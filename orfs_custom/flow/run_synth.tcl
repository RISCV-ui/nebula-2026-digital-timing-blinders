# Stage 3: standalone Yosys synth wrapper (fast re-synth for the LLM retry
# loop -- NOT the full ORFS flow, which is the expensive final PPA run in
# Stage 5). Reads SYNTH_VERILOG / SYNTH_TOP / SYNTH_LIBERTY / SYNTH_OUT_V from
# env. Prints `stat -json` between delimiter markers for run_synth.py to parse.
#
# Run in Tcl mode (yosys -c), so every Yosys command must be invoked as
# "yosys <command> <args>" -- plain Tcl control flow (foreach/if) works
# directly since this is a real Tcl interpreter, unlike a .ys native script.

foreach v {SYNTH_VERILOG SYNTH_TOP SYNTH_LIBERTY SYNTH_OUT_V} {
    if { ![info exists ::env($v)] } {
        puts "ERROR: set $v env var"
        exit 1
    }
}

# SYNTH_BLACKBOX_V: colon-separated stub files read with -lib, so the module
# is known by port only and Yosys emits an instance instead of synthesizing
# logic for it. This is how the OpenRAM macros (id_memory_256x64,
# tag_memory_92x64) stay hard macros: their .v is a simulation model, the
# .lib/.lef are what the silicon actually is, and synthesizing the .v would
# produce a pile of flops that does not exist on the die. Read the stubs
# FIRST -- a real module definition read earlier wins over a later -lib one.
if { [info exists ::env(SYNTH_BLACKBOX_V)] } {
    foreach f [split $::env(SYNTH_BLACKBOX_V) ":"] {
        yosys read_verilog -lib -sv $f
    }
}

set verilog_files [split $::env(SYNTH_VERILOG) ":"]
foreach f $verilog_files {
    yosys read_verilog -sv $f
}

yosys hierarchy -top $::env(SYNTH_TOP)

# -nofsm: no FSM detection or state re-encoding. Two reasons. The netlist is
# equivalence-checked against the RTL module by module, and re-encoding
# changes the state bits themselves, so the two sides stop matching. And the
# loop's FSM work is meant to be a deliberate RTL edit we can read and
# justify, not a silent synthesis rewrite.
yosys synth -top $::env(SYNTH_TOP) -nofsm

yosys dfflibmap -liberty $::env(SYNTH_LIBERTY)

# SYNTH_STRATEGY selects a synthesis-only retry tier (no RTL change) tried
# before ever calling the LLM -- cheap re-mapping variants that can close
# timing on their own when the bottleneck is a suboptimal tech-mapping
# choice rather than a genuinely bad RTL structure.
set strategy "default"
if { [info exists ::env(SYNTH_STRATEGY)] } {
    set strategy $::env(SYNTH_STRATEGY)
}

if { $strategy eq "retime" } {
    # ABC's own sequential retiming during tech-mapping: moves existing
    # registers earlier/later without touching RTL. Free version of the
    # "retiming" technique, done at the tool level.
    yosys abc -liberty $::env(SYNTH_LIBERTY) -dff
} elseif { $strategy eq "timing_driven" } {
    # Re-map with an explicit delay target (ps) instead of ABC's default
    # area-leaning heuristic -- forces ABC to prioritize the critical path.
    if { ![info exists ::env(SYNTH_ABC_PERIOD_PS)] } {
        puts "ERROR: SYNTH_STRATEGY=timing_driven requires SYNTH_ABC_PERIOD_PS"
        exit 1
    }
    yosys abc -liberty $::env(SYNTH_LIBERTY) -D $::env(SYNTH_ABC_PERIOD_PS)
} else {
    yosys abc -liberty $::env(SYNTH_LIBERTY)
}

yosys clean -purge
yosys setundef -zero

# Write the netlist BEFORE flattening -- hierarchy must survive (instance
# names like "dpath.b_reg...") so OpenSTA's report_checks path names can be
# mapped back to the RTL submodule that actually contains them (Stage 8's
# edit-localization step needs this; a flattened netlist collapses every
# name to opaque "_243_"-style IDs and that mapping becomes impossible).
yosys write_verilog -noattr $::env(SYNTH_OUT_V)

# Flatten a throwaway copy only for accurate whole-design cell/area totals
# (per-module num_cells double-counts submodule instances otherwise).
yosys flatten
yosys tee -o [format "%s.stat.json" $::env(SYNTH_OUT_V)] stat -json -liberty $::env(SYNTH_LIBERTY)

exit
