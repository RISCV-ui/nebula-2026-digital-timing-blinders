# nebula_bench — reduced RTL benchmark

Same design as `Design-and-Implementation-of-a-Multi-Clock-Domain-RISC-V-SoC-Subsystems/`,
cut down so the whole flow — lint, synthesis, STA, equivalence, floorplan,
placement, CTS, routing — finishes in minutes. The point of the entry is the
number of GenAI iterations we can run and show, and an iteration that takes
three and a half hours and then fails is worth nothing.

## What changed and why

**The two OpenRAM hard macros are gone.** `id_memory_256x64_wrap` and
`tag_memory_92x64_wrap` keep their exact port list and handshake but are now
behavioural, so `l1_d_cache_8kb` and `l1_i_cache_8kb` did not have to be
touched. The macros were `CLASS BLOCK`, 2228.76 × 226.435 µm, with met1–met4
obstruction over their entire area. Ten of them left met2 — the vertical layer
— carrying 71% of all routing congestion (119,223 of 167,419) with 85% of the
hot tiles at `capacity:0`, and every run ended in `GRT-0116`. Rotating them
R90 helped (hot tiles 20,000 → 12,627, global route 3h21m → 1h04m) but never
closed. The problem statement asks for timing analysis, PPA comparison and
formal equivalence; it has no routing, GDS, DRC, LVS or tapeout deliverable.
The macros served no deliverable and caused the only hard failure.

**Caches shrank in sets, not in shape.** Still 4-way, still 256-bit lines,
still the same FSM, LRU and AXI refill path — 8 sets instead of 64. `dmem` and
`i_rom_32x256` went from 256 to 64 words. Nothing the equivalence check
reasons about changed structurally, so the module-by-module EQY results carry
over.

**Result: 65,998 cells, 934,364 µm² of standard cells**, against 82,458 cells
plus ten macros before, and the ~50K figure in the benchmark spec.

## What did not change

Everything the spec actually mandates:

- five independent asynchronous master clock domains (`clk1`–`clk5`)
- at least one generated clock per master (gate + divider on every domain)
- clock domain crossings between all five
- clock dividers at several ratios
- hierarchy preserved for every module, no FSM re-encoding — so the
  post-synthesis netlist stays checkable module by module against the RTL

`multiplier_pipelined` and `fp4_dot_unit` were deliberately kept at full size.
They are the timing-critical arithmetic, which is exactly what the GenAI
optimization pass — pipelining, retiming, logic restructuring — has to work on.

## Layout

    rtl/           55 Verilog files
    constraints/   nebula.sdc
    scripts/       flow helpers

ORFS design directory: `orfs/flow/designs/sky130hd/nebula_bench/`

    cd orfs/flow && source ../env.sh
    make DESIGN_CONFIG=./designs/sky130hd/nebula_bench/config.mk
