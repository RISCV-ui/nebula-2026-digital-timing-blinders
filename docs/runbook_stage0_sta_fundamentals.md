# Stage 0 — Digital Logic / STA Fundamentals Refresher

## Goal
Hand-build one tiny design, hand-write its SDC, run it through synthesis +
STA, find a real timing violation, and fix it by manually rewriting RTL
(no tools/scripts doing the thinking) — to relearn STA vocabulary
(slack, arrival time, required time, setup/hold, WNS/TNS) from first
principles before any automation is layered on.

## Design: `traffic_light.v`
Moore FSM: RED (4 cyc) → GREEN (3 cyc) → YELLOW (1 cyc) → RED …
- `state`/`next_state`: 2-bit FSM state register + combinational next-state logic
- `count`: 3-bit datapath counter, counts cycles spent in current state
- Outputs `red`/`yellow`/`green`: one-hot decode of state

File: `rtl/stage0/traffic_light.v`. Testbench: `rtl/stage0/traffic_light_tb.v`.

## Step-by-step, by hand

### 1. Simulate functionally first (before touching timing)
```
cd rtl/stage0
iverilog -o sim/tb.out traffic_light.v traffic_light_tb.v
vvp sim/tb.out
```
Confirms functional correctness (FSM sequences RED→GREEN→YELLOW correctly)
independent of timing — always do this before synthesis. A design that's
functionally broken will also produce a nonsense STA report and waste your
time chasing "timing bugs" that are actually logic bugs.

### 2. Synthesize to gates (sky130hd)
```
yosys -p "
read_verilog traffic_light.v
hierarchy -check -top traffic_light
proc; opt; fsm; opt; memory; opt
techmap; opt
dfflibmap -liberty <path to sky130_fd_sc_hd__tt_025C_1v80.lib>
abc -liberty <same liberty>
clean
write_verilog -noattr traffic_light_synth.v
stat -liberty <same liberty>
"
```
This is a full Yosys synthesis script: RTL → generic gates (`proc/opt/fsm/
memory`) → tech-mapped flops (`dfflibmap`) → tech-mapped combinational gates
+ optimization (`abc`) → clean dangling wires → write gate-level netlist.
`stat -liberty` prints cell count + area — sanity-check this isn't zero/huge.

### 3. Write the SDC (by hand — this is the part an LLM will eventually help with)
`rtl/stage0/traffic_light.sdc`:
```
create_clock -name clk -period 1.0 [get_ports clk]
set_input_delay -clock clk 1.0 [get_ports rst_n]
set_output_delay -clock clk 1.0 [get_ports {red yellow green}]
```
- `create_clock`: declares the clock, its period, which port it's on.
  Period is in **nanoseconds** by default in OpenSTA.
  1.0ns period = deliberately aggressive/unrealistic for this design's logic
  depth, chosen ON PURPOSE to force a violation to practice on.
- `set_input_delay`/`set_output_delay`: tells STA how much of the clock
  period is "already spent" before/after this design's boundary (e.g. time
  for a signal to arrive from an upstream chip, or to be used downstream) —
  without these, STA assumes inputs arrive at time 0 and outputs have the
  whole period to work with, which is unrealistically generous.

### 4. Run OpenSTA
`rtl/stage0/run_sta.tcl`:
```tcl
read_liberty <sky130hd typical-corner .lib>
read_verilog traffic_light_synth.v
link_design traffic_light
read_sdc traffic_light.sdc
report_checks -path_delay max -fields {slew cap input}
report_checks -path_delay min -fields {slew cap input}
report_wns
report_tns
exit
```
Run via the OpenSTA docker wrapper (`sta/sta.sh`, mounts repo root at `/data`):
```
./sta/sta.sh /data/rtl/stage0/run_sta.tcl
```
`report_checks -path_delay max` = setup checks (the usual "is my clock fast
enough" check). `-path_delay min` = hold checks (data doesn't race ahead of
the clock edge). Always check BOTH — a design can pass setup and fail hold
or vice versa; they are independent failure modes.

## What "reading the STA report" actually means
Key fields per path in `report_checks` output:
- **Startpoint / Endpoint**: where the path begins (a flop Q, or an input
  port) and ends (a flop D, or an output port).
- **data arrival time**: when the signal actually gets to the endpoint,
  accounting for every gate delay along the path.
- **data required time**: the deadline — when it MUST arrive by (derived
  from the clock period + any input/output delay budget you set in the SDC).
- **slack** = required − arrival. **Negative slack = violation.** Positive
  = margin (headroom before it'd break).
- **WNS** (Worst Negative Slack) = the single worst (most negative) slack
  across all paths — the number that answers "how much do I need to speed
  up my *worst* path to close timing."
- **TNS** (Total Negative Slack) = sum of ALL negative slacks — tells you
  how widespread the problem is (one bad path vs. many).

## The violation we found and fixed
First run: worst path was `_39_ → red`, **slack -0.56ns**. Root cause:
the original RTL had `assign red = (state == S_RED)` — i.e. the output was
combinational logic sitting AFTER the state flop. That combinational decode
gate delay was added on top of the flop's clock-to-Q delay, pushing arrival
time past the deadline.

**The fix — retiming** (one of the 4 allowed RTL-fix techniques): move the
decode logic to evaluate off `next_state` and register the *result*
directly (`red_r <= (next_state == S_RED)`), rather than registering
`state` and then decoding combinationally afterward. Functionally
identical output sequence (since `state <= next_state` on the same edge
anyway) — but now `red`/`green`/`yellow` drive straight off a flop's Q pin
with **zero** combinational gates in the path. See the `red_r`/`green_r`/
`yellow_r` block in `traffic_light.v` (lines 52-62) and the comment there.

**Re-run after fix**: WNS improved -0.56ns → -0.33ns. Worst path is now
`rst_n → _48_` (a different, `rst_n`-driven sync-reset-mux path at a flop's
D-input) — a separate, unaddressed issue (11 violations remain, up from 8,
because loosening one constraint can expose others that were previously
masked in `report_checks`'s default single-worst-path-per-endpoint view —
don't assume "violations went up" always means "got worse", check WHICH
paths and WHY). Confirms retiming can fully eliminate a specific critical
path without touching functionality — this remaining `rst_n` issue is a
different class of problem (looks like an input-delay budget issue on
`rst_n`, not a logic-depth issue) and was deliberately left as out-of-scope
for this stage.

## Command reference (copy-paste ready)
```bash
# functional sim
iverilog -o sim/tb.out traffic_light.v traffic_light_tb.v && vvp sim/tb.out

# synthesis (see full script above)
yosys -p "<script above>"

# STA
./sta/sta.sh /data/rtl/stage0/run_sta.tcl
```

## Problems hit + fixes
- None specific to Stage 0 beyond the intentional violation-and-fix
  exercise itself (that IS the exercise).
