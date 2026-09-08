# Stage 6 Prep — SoC Integration & Clock Domain Crossing (CDC) Concepts

Read this BEFORE writing any Stage 6 benchmark RTL. It explains the concepts
needed to understand (not just copy) the 5-clock-domain, ~50k-cell benchmark
design required by Nebula. No code here yet — code comes when Stage 6 itself
is built, block by block, together.

## Why 5 async masters → minimum 10 clock domains
Nebula's benchmark spec requires:
- 5 independent asynchronous master clocks
- ≥1 generated clock per master (e.g. divide-by-2/4 off that master, like the
  `clk_div2` exercise in Stage 1)

So: 5 masters + 5 generated (minimum 1 each) = **10 distinct clock domains
minimum**. Each domain needs its own `create_clock` (masters) or
`create_generated_clock` (derived clocks) declaration in the SDC — same
mechanics as Stage 0/1, just repeated per domain.

## Why ~50,000 standard cells
Not a per-domain number — it's a TOTAL scale target across the whole design,
meant to resemble a realistic SoC-subsystem rather than a toy module (Stage 0's
`traffic_light` was on the order of 50-100 cells after synthesis). Reached not
by writing one giant module, but by assembling several individually-simple
blocks (FSMs, datapath/ALU logic, memory-like structures, CDC synchronizers,
clock dividers) — each block is conceptually no harder than Stage 0/1, the
scale comes from combining enough of them.

## What an SoC actually is, structurally
Not one monolithic thing — several independently-clocked blocks, each
individually as simple as a Stage 0 FSM or Stage 1 accumulator, wired together
hierarchically (a top-level module instantiating child modules — ordinary
Verilog hierarchy, nothing new). The only genuinely new concept versus
Stage 0/1 is what happens AT THE BOUNDARY where two different clock domains
meet.

```
        clk_A (master 1)              clk_B (master 2)
            |                              |
    +---------------+            +---------------+
    |  Block A (FSM  |            |  Block B (data-|
    |  + control      |            |  path/ALU)     |
    |  logic)         |            |                |
    +--------+--------+            +--------+-------+
             | data_A                       | data_B
             +-----------+       +----------+
                          v       v
                    +-------------------+
                    |  CDC Synchronizer  |  <- the bridge between domains
                    |  (2-flop or FIFO)  |
                    +---------+---------+
                              |
                     clk_B domain continues...
```
This pattern repeats across all 5 master domains + their generated clocks,
with a synchronizer at every domain boundary crossing.

## CDC (Clock Domain Crossing) — the core new concept for Stage 6

**The problem**: when a signal generated in one clock's domain (say `clk_A`
at 200MHz) is read by logic in a different, asynchronous clock's domain
(`clk_B` at 150MHz), the two clocks' edges don't align predictably. Wiring
signal A straight into a `clk_B`-clocked flop risks **metastability**: the
receiving flop samples mid-transition and can output a value that's neither
a clean 0 nor 1 for a brief period, which can then propagate downstream as
corrupted data or, worse, resolve to different logic values in different
downstream flops reading the same signal.

**The standard fix — a synchronizer**: typically 2 (sometimes 3) flops in
series, clocked by the RECEIVING domain (`clk_B`), placed directly on the
crossing signal. This gives any metastable state time to settle before the
value is used by real logic. This is a mechanical, well-known circuit — not
something to reinvent per-signal.

**Multi-bit buses need more care**: chaining a 2-flop synchronizer per bit
independently does NOT work for multi-bit values — different bits can land
in the receiving domain on different cycles, producing a garbage combination
that was never a valid value in either domain. Standard fixes:
- **Gray-coding** the value before crossing (only 1 bit changes per
  increment, so even a misaligned sample differs by at most 1 count) — common
  for crossing counters/pointers.
- **Dual-clock FIFO** (asynchronous FIFO) — the standard block for crossing
  wide data buses, using gray-coded read/write pointers internally.

Stage 6 needs at least one instance of each: a simple 2-flop synchronizer for
a single-bit control/status signal, and either a gray-coded pointer crossing
or a small async FIFO for a multi-bit data crossing.

## Problems that come up at SoC scale, and how each is resolved

| Problem | What it looks like | How it's resolved |
|---|---|---|
| **Timing violation** | `report_checks` shows negative slack on some path | Same 4 techniques as Stage 0: pipelining, logic restructuring, retiming, FSM re-encoding — applied via the `run_sta → propose_and_apply_edit → resynth_and_check` loop (Stage 8), same idea as the Stage 0 retiming fix, just automated |
| **CDC violation** | a signal crosses domains with no synchronizer, or a multi-bit bus crossed without gray-coding/FIFO | caught by a CDC-specific static check (industry tools: Questa CDC, Spyglass CDC; open-source: partial support in some Yosys passes) — fixed by inserting/correcting the synchronizer structure, not a timing fix |
| **Functional regression after a timing fix** | an RTL edit that improves timing accidentally changes behavior | this is exactly what the **EQY formal equivalence gate** (Stage 7) exists to catch — every proposed edit is proven logically identical to the original before being accepted; if EQY fails, the edit is rejected regardless of how much it improved timing |

## Where this fits in the roadmap
This doc is prep reading for **Stage 6** (build the benchmark RTL). Read it
alongside Stage 0 (`runbook_stage0_sta_fundamentals.md`) and Stage 1
(`runbook_stage1_sdc_constraints.md`) — those cover the single-domain
fundamentals (slack, WNS/TNS, generated clocks, multicycle paths) that every
individual block inside this SoC still relies on. CDC is the ADDITIONAL
concept layered on top when multiple such blocks are connected together.

Stage 6 itself (actual RTL, actual SDC, actual synchronizer code, actual
before/after numbers) gets its own runbook doc once built — this doc is
concepts-only, written before any Stage 6 code exists.
