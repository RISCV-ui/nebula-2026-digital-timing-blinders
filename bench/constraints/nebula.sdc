# ===================================================================
#  nebula.sdc -- timing constraints for soc_top
#  Nebula 2026 digital track, benchmark design
#
#  Five asynchronous master clocks enter the design. Each peripheral
#  domain passes through a clk_gate and a clk_div_mux, so each master
#  carries at least one generated clock. The five masters are mutually
#  asynchronous and every path between them is a CDC.
#
#  Units: ns. Target library: sky130hd.
# ===================================================================

set_units -time ns -capacitance pF

# -------------------------------------------------------------------
# Clock-net driver lookup
#
# This file is nebula.sdc adapted for the ORFS flow. OpenROAD reads the
# netlist with OPENROAD_HIERARCHICAL off, so the clk_gate / clk_div_mux
# instance pins nebula.sdc names (timer_clk_gate/clk_out and friends) do
# not exist by that name after flattening -- read_sdc dies with
# "pin 'timer_clk_gate/clk_out' not found" -> STA-0374.
#
# What does survive is the soc_top net each of those pins drives: clk_s1
# through clk_s8, and the *_gate nets feeding the dividers. Those are
# top-level names, identical before and after flattening, so resolve the
# driver pin off the net. The driver itself is a leaf gate with a
# generated name (_1234_) that changes on every resynth and can never be
# hardcoded.
# -------------------------------------------------------------------
proc clk_net {netname} {
  set n [get_nets -quiet $netname]
  if {[llength $n] == 0} { set n [get_nets -quiet -hierarchical $netname] }
  if {[llength $n] == 0} { error "clk_net: no net named $netname" }
  foreach p [get_pins -quiet -of_objects $n] {
    if {[get_property $p direction] == "output"} { return $p }
  }
  error "clk_net: net $netname has no output driver pin"
}


# -------------------------------------------------------------------
# 1. Master clocks
# -------------------------------------------------------------------
create_clock -name clk1 -period 10.0 [get_ports clk1]   ;# core        100 MHz
create_clock -name clk2 -period 20.0 [get_ports clk2]   ;# gpio         50 MHz
create_clock -name clk3 -period 12.5 [get_ports clk3]   ;# dot product  80 MHz
create_clock -name clk4 -period 25.0 [get_ports clk4]   ;# timer        40 MHz
create_clock -name clk5 -period 40.0 [get_ports clk5]   ;# uart         25 MHz

# -------------------------------------------------------------------
# 2. Gated clocks
#
# clk_gate is an integrated clock gate: the enable is latched on the low
# phase of the clock and ANDed with it, so the enable can only change
# while the clock is already low and no pulse is ever chopped. Gating
# does not change the period, so each
# gate output is a divide_by 1 generated clock of its source. Declaring
# them explicitly is what stops the analyser treating the gate output as
# an unclocked net and silently dropping every path behind it.
# -------------------------------------------------------------------
create_generated_clock -name clk_s1_gate -source [get_ports clk4] \
    -divide_by 1 [clk_net clk_s1_gate]
create_generated_clock -name clk_s2_gate -source [get_ports clk2] \
    -divide_by 1 [clk_net clk_s2_gate]
create_generated_clock -name clk_s5_gate -source [get_ports clk3] \
    -divide_by 1 [clk_net clk_s5_gate]
create_generated_clock -name clk_s4_gate -source [get_ports clk5] \
    -divide_by 1 [clk_net clk_s4_gate]

# DMA and memory gates sit in the core domain and have no divider after
# them, so their outputs are the endpoints of clk1's gated branch.
create_generated_clock -name clk_s3 -source [get_ports clk1] \
    -divide_by 1 [clk_net clk_s3]
create_generated_clock -name clk_s8 -source [get_ports clk1] \
    -divide_by 1 [clk_net clk_s8]

# -------------------------------------------------------------------
# 3. Divided clocks
#
# clk_div_mux hands over between the incoming clock and counter bits 0,
# 1 and 2, giving divide by 1, 2, 4 or 8 under software control. sel is
# written only during configuration, never while the domain is running,
# and the handover is glitch-free in any case: each branch is gated by
# an enable registered on that branch's own falling edge, and a branch
# may only assert once every other branch has released.
#
# Constraining divide_by 1 is the worst case: it is the fastest the mux
# output can ever be, so a design that closes here closes at every other
# setting. The cost is pessimism on the divided settings, which we accept
# rather than run four analyses.
# -------------------------------------------------------------------
create_generated_clock -name clk_s1 -source [clk_net clk_s1_gate] \
    -divide_by 1 [clk_net clk_s1]
create_generated_clock -name clk_s2 -source [clk_net clk_s2_gate] \
    -divide_by 1 [clk_net clk_s2]
create_generated_clock -name clk_s5 -source [clk_net clk_s5_gate] \
    -divide_by 1 [clk_net clk_s5]
create_generated_clock -name clk_s4 -source [clk_net clk_s4_gate] \
    -divide_by 1 [clk_net clk_s4]

# -------------------------------------------------------------------
# 3b. Divider-internal handover clocks
#
# The glitch-free mux registers each branch's enable on that branch's
# own clock, so the counter bits inside clk_div_mux are not just data --
# they clock eight flops per instance. Left undeclared they would be
# unclocked registers: OpenSTA drops every path to them without failing,
# which is precisely the kind of silent hole the rest of this file
# exists to close. They are declared per instance rather than once,
# because each of the four dividers is a separate physical net.
#
# The internal net names survive linking as <instance>/clk_div2 and
# friends; div_net resolves them and errors if a name ever stops
# matching, so an under-constrained run fails at read_sdc instead of
# reporting optimistic timing.
# -------------------------------------------------------------------
proc div_net {inst net} {
  # Two linkers, two naming schemes, and which one is in force depends on how
  # the netlist reached us. Reading the elaborated hierarchy, the full path is
  # not a net name at all and only the leaf name exists -- `-hierarchical`
  # matches that leaf at each level, so the instance has to be recovered from
  # get_full_name. Reading the synthesised netlist the way the flow does, the
  # opposite holds: `$inst/$net` resolves directly and `-hierarchical` on the
  # leaf finds nothing. Try the direct name first, fall back to the leaf scan,
  # and error if neither works rather than leaving the net unconstrained.
  set n [get_nets -quiet "$inst/$net"]
  if {[llength $n] == 0} {
    foreach x [get_nets -quiet -hierarchical $net] {
      if {[get_full_name $x] == "$inst/$net"} { lappend n $x }
    }
  }
  if {[llength $n] == 0} { error "div_net: no net named $inst/$net" }
  if {[llength $n] > 1}  { error "div_net: $inst/$net is ambiguous" }
  foreach p [get_pins -quiet -of_objects $n] {
    if {[get_property $p direction] == "output"} { return $p }
  }
  error "div_net: net $inst/$net has no output driver pin"
}

array set handover {clk1 {} clk2 {} clk3 {} clk4 {} clk5 {}}

foreach {inst src master} {
    timer_clk_div clk_s1_gate clk4
    gpio_clk_div  clk_s2_gate clk2
    dot_clk_div   clk_s5_gate clk3
    uart_clk_div  clk_s4_gate clk5
} {
  foreach {net div} {clk_div2 2 clk_div4 4 clk_div8 8} {
    set name ${inst}_${net}
    create_generated_clock -name $name -source [clk_net $src] \
        -divide_by $div [div_net $inst $net]
    lappend handover($master) $name
  }
}

# -------------------------------------------------------------------
# 4. Clock uncertainty and transition
#
# Pre-layout there is no real clock tree, so skew and jitter are
# budgeted rather than measured. 250 ps setup uncertainty is a normal
# pre-CTS budget at this process and frequency; 100 ps hold uncertainty
# covers skew alone, since jitter does not hurt hold on a single clock.
# Replace both with post-CTS numbers once place and route has run.
# -------------------------------------------------------------------
set_clock_uncertainty -setup 0.250 [all_clocks]
set_clock_uncertainty -hold  0.100 [all_clocks]
set_clock_transition        0.150  [all_clocks]

# -------------------------------------------------------------------
# 5. Asynchronous groups
#
# The five masters have no phase relationship. Without this the analyser
# invents one, compares edges that never line up in reality, and reports
# thousands of impossible violations across every CDC.
#
# This declares the paths unanalysable, not safe. Safety comes from the
# two-flop synchronisers and the async FIFO in the RTL.
# -------------------------------------------------------------------
#
# The divider-internal handover clocks join their own master's group:
# they are derived from it, and a `sel` write reaching them from clk1 is
# a crossing like any other, covered by the same declaration.
set_clock_groups -asynchronous \
    -group [concat {clk1 clk_s3 clk_s8}        $handover(clk1)] \
    -group [concat {clk2 clk_s2_gate clk_s2}   $handover(clk2)] \
    -group [concat {clk3 clk_s5_gate clk_s5}   $handover(clk3)] \
    -group [concat {clk4 clk_s1_gate clk_s1}   $handover(clk4)] \
    -group [concat {clk5 clk_s4_gate clk_s4}   $handover(clk5)]

# -------------------------------------------------------------------
# 6. Reset
#
# rst is asynchronous in origin and synchronously released per domain.
# It fans out to nearly every flip-flop in the design, so leaving it
# timed produces a critical path that is an artefact of the fanout
# rather than of any real logic.
# -------------------------------------------------------------------
set_false_path -from [get_ports rst]

# -------------------------------------------------------------------
# 7. I/O
#
# soc_obs is the only functional output and exists solely to keep the
# logic observable. Nothing outside samples it, so its output delay is
# nominal rather than a real interface budget.
# -------------------------------------------------------------------
set_input_delay  -clock clk1 2.0 [get_ports rst]
set_output_delay -clock clk1 2.0 [get_ports soc_obs*]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 [all_inputs]
set_load 0.05 [all_outputs]

# -------------------------------------------------------------------
# 8. Design rules
# -------------------------------------------------------------------
set_max_fanout    20 [current_design]
set_max_transition 1.5 [current_design]
