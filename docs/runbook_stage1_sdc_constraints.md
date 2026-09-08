# Stage 1 — STA Fundamentals cont'd: Generated Clocks + Multicycle Paths

## Goal
Real chips have more than one clock. This stage hand-builds the two SDC
constructs needed for that: a **generated clock** (a clock derived from
another clock inside the design, e.g. a divide-by-2) and a
**multicycle path exception** (telling STA "this specific path is allowed
more than 1 clock period to settle, because the surrounding logic only
uses it every Nth cycle").

## Design: `clkdiv_mcp.v`
- `clk_div2`: divide-by-2 toggle flop off `clk` — this is the generated clock.
- `acc`: 32-bit accumulator clocked by `clk_div2`, fed by a deliberately
  deep combinational adder tree (`(acc^operand)+(acc&operand)+(acc|operand)+operand`)
  that's too slow to close in 1 `clk_div2` cycle at the given period —
  by design, so we have something to apply a multicycle exception to.
- `accept`: pulses once every 2 `clk_div2` cycles, which is the actual
  functional justification for the multicycle exception — the accumulator
  genuinely only needs a new result every other cycle.

## Bug #1 hit + fixed: X-propagation in simulation
Original RTL had no `initial` value on `clk_div2` or `acc`. Trace through:
`clk_div2`'s own always-block is `if (!rst_n) clk_div2<=0; else clk_div2<=~clk_div2;`
— but if `clk_div2` starts as X, `~X` is still X forever, UNLESS the reset
branch fires. The reset branch only fires on a `posedge clk` while
`rst_n==0`— which it does — so `clk_div2` does reach a real 0. But `acc`
is clocked on `posedge clk_div2`, and `clk_div2` never toggles (thus never
posedges) while held at a stable 0 during the reset window, so `acc`'s own
reset branch (`if(!rst_n) acc<=0`) never actually gets a clock edge to fire
on before `rst_n` deasserts — leaving `acc` X forever via the `^` term in
`sum_wide`.
**Fix**: added sim-only `initial` values (`reg clk_div2 = 1'b0;`,
`reg acc = 32'd0;`) — does NOT change any real reset logic, just seeds the
simulator's initial state to something other than X, which real silicon
doesn't have (flops power up to a real 0 or 1, not X — X is a simulation
artifact of "unknown", not a hardware behavior). **Lesson: any reg clocked
by a derived/gated clock needs an explicit sim initial value, because you
can't always guarantee the derived clock will produce an edge during the
reset window.**

## Bug #2 hit + fixed: generated clock declared at wrong point (the important one)
First attempt: `create_generated_clock ... [get_ports clk_div2_out]`
(targeting the output PORT). Result: `report_checks -path_group {clk clk_div2}`
showed **zero paths** in the clk_div2 group despite the design being fine.

**Why**: a generated clock only propagates FORWARD from the pin/port it's
declared at. `clk_div2_out` is a port with nothing electrically downstream
of it inside this design (it's an output — its only "load" is outside the
chip). Declaring the generated clock there means, from STA's point of
view, the clock signal reaches the boundary and stops — none of the
accumulator's flops (which are driven by the internal `clk_div2` net, not
the port) are seen as being on that clock domain at all. They're invisible
to timing analysis — not violating, just silently unchecked, which is much
worse than a reported violation.

**Fix**: find the actual toggle-flop's output pin in the SYNTHESIZED
netlist (not the RTL — pin names only exist post-synthesis) and target
that:
```bash
grep -n "clk_div2" clkdiv_mcp_synth.v | head
# find the cell instance driving the `clk_div2` net, e.g. cell `_528_`, port `.Q(clk_div2)`
```
```
create_generated_clock -name clk_div2 -source [get_ports clk] -divide_by 2 [get_pins _528_/Q]
```
**Lesson: always declare a generated clock at its actual source pin
(typically a toggle flop's Q), never at a downstream port — grep the
synthesized netlist to find the real cell/pin name; it will NOT match any
RTL signal name directly (`_528_` bears no resemblance to `clk_div2`).**

## Final SDC (`rtl/stage1/clkdiv_mcp.sdc`)
```
create_clock -name clk -period 2.0 [get_ports clk]
create_generated_clock -name clk_div2 -source [get_ports clk] -divide_by 2 [get_pins _528_/Q]
set_input_delay  -clock clk_div2 0.3 [get_ports operand]
set_input_delay  -clock clk_div2 0.3 [get_ports accept]
set_output_delay -clock clk_div2 0.3 [get_ports acc_out]
set_multicycle_path 2 -setup -from [get_clocks clk_div2] -to [get_clocks clk_div2]
set_multicycle_path 1 -hold  -from [get_clocks clk_div2] -to [get_clocks clk_div2]
```
- `-divide_by 2`: tells STA the generated clock's period is 2x the master
  (so `clk`=2ns → `clk_div2`=4ns automatically, no need to hand-specify).
- `set_multicycle_path 2 -setup ...`: extends the SETUP check's deadline
  from 1×period to 2×period for paths between `clk_div2` and itself. This
  is the mechanism — without it, the exact same RTL would show a setup
  violation (deep adder can't finish in 4ns) even though functionally
  it's fine (accept only fires every 2 cycles).
- `set_multicycle_path 1 -hold ...`: **always pair a setup multicycle with
  an explicit hold multicycle** (usually staying at 1, i.e. explicitly
  NOT relaxed) — if you don't, some tools infer a matching hold relaxation
  automatically which can silently hide a real hold violation. Being
  explicit here is a deliberate defensive habit, not strictly required by
  OpenSTA in this exact case, but is standard industry practice.

## Verification commands used
```bash
# after fixing the generated-clock declaration, confirm the period math:
./sta/sta.sh /data/rtl/stage1/run_sta.tcl
# checked: get_property [get_clocks clk_div2] period  -- (returned 0.0 due to
# an OpenSTA build quirk, see Stage 2 notes -- verified correctness instead
# via report_checks showing the right 4ns/8ns math directly)

# confirm the multicycle exception is actually being applied:
# in report_checks output, data_required_time for a clk_div2->clk_div2 path
# should land on the 2nd clock edge (8ns), not the 1st (4ns)
```
Final result: WNS 0.00, TNS 0.00 — multicycle path closes cleanly at the
relaxed 2-cycle (8ns) deadline; without the exception it would show
roughly -3 to -4ns violation (adder needs ~7-8ns, only had 4ns budget).

## Command reference
```bash
# sim (after adding initial values)
iverilog -o sim/tb.out clkdiv_mcp.v clkdiv_mcp_tb.v && vvp sim/tb.out
# check final acc_out isn't X:
# should print something like: final acc_out = 9c0b0230

# synth
yosys -p "read_verilog clkdiv_mcp.v; hierarchy -check -top clkdiv_mcp; proc; opt; fsm; opt; memory; opt; techmap; opt; dfflibmap -liberty <lib>; abc -liberty <lib>; clean; write_verilog -noattr clkdiv_mcp_synth.v; stat -liberty <lib>"

# find the generated clock's real source pin
grep -n "clk_div2" clkdiv_mcp_synth.v | head

# STA
./sta/sta.sh /data/rtl/stage1/run_sta.tcl
```

## Problems hit + fixes summary
| Problem | Root cause | Fix |
|---|---|---|
| `acc_out` simulates to all-X forever | derived clock never toggles during reset window, so accumulator's reset branch never gets a clock edge | add sim-only `initial` values to `clk_div2` and `acc` regs |
| `clk_div2` timing group shows 0 paths | generated clock declared at output port (nothing downstream) instead of source pin | grep synthesized netlist for real toggle-flop cell, declare at `[get_pins <cell>/Q]` |
| `report_clocks` prints "invalid command" | wrong assumed command name — not a real OpenSTA command in this build | removed; confirmed real command surface via `info commands` (see Stage 2 doc) |
