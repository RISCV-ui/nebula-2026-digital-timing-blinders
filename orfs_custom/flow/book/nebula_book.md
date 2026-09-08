# Closing the Loop

### A Practitioner's Guide to LLM-Driven RTL Timing Closure

**Built for the Astera Labs Nebula 2026 Digital Track — Team Timing Blinders**
*Shubhanshu Shivhare · Nagarjun BV*

---

> This book documents a real pipeline, built and verified end-to-end on a real
> 5-clock-domain SoC benchmark (`nebula_soc`, sky130hd, ~57K standard cells).
> Every command, every script, every bug in this book is one we actually hit,
> diagnosed, and fixed — not textbook theory. Where a concept is explained in
> the abstract, it is immediately grounded in the exact file and exact line
> where we applied it. If you are bringing up this flow on a new SoC, this
> book is written to be followed top to bottom.

---

## Table of Contents

**Part 0 — Orientation**
- Preface: Why This Book Exists
- How to Read This Book

**Part 0.5 — Before Chapter 1**
0. Environment Setup From Zero

**Part I — Foundations**
1. Digital Logic & RTL Refresher (just enough)
2. STA Fundamentals
3. SDC — The Language of Constraints
4. TCL Fundamentals for EDA Scripting

**Part II — The Toolchain, Tool by Tool**
5. Yosys — RTL Synthesis
6. OpenSTA — Static Timing Analysis
7. OpenROAD-flow-scripts — Full RTL-to-GDS and PPA
8. Verilator Lint — Catching What Synthesis and STA Cannot
9. EQY/SymbiYosys — Formal Equivalence Checking

**Part III — The Benchmark Design**
10. Building `nebula_soc`: A 5-Clock-Domain Benchmark
11. Writing `constraint.sdc`: A Real Debugging Walkthrough

**Part IV — The Agentic Loop**
12. Architecture of the Timing-Closure Loop
13. The Synthesis-Only Retry Tier
14. The LLM Call: Constrained RTL Editing
15. Acceptance Criteria: WNS, Violations, and the EQY Gate
16. Edit Localization: Finding the Right Module to Edit
17. Research Foundations: What the Literature Actually Contributes

**Part V — Running This on a New SoC**
18. Design Decisions and Alternatives Considered
19. End-to-End Walkthrough: Bringing Up a New Design
20. Troubleshooting Compendium
21. Command Reference

**Appendix**
- A. Glossary
- B. File Manifest
- C. Reference Papers and Why Each One Matters
- D. Full Annotated Source Listings
- E. Sample Reports — What Each Tool's Output Actually Looks Like

---
---

# Part 0 — Orientation

## Preface: Why This Book Exists

Timing closure is the part of chip design where a netlist that is
functionally correct gets forced to also run at its target clock frequency.
It is iterative, manual, and — critically — it is the part of the flow where
an engineer's judgment (which technique fixes *this* path, without breaking
three others) matters more than raw compute. That makes it a good target for
an LLM in a loop: not because the LLM understands physics, but because the
*loop around* the LLM can catch every mistake it makes, cheaply, before that
mistake ever reaches silicon.

That loop is the actual deliverable of this project. Not "an LLM that writes
Verilog" — anyone can get an LLM to write Verilog. The deliverable is the
scaffolding that makes it safe to let an LLM touch a real design: a
timing-analysis stage that hands the LLM exactly the right amount of context,
a formal-equivalence gate that rejects any edit that isn't provably the same
circuit, and an acceptance criterion that can't be fooled by a local
improvement that causes a global regression.

This book is the record of building that scaffolding, module by module, bug
by bug. Every chapter maps to a real file in the `flow/` directory of this
repository. Every "gotcha" section describes an error message we actually
saw, on this actual design, and the actual fix — not a hypothetical.

## How to Read This Book

If you already know STA and Verilog cold, skip Part I and start at Part II —
each tool chapter is self-contained and references the actual wrapper script
you'll run. If you are bringing up this exact flow on a *new* SoC (different
RTL, same toolchain), go straight to Chapter 19, which is a linear checklist
that points back into earlier chapters only where you need the depth.

Every code listing in this book is either a verbatim excerpt of a real file
in this repository, or a real terminal transcript. Where a listing has been
shortened for space, that is marked explicitly.

---

## Chapter 0 — Environment Setup From Zero

This chapter assumes you know digital logic and can read/write Verilog, and
nothing else — no prior exposure to Yosys, OpenSTA, OpenROAD, Tcl, EQY, or
running a multi-tool EDA flow from the command line. Every command below is
real and was actually run to build this project; run them in this order,
top to bottom, before touching Chapter 1.

### 0.1 What you're installing, and why, in one table

| Tool | What it does in this flow | Why you need it before Chapter 1 |
|---|---|---|
| OSS CAD Suite | bundles Yosys, OpenSTA, Verilator, Icarus | one download gets you three of the five core tools |
| EQY + SymbiYosys (`sby`) | formal equivalence checking | the safety gate; build this before anything touches an LLM |
| OpenROAD-flow-scripts | full RTL-to-GDS PPA flow | only needed from Chapter 7 onward; slowest to build, start it early and let it run in the background while you read Chapters 1–4 |
| Python 3.9+ | orchestration layer | already on macOS/Linux; just needs a venv |
| `anthropic` Python package | the LLM client, Chapter 14 onward | only needed if you go past the mock-mode LLM loop |

### 0.2 Step 1 — OSS CAD Suite (Yosys, OpenSTA, Verilator)

On Apple Silicon macOS (adjust the filename for your platform — Linux x64
uses `-linux-x64`, Intel Mac uses `-darwin-x64`; **getting this filename
wrong is the single most common Chapter 0 mistake** — it will still
"install" and even mostly run, just slower and occasionally with subtly
different floating-point behavior under Rosetta emulation, with no error to
tell you it happened):

```bash
mkdir -p ~/eda && cd ~/eda
curl -L -o oss-cad-suite.tgz \
  https://github.com/YosysHQ/oss-cad-suite-build/releases/latest/download/oss-cad-suite-darwin-arm64.tgz
tar xzf oss-cad-suite.tgz
xattr -dr com.apple.quarantine oss-cad-suite/
source oss-cad-suite/environment
```

The `xattr` line is not optional on macOS — skip it and every single binary
in the suite (there are dozens) will pop a separate "cannot be opened,
unidentified developer" Gatekeeper dialog the first time it runs, one at a
time, which makes the suite functionally unusable until you either click
through all of them or run this one command up front.

Verify it worked before moving on — do not assume, check:
```bash
yosys -V
sta -version
verilator --version
```
Each should print a version string. If any of the three says "command not
found," the `source oss-cad-suite/environment` line either wasn't run, or
was run in a different shell session than the one you're now typing in —
`source` only affects your *current* shell; open a fresh terminal and it's
gone again unless you add that `source` line to your `~/.zshrc`/`~/.bashrc`.

### 0.3 Step 2 — EQY and SymbiYosys

```bash
cd ~/eda
git clone https://github.com/YosysHQ/sby.git
git clone https://github.com/YosysHQ/eqy.git
cd sby && make install PREFIX=~/eda/oss-cad-suite && cd ..
cd eqy && make install PREFIX=~/eda/oss-cad-suite && cd ..
```
Both install *into* the OSS CAD Suite prefix deliberately, so they end up
on the same `PATH` you already sourced in Step 1, and so EQY's internal
shell-out to `yosys` (Appendix D.5) finds the exact same Yosys build you
just verified, rather than some other Yosys that might exist elsewhere on
your machine. Verify:
```bash
eqy --help
```

### 0.4 Step 3 — a PDK (sky130hd)

You need real Liberty (`.lib`) and LEF (`.lef`) files before Chapter 5's
synthesis wrapper can run — synthesis maps generic logic onto *real*
standard cells, and it needs their timing/area library to do that mapping
at all. This project uses the open **SkyWater sky130hd** PDK specifically
because it's free, well-supported by every tool in this list, and is what
OpenROAD-flow-scripts (Step 4) ships pre-integrated — using any other PDK
here means also re-deriving Step 4's PDK wiring yourself, which is real
extra work with no benefit for a first build.

The simplest path is to let OpenROAD-flow-scripts's own build pull it in
(Step 4 does this automatically); if you need the library files before
that finishes, they are also available standalone via
`github.com/RTimothyEdwards/open_pdks` — but for this project's flow,
just proceed to Step 4 and treat the PDK as bundled with it.

### 0.5 Step 4 — OpenROAD-flow-scripts (start this early, it's slow)

```bash
cd ~/eda
git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
cd OpenROAD-flow-scripts
./build_openroad.sh --local
```
`--recursive` matters — this repo pulls in the actual OpenROAD engine and
the PDK data as git submodules; cloning without it leaves those
directories empty and the build fails partway through with errors that
look unrelated to the missing submodules. This build genuinely takes
30–90+ minutes depending on your machine — this is the reason Step 4 is
listed as "start early": kick it off, then go read Chapters 1–4 (pure
conceptual reading, no tool needed) while it compiles in the background.
Do not block on it before starting Chapter 1.

### 0.6 Step 5 — Python environment for the orchestration scripts and (later) the LLM

```bash
cd ~/eda   # or wherever this project's flow/ directory lives
python3 -m venv .venv
.venv/bin/pip install anthropic
```
A dedicated venv, not a system-wide `pip install`, for two independent
reasons that both bite beginners the same way: (1) modern Python
installations refuse a bare `pip install` outside a venv anyway (PEP 668,
"externally managed environment" — you'll see this error if you skip the
venv and try anyway), and (2) even on an older Python that *would* allow
it, mixing this project's dependencies into your system Python risks
breaking unrelated tools that also depend on Python. Every command in this
book that says "run the Python wrapper" means run it with
`.venv/bin/python3`, not a bare `python3` — mixing the two is the single
most common source of a confusing `ModuleNotFoundError: No module named
'anthropic'` despite `pip install` having reported success (Chapter 20,
"environment/tooling friction" section, has the full diagnostic for when
this happens anyway).

### 0.7 Step 6 — sanity-check the whole chain in under a minute

Before writing a single line of this project's own code, prove every tool
in the chain actually runs, on the smallest possible input, so that any
later error you hit is a *design* problem, not a *toolchain* problem:

```bash
echo 'module t(input a, output b); assign b = a; endmodule' > /tmp/t.v
yosys -p "read_verilog /tmp/t.v; synth -top t; stat" /tmp/t.v
```
If this prints a cell-count summary with no errors, Yosys is fully
functional end to end (frontend parse → generic synth → stat report) and
you are ready for Chapter 1.

### 0.8 What "winning this competition" actually requires, scope-wise

You do not need to build every chapter of this book to have a complete,
demoable, judge-scoring entry. The **minimum path to a working, honest
demo** — matching every item on the official Nebula deliverables checklist
(Preface) — is, in strict order:

1. Chapters 0–4: environment + concepts (a few hours of reading, mostly
   passive, do Step 4's build in parallel).
2. Chapter 5 (Yosys) + Chapter 6 (OpenSTA): get a synthesized netlist and a
   real timing report on *any* design — even a tiny one — before touching
   the benchmark RTL. This proves the fast inner loop works.
3. Chapter 10 (or your own smaller benchmark, see the note below) +
   Chapter 11 (SDC): a design with real, closable timing violations. Your
   design does **not** need to hit the full ~50,000-cell / 5-clock-domain
   scale to produce a valid, honest demo of the *method* — a smaller
   design that still has genuine CDC, a generated clock, and a real
   critical path exercises the same pipeline and is far faster to iterate
   on under competition time pressure. Scale up only once the loop
   provably works end to end on something small.
4. Chapter 9 (EQY): build and test the equivalence gate on a trivial
   hand-edited example (e.g. manually pipeline one register in a tiny
   test module, prove EQY accepts it; manually break the logic, prove EQY
   rejects it) **before** wiring up Chapter 14's LLM call — this order is
   the project's own non-negotiable design principle (see the root
   CLAUDE.md), and it is also simply the fastest way to build confidence
   that your gate is real and not a rubber stamp.
5. Chapters 12–16: the agentic loop, run first in `--mock` mode (Chapter
   14's mock path) to prove the *plumbing* — localization, retry tiers,
   accept/reject logic — end to end with zero API cost and zero
   dependency on network access, before spending a single real API call.
6. Only once mock mode fully closes timing on your chosen benchmark:
   switch on the real LLM call for the actual demo run, and capture the
   before/after slack numbers and the EQY equivalence report for your
   deliverable #6 (formal equivalence verification report) and #5
   (timing/PPA comparison).
7. Chapter 7 (ORFS) for a full PPA number set, run once, near the end,
   once the fast-loop RTL is already good — this is the slowest single
   step in the whole pipeline and should never be in your fast iteration
   loop (Chapter 7 explains exactly why).

Deliverable #7 ("interactive demo showcasing the workflow") is best served
by literally showing the Chapter 12 loop running live against your
benchmark, narrating each stage as it prints — the `llm_loop.py` stderr
trace (Appendix E, Figure E.10) *is* your demo script; you do not need to
build a separate GUI or dashboard to satisfy this checklist item.

---
---

# Part I — Foundations

## Chapter 1 — Digital Logic & RTL Refresher

You do not need a semester of digital design to follow this book, but you do
need five ideas cold, because every later chapter assumes them.

**1. A register is a time machine, not a wire.** A flip-flop (FF) samples its
`D` input at a clock edge and holds that value on `Q` until the next edge.
Between edges, `Q` is *frozen* — this is the only thing that makes "the
signal has time to settle before the next edge" a meaningful sentence. All of
static timing analysis is built on this one fact.

**2. Combinational logic has delay, but no memory.** An AND gate, a mux, an
adder — none of them "wait". They compute a new output as fast as physics
allows, continuously, in response to their inputs changing. The *only* reason
a circuit's speed is bounded at all is that combinational logic sits *between*
two registers, and the receiving register needs the combinational output to
have stabilized before it samples.

**3. A "path" is startpoint → combinational cloud → endpoint.** A startpoint
is a register's `Q` output (or a primary input port). An endpoint is a
register's `D` input (or a primary output port). Everything in between is the
combinational cloud STA has to sum the delay of. This is the unit every STA
tool reports on, and the unit an LLM edit has to reason about.

**4. Clock domains are not automatically compatible.** Two clocks running at
different frequencies, or the same frequency with no fixed phase
relationship, are *asynchronous*: there is no meaningful "setup time" between
them, because there's no fixed edge-to-edge relationship to check. Crossing
between such domains needs dedicated hardware (a synchronizer, or — as in our
benchmark — a full asynchronous FIFO with Gray-coded pointers). Standard STA
setup/hold analysis is meaningless across such a boundary and must be
explicitly told to ignore it (`set_clock_groups -asynchronous`, Chapter 3 and
Chapter 11).

**5. A generated clock is still a clock, but it comes from logic.** `clk_div`
= "take a fast clock, divide it in hardware (a counter that toggles an
output), and treat that toggling output as a new clock for everything
downstream." The tool needs to be told explicitly which pin is a clock and
what its relationship is to its source clock (`create_generated_clock`) — it
cannot infer this from the netlist alone.

If those five ideas are solid, you have enough RTL background for this
entire book. Everything else (Verilog syntax, `always` blocks, blocking vs.
non-blocking assignment) you will pick up faster by reading `nebula_soc.v`
directly in Chapter 10 than from a textbook, because you'll see it in a
context that already matters to you.

### A worked numeric example, because "setup time" is easier to trust once you've added the numbers yourself

Take one real edge of the benchmark: `clk0` at 5.0 ns period (Chapter 11).
Say the launching register's clock-to-Q delay is 0.18 ns, the combinational
logic between it and the next register has a worst-case delay of 4.1 ns, and
the capturing register's setup time is 0.09 ns.

- **Data arrival time** = clock-to-Q + combinational delay = 0.18 + 4.10 =
  4.28 ns after the launch edge.
- **Data required time** = one full period minus the capturing register's
  setup requirement = 5.00 − 0.09 = 4.91 ns after the launch edge (this is
  the latest the data is allowed to arrive and still be safely captured at
  the *next* edge).
- **Slack** = required − arrival = 4.91 − 4.28 = **+0.63 ns**. Positive:
  this path is fine, with 0.63 ns of margin to spare.

Now suppose an LLM-proposed edit (Chapter 14) adds one more gate to that
combinational cloud, adding 0.9 ns of delay. New arrival time: 4.28 + 0.90 =
5.18 ns. New slack: 4.91 − 5.18 = **−0.27 ns** — a violation, where there
wasn't one before. This is the exact arithmetic `report_checks` is doing
per-path, at scale, for every register pair in the design — and it's why a
single badly-placed extra gate on a previously-comfortable path is enough to
turn a "successful" local edit into a net regression elsewhere (the exact
failure mode Chapter 15's WNS-only-acceptance bug allowed through before it
was fixed).

---

## Chapter 2 — STA Fundamentals

Static Timing Analysis answers one question, over and over, for every
register-to-register path in a design: **"does the signal launched at the
start of this path arrive at the end in time for the next clock edge to
safely capture it?"** It does this *statically* — without simulating any
actual input vectors — by computing worst-case delay bounds through every
path in the design and checking each one against the clock period. This is
why it scales to millions of gates: it never has to "run" the circuit.

### Setup and hold, precisely

For a simple same-clock-domain path:

- **Setup check**: data launched at time `T_launch` must arrive at the
  capturing register no later than `T_capture_edge - setup_time`. Violating
  this is a **max-path** violation — the classic "path is too slow" failure.
- **Hold check**: data must not arrive so *fast* that it changes before
  `T_capture_edge + hold_time` has passed since the *previous* edge — i.e.
  the new data must not race ahead and corrupt the value the register is
  still trying to capture from the previous cycle. Violating this is a
  **min-path** violation.

In our tool wrapper (`run_sta.tcl`, Chapter 6), you'll see both reported
separately: `report_checks -path_delay max` for setup, `-path_delay min` for
hold. This 1:1 maps to what `run_sta.py` calls `path_type: "max"` vs `"min"`
in its parsed JSON.

### Slack

**Slack = required time − arrival time.** Positive slack means the path is
fine, with that much margin to spare. Negative slack is a violation, and its
magnitude is *how late* the path is — this is the number the LLM loop
optimizes against (Chapter 15). Two summary numbers matter at the design
level:

- **WNS (Worst Negative Slack)** — the single worst (most negative) slack
  across all paths. This is what `report_wns` prints and what
  `sta_data["wns"]["max"]` holds in our JSON.
- **TNS (Total Negative Slack)** — the *sum* of all negative slacks. A design
  can have a small WNS but a huge TNS if hundreds of paths are all slightly
  violating — that's a systemic issue, not a single bad path, and it changes
  what fix is appropriate.

### Path groups

OpenSTA buckets paths by which clock's *endpoint* register they land on
(`Path Group` in `report_checks` output). In a multi-clock design like
`nebula_soc`, this is not cosmetic — it's how you tell whether the violating
paths are concentrated in one clock domain (fixable locally) or spread across
several (a structural problem). Our `constraint.sdc` (Chapter 11) has ten
groups: `clk0`..`clk4` and `div_clk0`..`div_clk4`.

### Why STA needs a netlist, not just RTL

STA cannot compute a delay number from Verilog alone — `a & b` has no
inherent nanosecond cost. It needs: (1) a synthesized netlist of actual
standard cells, because each cell type has a real delay characterized in a
Liberty (`.lib`) file, and (2) either real parasitics from placement/routing,
or (for a fast pre-placement estimate) wireload assumptions. This is exactly
why the loop in this project runs Yosys *before* OpenSTA on every iteration
(Chapter 5, Chapter 12) — there is no such thing as "the timing of this RTL"
without first picking a technology and mapping to it.

---

## Chapter 3 — SDC: The Language of Constraints

SDC (Synopsys Design Constraints) is not part of the netlist and not part of
the RTL — it's a separate Tcl-based file that tells the STA tool *what to
check* and, just as importantly, *what not to check*. A netlist with no SDC
has no defined "correct" timing at all: the tool doesn't know what a clock
is, what frequency it should run at, or which ports are asynchronous.

The five commands that matter for this project, in the order you'll actually
write them:

**`create_clock -name <name> -period <ns> [get_ports <port>]`** — declares a
primary clock. Nothing before this line exists as a timed object.

**`create_generated_clock -name <name> -source <master_port> -divide_by <n>
<pin>`** — declares a clock that is *derived* from another clock by logic
(a divider, in our case). The `<pin>` argument is the pin in the netlist that
actually toggles at the divided rate — see Chapter 11 for why finding this
pin correctly, on a flattened OpenSTA netlist, was harder than it sounds.

**`set_clock_groups -asynchronous -group {...} -group {...}`** — tells the
tool "do not check timing *between* these groups of clocks, they have no
fixed relationship." Without this, OpenSTA will try to compute setup/hold
between every clock pair in the design by default, and will report
nonsensical violations on paths that cross via a properly-designed CDC
synchronizer (which are not supposed to meet single-cycle setup — that's the
entire point of a synchronizer).

**`set_input_delay -clock <clk> <ns> [get_ports <port>]`** / **`set_output_delay`**
— model the "cost" already spent, or still to be spent, outside the chip's
boundary for a given I/O port, relative to a clock edge. **Use these only for
genuinely synchronous I/O.** Chapter 11 documents a real bug where applying
`set_input_delay` to an *asynchronous* reset port produced 10 spurious
violations — the tool already generates the correct check (recovery/removal)
for async resets on its own; layering a synchronous check on top is simply
wrong modeling, not conservative modeling.

**`set_false_path -through <pin>`** / **`-from`/`-to`** — tells the tool a
specific path (or one passing through a specific point) should never be
checked at all, because it is provably not a real timing risk even though the
tool's default model would flag it. This is the sharpest tool in the file —
it silently removes a check, so it must be scoped as tightly as possible and
justified in a comment (see Chapter 11 for the generated-clock self-path
case, where we scoped this to `-through <one specific pin>`, never a blanket
exclusion).

### The single most important discipline in this chapter

**Every non-obvious SDC line in this project has a comment above it stating
why the constraint is being relaxed, and what was verified to make that
relaxation safe.** `set_false_path` and skipping `set_input_delay` are both,
in effect, "trust me" instructions to the tool. A trust-me instruction with
no stated reasoning is indistinguishable, six months later, from a mistake
that happens to produce a clean report. Read `constraint.sdc` in Chapter 11
as much for its comments as its Tcl.

---

## Chapter 4 — TCL Fundamentals for EDA Scripting

Every tool in this pipeline — Yosys, OpenSTA/OpenROAD, EQY — is scripted in
Tcl, not because Tcl is a great general-purpose language, but because it was
the embeddable scripting language available when these tools' APIs were
designed, and the whole EDA industry standardized on it (SDC itself is just a
constrained subset of Tcl commands). You need a working vocabulary, not
mastery.

### The pattern you'll see everywhere: `tool_command -flag value -flag value obj`

Tcl commands take positional and flag arguments freely mixed, e.g. from
`run_sta.tcl`:

```tcl
report_checks -path_delay max -group_path_count $group_count \
    -fields {slew cap input} -digits 4
```

`-path_delay`, `-group_path_count` etc. are flags; `$group_count` is a Tcl
variable substitution (see below); `{slew cap input}` is a Tcl *list literal*
(curly braces = don't interpret contents, pass as a single grouped value).

### Variables and substitution

```tcl
set strategy "default"
if { [info exists ::env(SYNTH_STRATEGY)] } {
    set strategy $::env(SYNTH_STRATEGY)
}
```

`set var value` assigns. `$var` substitutes the value. `::env(NAME)` is Tcl's
handle into the process's environment variables — this is *the* mechanism
this project uses to pass parameters from Python into a Tcl script (see
"Python calls Tcl calls the real tool" below). `[info exists ...]` is a
bracketed command substitution — square brackets mean "run this command, then
substitute its result here," analogous to `$(...)` in shell.

### Object query syntax (`get_*`)

This is where SDC-flavored Tcl looks different from plain Tcl. `get_ports`,
`get_pins`, `get_nets`, `get_clocks` are query commands specific to the STA
tool's Tcl extensions — they return handles to design objects matching a
pattern, e.g.:

```tcl
foreach p [get_pins -quiet -of_objects [get_nets -hierarchical $netname]] {
  if {[get_property $p direction] == "output"} { return $p }
}
```

This is the actual `div_clk_driver` procedure from `constraint.sdc`
(Chapter 11) — it queries all pins connected to a named net, then filters
to the one whose direction is `output` (the driver). `-of_objects` chains
queries: "pins *of* these nets" rather than "pins matching this name
pattern." This chaining is the single most useful Tcl idiom for navigating a
netlist you don't have a clean name for — which, as Chapter 11 explains, is
exactly the situation after OpenSTA's `link_design` flattens hierarchy.

### `proc` — defining a reusable function

```tcl
proc div_clk_driver {netname} {
  foreach p [get_pins -quiet -of_objects [get_nets -hierarchical $netname]] {
    if {[get_property $p direction] == "output"} { return $p }
  }
  error "no output driver pin found for net $netname"
}
```

Standard Tcl function definition: `proc name {args} { body }`. `error "..."`
raises and halts the script with that message — used here so a missing
driver pin fails loudly at SDC-read time rather than silently producing a
malformed generated clock.

### Yosys vs. OpenSTA/OpenROAD Tcl: one crucial difference

Yosys's *native* script format (`.ys` files) is **not** Tcl — it's a flat
list of Yosys commands, one per line, no real control flow. To get real Tcl
(variables, `foreach`, `if`, `proc`) when scripting Yosys, you must invoke it
in **Tcl mode**: `yosys -c script.tcl`, and inside that script, every Yosys
command must be prefixed with the literal word `yosys`:

```tcl
yosys read_verilog -sv $f
yosys hierarchy -top $::env(SYNTH_TOP)
yosys synth -top $::env(SYNTH_TOP)
```

This is exactly what `run_synth.tcl` does (Chapter 5) — every line calls
`yosys <command>`, and the `foreach`/`if` around them are plain Tcl. OpenSTA
and OpenROAD, by contrast, embed a real Tcl interpreter natively and don't
need this prefix — `report_checks`, `read_liberty`, etc. are called directly,
as seen in `run_sta.tcl` (Chapter 6).

### Python calls Tcl calls the real tool — the orchestration pattern

Every wrapper in this project (`run_synth.py`, `run_sta.py`, `run_eqy.py`)
follows the same shape: Python sets environment variables, calls the real
binary with `-c <tcl_script>` (or `eqy` with a config file, which is a
different-but-analogous templated-text approach — see Chapter 9), captures
stdout/stderr, and parses text back into JSON with regexes. Tcl is the
*only* language these tools natively understand for scripting; Python is
*only* the glue that drives them and turns their text reports into
structured data an LLM (or any other consumer) can use. Keep this boundary
in mind while reading Part II — you will never see Python calling an EDA
tool's internals directly, only ever via a subprocess + a Tcl script.

---
---

# Part II — The Toolchain, Tool by Tool

## Chapter 5 — Yosys: RTL Synthesis

### What synthesis actually does

Synthesis converts RTL (behavioral Verilog: `always` blocks, `assign`
statements, arithmetic operators) into a **netlist**: a flat-ish graph of
instances of real standard cells from a specific technology library (here,
`sky130_fd_sc_hd`), connected by wires. Before synthesis, "timing" is not a
meaningful concept for the design — there is no delay number for `a + b`
until you've picked actual `AND`/`XOR`/`FA` gates to build that adder out of.
This is why every tool chapter after this one depends on this one running
first.

### The wrapper: `run_synth.py` + `run_synth.tcl`

We built a standalone synth wrapper deliberately separate from the full ORFS
flow (Chapter 7). ORFS's own synthesis step is bundled inside a much longer
pipeline (floorplan, place, route, ...) that takes minutes; the LLM retry
loop needs a synth result in *seconds*, on every single candidate edit. So
`run_synth.py` calls Yosys directly, synthesis-only, nothing else.

Python side (`run_synth.py`) sets environment variables and invokes Yosys in
Tcl mode:

```python
env["SYNTH_VERILOG"] = ":".join(str(v) for v in verilog_files)
env["SYNTH_TOP"] = top
env["SYNTH_LIBERTY"] = str(liberty)
env["SYNTH_OUT_V"] = str(out_v)
...
result = subprocess.run(
    [str(yosys_exe), "-q", "-c", str(TCL_SCRIPT)],
    cwd=cwd, env=env, capture_output=True, text=True, timeout=600,
)
```

Tcl side (`run_synth.tcl`) does the actual synthesis, five real stages:

```tcl
foreach f $verilog_files {
    yosys read_verilog -sv $f
}
yosys hierarchy -top $::env(SYNTH_TOP)
yosys synth -top $::env(SYNTH_TOP)
yosys dfflibmap -liberty $::env(SYNTH_LIBERTY)
yosys abc -liberty $::env(SYNTH_LIBERTY)
yosys clean -purge
```

Walking through what each stage means:

- **`read_verilog -sv`**: parse the RTL. `-sv` enables SystemVerilog syntax
  (needed even for our "plain Verilog" files, since Yosys's `-sv` parser is
  simply the more complete/modern one).
- **`hierarchy -top <name>`**: build the module hierarchy tree rooted at
  `<name>`, and — critically — flag/remove any modules unreachable from the
  top. Without this, Yosys doesn't know which module is "the design."
- **`synth -top <name>`**: Yosys's built-in generic synthesis script — an
  umbrella covering coarse-grain optimization, FSM extraction, memory
  inference, and mapping to Yosys's internal generic-gate library
  (`$_AND_`, `$_DFF_P_`, etc. — *not* real standard cells yet).
- **`dfflibmap -liberty <lib>`**: map the generic flip-flops to the specific
  sequential cells actually available in the target Liberty file (e.g.
  `sky130_fd_sc_hd__dfxtp_1`). Must happen before `abc`, which only
  tech-maps combinational logic.
- **`abc -liberty <lib>`**: invoke ABC (a separate, embedded logic-synthesis
  engine) to tech-map all remaining combinational logic to real standard
  cells from the Liberty file, and to perform area/delay optimization during
  that mapping. **This is the single highest-leverage command in the whole
  synthesis stage** — see the strategy variants below.
- **`clean -purge`**: remove dangling/unused wires and cells.

### The `clean` vs. `clean -purge` bug

Plain `yosys clean` does **not** remove unused wires or cells that have a
"public" name — anything not starting with the internal `$`/auto-generated
prefix. When Verilog `function` blocks get `proc`-converted internally,
Yosys leaves behind function-local temporary wires with escaped identifier
names like:

```
\sum_tree$func$.../nebula_soc.v:164$921.acc
```

These survived plain `clean`, ended up in the written netlist, and broke
OpenSTA's Verilog parser outright (`syntax error` at the netlist line
containing that escaped name — Verilog identifiers with `$` and `.` inside
an escaped `\...` token are legal Verilog but not something OpenSTA's reader
handled). **Fix: `clean` → `clean -purge`**, which is the aggressive variant
that also sweeps public-named-but-unused objects. One-line fix, but it cost
real debugging time the first time the netlist failed to parse — put this
fix in `run_synth.tcl` on day one for any new project using this flow.

### Why the netlist is written *before* flattening

```tcl
yosys write_verilog -noattr $::env(SYNTH_OUT_V)
yosys flatten
yosys tee -o [format "%s.stat.json" $::env(SYNTH_OUT_V)] stat -json -liberty $::env(SYNTH_LIBERTY)
```

Note the order: the netlist file written to disk is the **hierarchical**
one, *before* `flatten` runs. `flatten` only happens afterward, on a
throwaway in-memory copy, purely to get accurate whole-design cell/area
totals (a hierarchical `stat` double-counts submodule instances). This
ordering matters enormously for Stage 8 (Chapter 16): OpenSTA's own
`link_design` will flatten the netlist anyway when it loads it for STA, but
*keeping instance names like `dpath.b_reg...` in the written netlist* is
what lets `rtl_hierarchy.py` map a violating path's instance names back to
the RTL submodule that contains them. Flatten the file on disk and that
mapping becomes permanently impossible — every instance collapses to an
opaque `_243_`-style autogenerated name with no trace of which RTL module it
came from.

### Synthesis-only retry strategies

`run_synth.tcl` supports three strategies via `SYNTH_STRATEGY`, selected
right before the `abc` call:

```tcl
if { $strategy eq "retime" } {
    yosys abc -liberty $::env(SYNTH_LIBERTY) -dff
} elseif { $strategy eq "timing_driven" } {
    if { ![info exists ::env(SYNTH_ABC_PERIOD_PS)] } {
        puts "ERROR: SYNTH_STRATEGY=timing_driven requires SYNTH_ABC_PERIOD_PS"
        exit 1
    }
    yosys abc -liberty $::env(SYNTH_LIBERTY) -D $::env(SYNTH_ABC_PERIOD_PS)
} else {
    yosys abc -liberty $::env(SYNTH_LIBERTY)
}
```

- **`default`**: ABC's normal area-leaning heuristic mapping.
- **`retime`** (`-dff`): ABC performs sequential retiming *during*
  tech-mapping — it can move existing register boundaries earlier or later
  through combinational logic to balance path delays, entirely at the tool
  level, with **zero RTL change**. This is literally the "retiming" RTL-fix
  technique from CLAUDE.md's four allowed techniques, except free — no LLM
  call, no EQY needed (see Chapter 13 for why: identical RTL source in and
  out means equivalence is trivially guaranteed, not just formally proven).
- **`timing_driven`** (`-D <period_ps>`): re-map with an explicit delay
  target in picoseconds, forcing ABC to prioritize meeting that target over
  its default area/power-leaning behavior. Useful when the bottleneck is
  ABC's default heuristic simply not trying hard enough for the actual
  target frequency, rather than a structural RTL problem.

Why this exists at all, and why it runs *before* ever invoking the LLM, is
covered in full in Chapter 13 — this is the direct answer to the "how many
times do we retry synthesis before touching RTL" design question that came
up early in this project.

### 5.9 Yosys as a standalone tool — the complete practical usage guide

Everything above describes how this project *drives* Yosys through a Tcl
script. You will also need to run Yosys directly, by hand, constantly —
every time you're debugging a new module before wiring it into the wrapper.
This section is that standalone guide.

**Interactive mode** — just run `yosys` with no arguments to get a live
Tcl-command prompt (`yosys>`). This is the single fastest way to
experiment with an unfamiliar RTL file:
```
$ yosys
yosys> read_verilog -sv my_module.v
yosys> hierarchy -top my_module
yosys> synth -top my_module
yosys> stat
yosys> show my_module      # opens a graphviz visualization, if graphviz is installed
yosys> write_verilog out.v
```
Every command you type is logged to the console with its own timing —
useful for spotting which single pass is unexpectedly slow on a large
design.

**One-shot mode (`-p`)** — for a quick single command without writing a
script file:
```bash
yosys -p "read_verilog -sv my_module.v; synth -top my_module; stat"
```
This is exactly the Chapter 0.7 sanity-check pattern — the fastest way to
answer "does this file even parse" before investing in a full wrapper run.

**Script mode (`-c`, what the wrapper uses)**:
```bash
yosys -q -c run_synth.tcl
```
`-q`: quiet — suppress Yosys's normal per-command banner/progress spam,
leaving only `puts` output and errors, which is what makes the wrapper's
stdout/stderr parseable. `-c <file>`: run a Tcl script file rather than
entering interactive mode. Drop `-q` while debugging a new script by hand —
the extra verbosity shows you exactly which command is currently running
when something hangs or errors.

**Logging (`-l`)** — capture full session output to a file regardless of
`-q`, useful for a run you might need to inspect later without re-running
it:
```bash
yosys -q -c run_synth.tcl -l /tmp/synth_run.log
```

**Useful diagnostic commands to run inside any Yosys session, in the order
you'd typically reach for them:**
- `stat` — cell count and area breakdown by cell type; the first thing to
  check after any synthesis run, and the fastest way to sanity-check that a
  design synthesized to a *plausible* scale (Figure E.1's "what to look
  for" applies here directly).
- `stat -json` — machine-readable form of the above; what `run_synth.tcl`'s
  `tee -o ... stat -json` line captures for the wrapper to parse.
- `check` — structural sanity checks (undriven nets, multiple drivers,
  combinational loops at the Yosys-internal level — a useful second opinion
  alongside Verilator's lint, Chapter 8, though it catches a different,
  narrower set of issues since it operates post-synthesis on gates, not
  pre-synthesis on RTL semantics).
- `show <module>` — a graphviz schematic of the current design state;
  invaluable for building an intuition for what a `synth` pass actually did
  to a small module, far less useful once cell counts climb past a few
  hundred (the rendered graph becomes unreadable).
- `select -list` / `select <pattern>` — Yosys's object-query language for
  scripting against specific wires/cells by name or pattern, the Yosys-side
  analogue of OpenSTA's `get_*` commands (Chapter 4).
- `torder` — computes topological evaluation order (technically Yosys's
  own combinational-loop detector); a lower-level counterpart to
  Verilator's `UNOPTFLAT` (Chapter 8) worth cross-checking against on a
  suspicious signal.

**Flags worth knowing for the `synth` command specifically** (i.e.
`yosys synth -top X <flags>`):
- `-flatten` — flatten the design during synthesis rather than after (this
  project deliberately does *not* pass this, per the "why the netlist is
  written before flattening" section above — do not add it to
  `run_synth.tcl` without re-reading that section first).
- `-noabc` — skip the ABC tech-mapping stage entirely, leaving generic
  gates; useful only for inspecting Yosys's own optimization output in
  isolation, never for a netlist you intend to hand to STA (generic gates
  have no real Liberty timing data).
- `-run <from>:<to>` — run only a sub-range of `synth`'s internal pass
  list by label; an advanced escape hatch for isolating exactly which
  internal sub-pass changes a specific piece of logic, useful when a
  mystery optimization needs to be attributed to a specific stage.

**A realistic debugging session, start to finish**, for "my new module
won't synthesize cleanly":
```bash
yosys -p "
read_verilog -sv my_new_module.v;
hierarchy -top my_new_module -check;
synth -top my_new_module;
stat
"
```
The `-check` flag on `hierarchy` is worth adding specifically during
debugging — it upgrades hierarchy problems (a referenced submodule that was
never read in, a top module with no driven outputs) from warnings to hard
errors, so you find out immediately rather than several passes later when
`synth` fails with a much more confusing message about a module it expected
to exist.

---

## Chapter 6 — OpenSTA: Static Timing Analysis

### The wrapper: `run_sta.py` + `run_sta.tcl`

Same Python-sets-env / Tcl-does-the-work split as Chapter 5. The Tcl script
supports two input modes:

```tcl
if { $have_db } {
    read_db $::env(STA_DB)
} else {
    read_lef $::env(STA_TLEF)
    read_lef $::env(STA_LEF)
    read_verilog $::env(STA_NETLIST)
    link_design $::env(STA_TOP)
}
read_sdc $::env(STA_SDC)
```

- **`--db` mode**: load a post-place-and-route `.odb` database (from the full
  ORFS flow, Chapter 7). This has real, physical parasitics — accurate
  timing, but only available after the expensive full flow has run.
- **`--netlist` mode**: load a synthesized-but-unplaced Verilog netlist
  directly, using LEF files (`read_lef`) purely so OpenROAD has enough
  physical-cell information to build an internal database and estimate
  wire delay via wireload models, without ever running placement. This is
  what the LLM retry loop uses on *every* iteration — running full P&R per
  candidate edit would make the loop too slow to be usable.

`link_design $::env(STA_TOP)` is the step referenced constantly in Chapter 11
— this is exactly where OpenSTA flattens the hierarchy down to leaf
standard-cell instances, discarding submodule port identity in the process.

Then the actual report:

```tcl
puts "=== BEGIN MAX PATHS ==="
report_checks -path_delay max -group_path_count $group_count \
    -fields {slew cap input} -digits 4
puts "=== END MAX PATHS ==="

puts "=== BEGIN MIN PATHS ==="
report_checks -path_delay min -group_path_count $group_count \
    -fields {slew cap input} -digits 4
puts "=== END MIN PATHS ==="

puts "=== BEGIN WNS TNS ==="
report_wns
report_tns
puts "=== END WNS TNS ==="
```

The `=== BEGIN/END ... ===` markers are not an OpenSTA feature — they're
plain `puts` delimiters we added, purely so `run_sta.py`'s Python side can
slice the combined stdout into three sections with `str.index()` before
regex-parsing each independently (`extract_section()`).

### Turning report text into structured JSON

This is the single most surgical piece of code in the whole project, because
OpenSTA's `report_checks` output is plain fixed-width text meant for a human
to read, and the LLM loop needs it as structured data. The parsing logic in
`run_sta.py` uses regexes tuned to the exact `report_checks` format:

```python
PATH_BLOCK_RE = re.compile(
    r"Startpoint: (?P<startpoint>\S+)\s+"
    r"\((?P<startpoint_desc>[^)]*)\)\s*\n"
    r"Endpoint: (?P<endpoint>\S+)\s+"
    r"\((?P<endpoint_desc>[^)]*)\)\s*\n"
    r"Path Group: (?P<group>\S+)\s*\n"
    r"Path Type: (?P<path_type>\S+)\s*\n"
    r"(?P<body>.*?)"
    r"slack \((?P<status>MET|VIOLATED)\)",
    re.DOTALL,
)
```

and, per path, a cell-by-cell delay-table row parser:

```python
CELL_LINE_RE = re.compile(
    r"^\s*(?P<cap>[\d.]+)?\s*(?P<slew>[\d.]+)?\s+(?P<delay>[\d.]+)\s+(?P<time>[\d.]+)\s+[\^v]\s+"
    r"(?P<pin>\S+)\s+\((?P<cell>[^)]+)\)\s*$",
    re.MULTILINE,
)
```

Each parsed path becomes one JSON object with `startpoint`, `endpoint`,
`path_group`, `path_type` (max/min), `slack`, `status` (MET/VIOLATED), and a
full `cells` list (pin, cell type, incremental delay, cumulative time) — this
`cells` list, formatted back into readable text by `worst_path_summary()` in
`llm_loop.py`, is *literally what the LLM reads* to understand a critical
path (Chapter 14). If this regex silently mis-parses (e.g. OpenSTA changes
its report format in a future version), the LLM gets garbage input with no
visible error — this parser is a load-bearing wall for the entire loop and
should be spot-checked against `--raw-out` (see below) any time OpenSTA is
upgraded.

**`--raw-out`** exists for exactly that reason: pass it and the *raw*
pre-parse OpenSTA text is also saved, so you can always sanity-check the
parsed JSON against ground truth.

### WNS/TNS parsing

```python
def parse_wns_tns(section_text):
    wns = {}
    tns = {}
    for line in section_text.strip().splitlines():
        m = re.match(r"wns\s+(\S+)\s+(-?\d+\.\d+)", line)
        if m:
            wns[m.group(1)] = float(m.group(2))
            ...
```

`report_wns`/`report_tns` print one line per path group (e.g. `wns clk2
-0.849`), so the parsed result is a dict keyed by path-group name, plus
(implicitly) an overall figure under a group like `"max"` — this is what
`sta_data["wns"]["max"]` (used throughout `llm_loop.py`) actually refers to:
the worst slack across the whole design, not one specific clock domain.

### Reading a real `report_checks` output

Here is an actual worst path from an early, still-broken `constraint.sdc`
(before the false-path fix in Chapter 11) — reproduced to show what you are
actually looking at when this all goes right, and to make Chapter 11's fix
concrete:

```
Startpoint: u_div0/toggle_reg
            (rising edge-triggered flip-flop clocked by clk0)
Endpoint: u_div0/toggle_reg
            (rising edge-triggered flip-flop clocked by div_clk0)
Path Group: div_clk0
Path Type: max

  ...delay table omitted...

   -8.486   slack (VIOLATED)
```

Startpoint and endpoint are the *same register* — this is a self-path (the
divider's own toggle flip-flop feeding its own next-state logic), and it is
launched by `clk0` but captured by `div_clk0`, its own generated clock. That
mismatch (same physical register, two different named clocks on the two ends
of the check) is precisely the modeling artifact diagnosed and fixed in
Chapter 11.

### 6.9 OpenSTA as a standalone tool — the complete practical usage guide

**Interactive mode**: run `sta` with no arguments for a live Tcl prompt,
exactly like Yosys's interactive mode (Chapter 5.9). The command sequence
you'd type by hand mirrors `run_sta.tcl` exactly:
```
$ sta
% read_liberty sky130hd_tt.lib
% read_lef sky130hd.tlef
% read_lef sky130hd_std_cell.lef
% read_verilog netlist.v
% link_design my_top
% read_sdc constraint.sdc
% report_checks -path_delay max
```
Typing this by hand once, on a small design, before ever trusting the
Python wrapper, is the single best way to build real intuition for what
each stage actually does — you see each command's own output/errors in
isolation instead of a bundled JSON at the end.

**The report commands you'll use constantly, with the flags that matter:**

- `report_checks` — the single most important command in this whole
  toolchain. Key flags:
  - `-path_delay max|min|max_min` — max = setup checks (the usual concern),
    min = hold checks, max_min = both. Defaults to max if omitted, so an
    omitted flag silently means "I am not checking hold at all" — a real
    trap on a design you haven't explicitly checked hold on yet.
  - `-group_path_count N` — how many worst paths to print per path group,
    not a global total; on a 5-clock-domain design this means the *true*
    total worst-path count printed is up to `5 × N`. This is exactly why
    `run_sta.py`'s own `--group-count` argument exists and why Chapter 6's
    "why every edit is checked against its own predecessor" logic needs to
    request enough paths per group to actually see a regression on a
    domain that wasn't previously the worst.
  - `-fields {slew cap input}` — extra per-cell annotation columns; see
    Appendix D.3 for exactly what each adds and why this project always
    requests all three.
  - `-digits N` — decimal precision on printed numbers; this project fixes
    it at 4 specifically so downstream regex parsing (Appendix D.4) has a
    consistent number of digits to match against.
  - `-unique_paths_to_endpoint` — collapses multiple paths that share the
    same endpoint (common on a fanout-heavy net) down to just the worst
    one per endpoint; useful when you want a *diverse* sample of distinct
    problem locations rather than N variations of the same bottleneck.
- `report_wns` / `report_tns` — worst/total negative slack, one line per
  path group; the fastest single command to run after any edit to know
  "did this help or hurt," before reading a single full path.
- `report_clocks` — lists every clock OpenSTA currently knows about,
  including generated clocks, their period, and their source — the first
  command to run when an SDC change "does nothing," since a typo'd clock
  name in `set_clock_groups` or a generated clock that failed to resolve
  its source pin will show up here as simply missing from the list, before
  you waste time debugging `report_checks` output that's using stale
  clock definitions.
- `report_units` — confirms the time/capacitance/resistance unit
  convention in effect (this project's Liberty files use nanoseconds);
  worth checking once per new PDK before trusting any raw numbers, since a
  unit mismatch between what you *assume* and what the Liberty file
  actually declares silently produces numbers that are wrong by a fixed
  order of magnitude (typically 1000x, ns vs. ps) with no error at all.
- `report_power` — not used by this project's fast loop (Chapter 7 covers
  why full PPA numbers, including power, come from the slower ORFS flow
  instead), but useful to know exists for a final deliverable's
  power/performance/area table.

**A realistic standalone debugging session** for "why does this path show
a violation I don't expect":
```
% report_checks -path_delay max -group_path_count 1 -to [get_pins u_bad/D]
% report_clocks -digits 4
% get_property [get_pins u_bad/CK] clocks
```
`-to [get_pins ...]` narrows the report to paths ending at one specific
pin — invaluable once you already have a suspect from a JSON report
(Appendix E) and want to re-inspect just that one path interactively rather
than re-reading a full report. `get_property ... clocks` on a clock pin
directly answers "which clock does OpenSTA actually think is driving
this register," which is the fastest way to catch a clock-definition typo
or an unresolved generated-clock source before it produces a confusing
downstream violation.

---

## Chapter 7 — OpenROAD-flow-scripts: Full RTL-to-GDS and PPA

`run_synth.py`/`run_sta.py` are our own fast, synthesis-only and STA-only
tools, built for the tight loop. **ORFS is the real, complete flow** — RTL in,
GDSII (a manufacturable layout) out — and it is what produces trustworthy
final PPA (Power, Performance, Area) numbers, because only *after* placement
and routing do you have real physical parasitics rather than wireload
estimates.

### Where ORFS fits relative to the fast loop

Think of it as two different fidelity/cost tiers of the same underlying
question ("is this design's timing OK?"):

| | Fast tier (`run_synth.py`+`run_sta.py`) | Full tier (ORFS) |
|---|---|---|
| Runtime | seconds | minutes–hours |
| Timing accuracy | estimated (wireload) | real (placed & routed parasitics) |
| Used for | every LLM edit candidate, every retry | final PPA report, before/after comparison for the demo |
| Stages | synth only | synth → floorplan → place → CTS → route → finish |

The LLM loop (Chapter 12) runs entirely on the fast tier — it would be
unusable if every candidate edit needed a full ORFS run. ORFS is run once at
the *start* (baseline PPA) and once at the *end* (final PPA, after the loop
has converged) to produce the honest, physically-accurate before/after
numbers required by the official Nebula deliverable checklist ("Timing,
frequency and PPA comparison"). Reporting the fast tier's numbers as final
PPA would be misleading — they are directionally useful for the loop's
accept/reject decisions but are not placed-and-routed truth.

### Practical notes for our benchmark

`sky130hd` is the platform directory (`platforms/sky130hd/`) — LEF/Liberty
files under this path are the same ones the fast tier's `run_sta.py --tlef`/
`--lef`/`--liberty` flags point at, so both tiers are always analyzing
against the identical standard-cell library. A full ORFS run's final,
placed-and-routed netlist can also be fed straight into `run_sta.py --db
<path>/6_final.odb` for a spot-check against the fast tier's numbers on the
same design — useful once, early on, to confirm the two tiers agree closely
enough to trust the fast tier during the loop.

### 7.6 ORFS as a standalone tool — the complete practical usage guide

ORFS is driven by `make`, not by invoking OpenROAD directly — the Makefile
under `flow/` wraps the entire multi-stage pipeline and handles
stage-to-stage artifact passing for you. A new design needs a design
config before any of this works:

```makefile
# designs/sky130hd/nebula_soc/config.mk
export DESIGN_NAME = nebula_soc
export PLATFORM    = sky130hd
export VERILOG_FILES = $(sort $(wildcard $(DESIGN_HOME)/src/$(DESIGN_NAME)/*.v))
export SDC_FILE     = $(DESIGN_HOME)/sky130hd/$(DESIGN_NAME)/constraint.sdc
export CORE_UTILIZATION = 40
export PLACE_DENSITY = 0.65
```
`CORE_UTILIZATION`/`PLACE_DENSITY` are floorplan sizing knobs — too low a
utilization wastes die area (harmless for a competition demo, just
cosmetically odd on the final layout image); too high can make placement
or routing fail to converge entirely, which shows up as the `place` or
`route` stage erroring out partway rather than as a timing problem, so if
a run fails at those stages specifically (not at `synth`), this is the
first knob to check before assuming there's an RTL issue.

**The stage-by-stage targets**, run individually so you can inspect
intermediate results, or chained via `make` dependency resolution:
```bash
cd OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk synth
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk floorplan
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk place
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk cts
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk route
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk finish
```
or, to run the whole pipeline in one call and let `make` figure out the
dependency chain:
```bash
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk
```
Each stage writes its artifact into `results/sky130hd/nebula_soc/base/`
(named by stage number, e.g. `2_floorplan.odb`, `3_place.odb`,
`6_final.odb`) — this is exactly the `.odb` path `run_sta.py --db` expects
for a spot-check against the fast tier (Chapter 7's "practical notes"
above).

**Useful reporting targets, once a run completes:**
```bash
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk gui_final
```
Opens OpenROAD's GUI on the final routed layout — the actual visual GDS-ish
view, useful for a competition demo screenshot of real physical layout
(placement congestion, routing density) that no text report can convey.

```bash
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk report
```
Regenerates the full metrics report (area, power, timing, DRC violation
count) for the current results directory without re-running the whole
flow — the fastest way to re-check final numbers after only inspecting,
not re-running, a completed pipeline.

**Cleaning up before a re-run** — ORFS caches aggressively by design; a
stale artifact from a previous RTL version can silently linger if you edit
RTL and re-run without cleaning:
```bash
make DESIGN_CONFIG=./designs/sky130hd/nebula_soc/config.mk clean_all
```
`clean_all` (not plain `clean`, which only removes the current stage's
output) removes every stage's artifact for this design — the safe default
any time you've changed RTL and are unsure whether a stale intermediate
`.odb` might otherwise be silently reused.

**Realistic timing expectations**, so you can plan a competition timeline
around this: on a ~50,000-cell design on ordinary development hardware,
expect `synth` in under a minute, `floorplan`+`place` together in a few
minutes, `cts`+`route` as the dominant cost (often 10–30+ minutes combined,
scaling faster than linearly with congestion), and `finish` (final DRC/report
generation) in another minute or two. Never schedule your *first* full ORFS
run of a new, larger RTL revision for the hour before a demo — run it once,
early, on the design you intend to actually present, so any convergence
failure (place/route failing to close) surfaces with enough time left to
adjust `PLACE_DENSITY`/`CORE_UTILIZATION` or simplify the RTL rather than
discovering it live.

---

## Chapter 8 — Verilator Lint: Catching What Synthesis and STA Cannot

### The gap this closes

Neither of the two "correctness" gates already in this pipeline actually
proves a design is *functionally sound*:

- **EQY (Chapter 9)** proves gold RTL and gate RTL compute the *same
  function*. If both are broken the same way — or if gold itself has a bug —
  EQY happily proves them equivalent. It compares two specific snapshots to
  each other; it has no independent notion of "correct."
- **OpenSTA** assumes the netlist it's given is a legitimate, well-formed
  digital circuit and only ever asks "is it fast enough?" — never "is it
  even a sane circuit?" A netlist with a real, physical combinational loop
  will get a timing report from OpenSTA; the tool has no obligation to flag
  the loop itself as a defect.

**Lint is the only tool in this pipeline that checks RTL *style and
structural legality* against known-bad patterns** — inferred latches,
blocking assignment in a clocked block, incomplete `case` coverage, multiply
driven nets, and, critically for this project, genuine combinational loops.

### The wrapper: `run_lint.py`

```python
HARD_CODES = {
    "LATCH", "COMBDLY", "BLKSEQ", "MULTIDRIVEN", "CASEINCOMPLETE",
    "CASEOVERLAP", "UNOPTFLAT",
}

WARNING_RE = re.compile(
    r"%Warning-(?P<code>[A-Z0-9]+):\s*(?P<file>[^:]+):(?P<line>\d+):\d+:\s*(?P<msg>.*)"
)

def run_lint(verilator_exe, verilog_files, top, extra_args):
    cmd = [str(verilator_exe), "--lint-only", "-Wall"] + extra_args + \
          ["--top-module", top] + [str(v) for v in verilog_files]
    result = subprocess.run(cmd, cwd=FLOW_DIR, capture_output=True, text=True, timeout=120)
    return result
```

`--lint-only` runs Verilator's frontend checks *without* generating any
simulation model — fast, and doesn't need a testbench. `-Wall` enables the
full warning set (Verilator is conservative by default and hides many
useful checks otherwise).

### Why lint is *not* a blanket pass/fail gate

The obvious design would be "zero Verilator warnings, or reject." We
deliberately did not build it that way, because our own baseline design
(`gcd.v`, used for loop-mechanics smoke tests) already carries pre-existing
warnings (a `LATCH` in `gcd.ctrl`) that predate this pipeline entirely and
are not this project's to fix. A blanket gate on that baseline would be
permanently red from the first commit, teaching everyone to ignore it.

Instead: classify warnings into `HARD_CODES` (real correctness risk) vs.
everything else (informational — width mismatches, unused signals, which
are style noise for our purposes), and record both counts. **The intended
usage is diffing hard-warning counts against a stored baseline** — an LLM
edit is rejected only if it *increases* the hard-warning count relative to
the baseline for that design, never on the absolute count. (As of this
writing, this diff step is designed but not yet wired as an automatic gate
inside `llm_loop.py` — see Chapter 20's open items.)

```python
record = {
    "run_id": args.run_id, "top": args.top, "verilog": args.verilog,
    "returncode": result.returncode,
    "num_warnings": len(warnings), "num_hard_warnings": len(hard),
    "warnings": warnings, "hard_warnings": hard,
}
```

### A real bug this caught, that nothing else in the pipeline would have

This is the concrete justification for having lint in the pipeline at all,
not a hypothetical. Running `run_lint.py` on `nebula_soc.v` produced:

```
%Warning-UNOPTFLAT: nebula_soc.v:96:3: Signal unoptimizable: Feedback to
  clock or circular logic: 'async_fifo.wr_full'
```

`UNOPTFLAT` is Verilator's flag for a signal it cannot linearly schedule for
simulation — the textbook signature of a **real combinational loop**, not a
benign false positive. Investigating (rather than dismissing this as ring-
topology noise) turned up an actual bug: `async_fifo`'s lookahead pointer
logic computed `wr_ptr_bin_next` using `wr_en && !wr_full`, but `wr_full`
was itself derived from `wr_ptr_gray_next`, which depends on
`wr_ptr_bin_next` — a closed loop: `wr_full → wr_ptr_bin_next →
wr_ptr_gray_next → wr_full`.

Full diagnosis and both-sided fix (write-side *and* a second instance on the
read side, `rd_empty`/`rd_en`) is in Chapter 10, since it's really a lesson
about the design, not about the lint tool. The point for this chapter: **STA
was clean the entire time this bug existed in the RTL.** EQY, run against
this exact broken RTL as its own gold reference, also reported
`PROVED_EQUIVALENT` (self-identity is trivially true). Lint was the only
gate that ever saw the problem.

### 8.7 Verilator as a standalone tool — the complete practical usage guide

**Basic lint invocation**, no wrapper:
```bash
verilator --lint-only -Wall --top-module nebula_soc nebula_soc.v
```
Warnings print to **stderr** — a real gotcha the first time you run this
and see nothing on your terminal because you piped only stdout somewhere;
always capture or watch stderr specifically.

**The flags worth knowing:**
- `--lint-only` — frontend elaboration and checks only; no simulation
  model is built, which is what makes this fast enough to run on every
  candidate edit if you ever wanted to extend the loop to include it
  per-iteration (this project currently runs lint once as a baseline
  check, not per-edit — see Chapter 20's open items for why extending it
  per-edit is a reasonable but not-yet-done improvement).
- `-Wall` — enables Verilator's full non-default warning set; without it,
  many of the `HARD_CODES` warnings (Appendix D.1) simply never fire,
  since several (including `UNOPTFLAT`) are not in Verilator's default
  warning set.
- `-Wno-<CODE>` — suppress one specific warning code; this project uses
  this per-run via `--ignore` (e.g. `-Wno-BADVLTPRAGMA` for `gcd.v`'s
  pre-existing noise) rather than editing `HARD_CODES`, keeping the
  suppression scoped to the specific known-noisy file rather than globally
  silencing that warning class everywhere.
- `--top-module <name>` — required whenever the file set contains more
  than one module with no instantiation relationship between them (or, as
  here, to disambiguate explicitly rather than rely on Verilator's own
  top-inference heuristic).
- `-sv` — SystemVerilog parsing mode; add this if your RTL uses SV
  constructs (`always_ff`, `logic`, interfaces) that this project's plain
  Verilog benchmark doesn't need but yours might.
- `--timing` — required in recent Verilator versions if your RTL contains
  delay statements (`#5`) inside synthesizable-looking code, even though
  such code should never appear in real synthesizable RTL in the first
  place — if you see a timing-related parse error on RTL you believe is
  synthesizable, this is usually the sign of an accidental non-synthesizable
  construct that slipped in, not a flag you should reach for as a fix.

**A realistic triage workflow** for a large warning list on a design you
didn't write:
```bash
verilator --lint-only -Wall --top-module top top.v 2>lint.txt
grep -oE '%Warning-[A-Z0-9]+' lint.txt | sort | uniq -c | sort -rn
```
This gives you a warning-code frequency table in one line — triage the
`HARD_CODES` (Appendix D.1) rows first regardless of their count, then
skim whether any single informational code dominates the list (often a
sign of one systemic, low-risk pattern repeated many times, e.g. unused
bits in a wide bus) before deciding whether it's worth a closer look at
all.

---

## Chapter 9 — EQY / SymbiYosys: Formal Equivalence Checking

### What EQY actually proves

EQY (`YosysHQ/eqy`, built on `sby`) proves — using a SAT solver, not
simulation — that two RTL descriptions of a module ("gold" and "gate")
compute **exactly the same output for every possible input sequence**, up to
a bounded unrolling depth. This is categorically stronger than any amount of
simulation: simulation can only ever check the specific vectors you ran;
formal equivalence checking (within its bounded depth) checks *all* of them.

This is the project's non-negotiable safety net (per CLAUDE.md's design
principle, restated here because it's worth restating): **the LLM never gets
to propose an edit that reaches synthesis without first being proven
equivalent to the RTL it was derived from.** If EQY fails or is ambiguous,
the edit is discarded, full stop, no exceptions, regardless of how good the
resulting timing looks.

### The wrapper: `run_eqy.py`

EQY is configured via a small `.eqy` config file (not a `.tcl` script,
though it drives Yosys under the hood) — we generate this file per run from
a template:

```python
EQY_TEMPLATE = """\
[gold]
read_verilog {gold_flags}{gold}
prep -top {top}

[gate]
read_verilog {gate_flags}{gate}
prep -top {top}

[strategy sat]
use sat
depth {depth}
"""
```

Two named sections (`[gold]`, `[gate]`) each read one RTL source and run
`prep -top <module>` (Yosys's standard front-end elaboration); `[strategy
sat]` selects the SAT-based equivalence engine with a bounded unroll `depth`
(default 5 cycles in our wrapper — deep enough to catch pipeline-stage
mismatches from a pipelining edit, the most common technique the LLM will
propose).

### Classifying the result — and why exit code alone is not trusted

```python
def classify(proc):
    log = proc.stdout + proc.stderr
    if re.search(r"Successfully proved designs? equivalent", log):
        return True, "PROVED_EQUIVALENT"
    if re.search(r"Failed to prove equivalence", log) or proc.returncode not in (0,):
        return False, "NOT_EQUIVALENT_OR_ERROR"
    return False, "AMBIGUOUS_OUTPUT"
```

Three explicit outcomes, and the default (no clear match) is treated as a
**rejection**, not a pass. This matters: a tool that crashes, times out, or
produces output in a format we didn't anticipate should never be silently
treated as "equivalent" just because nothing explicitly said "not
equivalent." `run_eqy.py`'s own exit code mirrors this (`sys.exit(0 if
equivalent else 1)`), and its docstring states plainly that callers should
branch on the *process* exit code, not just parse the JSON — so a crashed
run can never slip through a caller that forgets to check the `equivalent`
field.

### What EQY does *not* prove — the important caveat

EQY proves gold ≡ gate for the two snapshots you hand it. It says nothing
about whether **gold itself** was correct. Running EQY with a design's
current (possibly buggy) RTL as its own gold reference — e.g. checking a
file against an untouched copy of itself, to sanity-check the tool wiring —
will report equivalence trivially and correctly, but this proves nothing
about functional correctness of the design. This is exactly the caveat
noted in Chapter 8: EQY's `PROVED_EQUIVALENT` result on `nebula_soc` both
before and after the `async_fifo` combinational-loop fix is a true, correct
result in both cases — the *post-fix* RTL is not equivalent to the *pre-fix*
RTL (it isn't supposed to be; the fix deliberately changed behavior for the
better), and EQY was never asked that question. Only lint (Chapter 8) and
manual review actually validated the fix was correct; EQY's role there was
narrower: confirming the fix, once made, didn't introduce some *unrelated*
new equivalence break relative to itself as a stable reference for the next
loop iteration.

### Full-design vs. per-module EQY

The loop (Chapter 15) runs EQY per-edit, per-module — gold is the RTL before
this specific edit, gate is the candidate with this edit applied. A separate,
coarser check — full-design EQY, original source vs. the final accumulated
RTL after all accepted edits — is the last checkpoint before ever trusting
the loop's output as a whole. In this project we ran that full-design check
manually against `nebula_soc` (both pre- and post-bugfix RTL, ~113 seconds
each on this design's size) and both reported `PROVED_EQUIVALENT`; wiring
this as an automatic `--final-check` flag on `llm_loop.py` is a documented
open item (Chapter 20).

### 9.9 EQY as a standalone tool — the complete practical usage guide

**Running EQY directly**, without the Python wrapper, is a two-step
process: write a `.eqy` config file (Appendix D.5's `EQY_TEMPLATE`), then
invoke `eqy` on it:
```bash
cat > check.eqy <<'EOF'
[gold]
read_verilog -sv original.v
prep -top my_module

[gate]
read_verilog -sv edited.v
prep -top my_module

[strategy sat]
use sat
depth 5
EOF
eqy check.eqy
```
EQY creates a working directory `check_eqy/` alongside your config,
containing per-partition logs — always check there first if the top-level
exit status alone isn't enough to diagnose a failure.

**Key `.eqy` config knobs:**
- `depth N` under `[strategy sat]` — how many clock cycles the SAT solver
  unrolls; too shallow and a latency-adding edit (pipelining, Chapter
  14) can produce a false `NOT_EQUIVALENT` purely from a bounds limit, not
  a real inequivalence (this exact failure mode is walked through in
  Chapter 19's EQY deep-dive) — when in doubt, double it and re-run before
  trusting a reject.
- Multiple `[gold]`/`[gate]` read commands — for a multi-file design, list
  every source file's `read_verilog` line in both sections; a common
  mistake is forgetting to add a newly-split-out submodule file to both
  sides after refactoring, which produces a confusing "module not found"
  error rather than an equivalence result.
- `[strategy sat]` vs. other strategies (e.g. `miter`, `bmc-native` in
  newer EQY versions) — this project uses `sat` throughout for its balance
  of speed and reliability on the four allowed edit techniques; if you
  extend this project with a technique outside those four, re-evaluate
  which strategy actually fits the structural change you're verifying
  before assuming `sat` still applies.

**Debugging a genuine `NOT_EQUIVALENT` result** — EQY's working directory
contains a counterexample trace when the SAT solver actually finds a
differing input sequence (as opposed to a solver timeout, which produces no
counterexample at all — an important distinction: a *counterexample*
means EQY is telling you something true and specific about where gold and
gate diverge; a bare timeout with no counterexample means EQY simply ran
out of budget and you've learned nothing about correctness either way).
Read the counterexample's stimulus and expected-vs-actual output; this is
the ground-truth artifact to hand back into a fix (or into a *next* LLM
retry's context, if you were extending the loop to include EQY failure
detail as retry feedback beyond what this project currently does).

**Sanity-checking your own EQY setup before trusting it on real edits** —
always run it once with `gold` and `gate` reading the *identical* file.
It must report equivalent, immediately, with a trivial (near-zero-cycle)
proof — if it doesn't, or if it hangs, the problem is in your `.eqy` config
or tool installation (per-file paths, missing `prep -top` typo against the
actual module name), not in any real design difference, and this is the
fastest possible check to isolate that class of error before it gets
confused with a real RTL bug.

---
---

# Part III — The Benchmark Design

## Chapter 10 — Building `nebula_soc`: A 5-Clock-Domain Benchmark

### Why a benchmark design at all

The official Nebula problem statement specifies concrete requirements the
test RTL must exercise: 5 independent asynchronous master clock domains, at
least one generated (divided) clock per master, clock domain crossings
between domains, clock divider logic at multiple ratios, and roughly 50,000
standard cells (a realistic SoC-subsystem scale, not a toy). `nebula_soc.v`
was purpose-built to hit every one of these, and nothing more — every module
in it exists because a specific requirement demanded it.

### Module inventory (`designs/src/nebula_soc/nebula_soc.v`, 518 lines)

| Module | Lines | Purpose |
|---|---|---|
| `clk_divider` | 6–29 | Generates one divided clock per master, at a distinct ratio per instance |
| `async_fifo` | 33–132 | Gray-code-pointer asynchronous FIFO — the real CDC mechanism between domains |
| `compute_pipeline` | 139–191 | The design's actual timing-critical datapath |
| `crc_pipeline` | 199–235 | Secondary datapath, adds combinational depth/variety |
| `domain_ctrl_fsm` | 240–344 | Per-domain control FSM — the FSM-optimization technique's natural target |
| `nebula_soc` | 357–518 | Top level: instantiates 5 of everything above, wires the domains together |

### `clk_divider` — generated clocks

Each of the 5 master clocks (`clk0`..`clk4`, periods 5.0/6.0/4.0/7.0/5.5 ns)
drives one `clk_divider` instance at a distinct divide ratio (2/4/6/8/10 —
"multiple ratios" from the requirement). The divider is a counter that
toggles its output when it reaches half the target period — meaning the
toggle flip-flop's own `Q` both *defines* the generated clock (via
`create_generated_clock` in `constraint.sdc`) *and* feeds back into its own
next-state mux combinationally. This dual role is exactly what produces the
self-path modeling artifact diagnosed in Chapter 11 — it is a direct,
unavoidable consequence of how a clock divider is built in RTL, not a
peculiarity of this specific design, so expect to hit this again on any new
SoC with divided clocks.

### `async_fifo` — the real CDC mechanism, and the bug we found in it

This module is the actual clock-domain-crossing bridge: standard Cummings-
style dual-clock FIFO, Gray-coded read/write pointers, two-flop
synchronizers in each direction (`rd_ptr_gray_sync1/2`, `wr_ptr_gray_sync1/2`),
full/empty flags computed by comparing synchronized Gray pointers.

**The bug (found via lint, Chapter 8, not via STA or EQY):** the original
lookahead-pointer formulas gated the *next* pointer value on the *current*
flag:

```verilog
// BUGGY (pre-fix) -- do not copy this pattern
wire [ADDR_W:0] wr_ptr_bin_next  = wr_ptr_bin + (wr_en & ~wr_full);
wire [ADDR_W:0] rd_ptr_bin_next  = rd_ptr_bin + (rd_en & ~rd_empty);
```

For `wr_full` this is a real, physical combinational loop: `wr_full` is
itself defined in terms of `wr_ptr_gray_next`, which is derived from
`wr_ptr_bin_next` above — so `wr_full` depends on itself through that chain.
**Fix, part 1** — drop the self-gating; the actual memory write is *already*
correctly gated by `wr_en && !wr_full` at the point of use, so the pointer
update itself never needed to protect against overflow a second time:

```verilog
wire [ADDR_W:0] wr_ptr_bin_next  = wr_ptr_bin + wr_en;
wire [ADDR_W:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

wire [ADDR_W:0] rd_ptr_bin_next  = rd_ptr_bin + rd_en;
wire [ADDR_W:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;
```

Re-linting after this showed the *write*-side loop gone, but **one hard
warning still remained** — the exact kind of result that rewards not
stopping at the first fix. Investigating further found a second, distinct
instance of the same class of bug: at the top level, `rd_en` is wired
**combinationally** as `!rd_empty` (an auto-drain-while-available pattern —
whenever the FIFO isn't empty, read immediately). `rd_empty`'s definition
still used the lookahead `rd_ptr_gray_next`, which itself depends on `rd_en`
— closing the loop again, this time *through the module boundary* rather
than internally.

Note the asymmetry: `wr_full` using the lookahead pointer is *safe*, because
`wr_en` is driven externally by a registered signal in the surrounding
design, never combinationally tied back to `wr_full` itself. `rd_empty`
using the lookahead pointer is *not* safe, because `rd_en = !rd_empty` at
the call site closes that exact loop. Same lookahead-pointer pattern, two
different structural contexts, only one of them a real bug — this is why
lint (which reasons about the *actual* dataflow graph) caught it and neither
STA nor a naive code-symmetry read would have.

**Fix, part 2** — use the current, already-registered pointer for
`rd_empty` (the standard, non-lookahead textbook empty-flag definition,
which depends only on already-latched state and cannot loop):

```verilog
assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);
```

`wr_full`'s lookahead-based definition was deliberately left unchanged —
it's correct as-is, and "fixing" a signal that isn't broken just to make the
two flags textually symmetric would have been change for its own sake.

Post-fix lint: **0 hard warnings** (down from 2), confirmed by re-running
`run_lint.py`. Full-design EQY (Chapter 9) confirmed the fix didn't break
the loop's own equivalence-checking mechanics going forward, though as
Chapter 9 explains, the *correctness* of this specific fix rests on the
reasoning above and the lint-clean result, not on EQY (which cannot compare
a functional bugfix against its own pre-fix behavior and call one "more
correct").

### `compute_pipeline` — the deliberate critical-path source

```verilog
module compute_pipeline #(
  parameter WIDTH = 16,
  parameter LANES = 4
) (
  input  wire                      clk,
  input  wire                      rst_n,
  input  wire                      valid_in,
  input  wire [WIDTH*LANES-1:0]    a_in,
  input  wire [WIDTH*LANES-1:0]    b_in,
  output reg                       valid_out,
  output reg  [2*WIDTH+$clog2(LANES)-1:0] acc_out
);
  ...
  genvar i;
  generate
    for (i = 0; i < LANES; i = i + 1) begin : lane
      assign a[i] = a_in[(i+1)*WIDTH-1 -: WIDTH];
      assign b[i] = b_in[(i+1)*WIDTH-1 -: WIDTH];
      assign prod[i] = a[i] * b[i];
    end
  endgenerate

  function [SUMW-1:0] sum_tree;
    input integer n;
    integer j;
    reg [SUMW-1:0] acc;
    begin
      acc = {SUMW{1'b0}};
      for (j = 0; j < n; j = j + 1)
        acc = acc + prod[j];
      sum_tree = acc;
    end
  endfunction

  wire [SUMW-1:0] sum_comb = sum_tree(LANES);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      acc_out   <= {SUMW{1'b0}};
    end else begin
      valid_out <= valid_in;
      acc_out   <= sum_comb;
    end
  end
endmodule
```

This is a single-cycle multiply-accumulate: `LANES` parallel WIDTH-bit
multiplies feeding a fully combinational adder tree (`sum_tree`, a Verilog
`function` — note this is exactly the construct whose Yosys-generated
temporary wires triggered the `clean -purge` bug in Chapter 5; you will see
this module's own line numbers in that netlist-parse error if you ever
regress that fix), registered once at the output. This is the module
carrying the design's worst *genuine* — not modeling-artifact — slack
(historically around 0.82 ns before any synth-retry or LLM edits are
applied), because a multiply followed immediately by a full adder tree, all
in one cycle with no intermediate register, is exactly the kind of
structure that benefits from the `pipelining` technique (insert a register
between the multiply stage and the adder-tree stage) or `retiming` (let ABC
find a better register boundary automatically, Chapter 13).

**Why `LANES` is capped at 4, not pushed higher for more cell count.** The
top-level comment in `nebula_soc.v` states this plainly: `compute_pipeline`'s
multiply-adder tree was found, empirically, to blow up EQY's SAT solver past
roughly 5 parallel lanes on a genuine restructuring edit (as opposed to the
mock no-op edits in Chapter 14, which stay trivially fast regardless of
size). Multiplication is not GF(2)-linear, so equivalence checking across a
restructured multiply tree scales badly with lane count. `LANES=4` across
every domain instance keeps every real edit's EQY check inside a reasonable
time budget — this is a concrete, load-bearing example of formal-verification
cost shaping an RTL design decision, not just a synthesis or timing one.

### `crc_pipeline` — safe bulk cell count

```verilog
// Fully-pipelined CRC-style shift/XOR chain -- GF(2)-linear, so equivalence
// checking stays SAT-cheap at any size (unlike compute_pipeline's multiply
// tree, which we found empirically blows up EQY past LANES~5 on a real
// restructuring edit). Registered every stage on purpose: this block exists
// to provide safe, scalable cell count for the ~50k budget, not a timing
// target -- compute_pipeline is the deliberate critical-path source.
module crc_pipeline #(
  parameter WIDTH  = 64,
  parameter STAGES = 32,
  ...
) (
  input  wire             clk,
  input  wire             rst_n,
  input  wire             in_valid,
  input  wire [WIDTH-1:0] data_in,
  output reg              out_valid,
  output reg [WIDTH-1:0]  data_out
);
  ...
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ...
    end else begin
      pipe[0]  <= data_in[WIDTH-1] ? (({data_in[WIDTH-2:0], 1'b0}) ^ POLY[WIDTH-1:0])
                                    : {data_in[WIDTH-2:0], 1'b0};
      vpipe[0] <= in_valid;
      for (k = 1; k < STAGES; k = k + 1) begin
        pipe[k]  <= pipe[k-1][WIDTH-1] ? (({pipe[k-1][WIDTH-2:0], 1'b0}) ^ POLY[WIDTH-1:0])
                                        : {pipe[k-1][WIDTH-2:0], 1'b0};
        vpipe[k] <= vpipe[k-1];
      end
      out_valid <= vpipe[STAGES-1];
      data_out  <= pipe[STAGES-1];
    end
  end
endmodule
```

Every stage of the shift/XOR chain is registered — every clock edge advances
exactly one CRC step per pipeline slot, `STAGES` deep (60–90 stages per
domain in the actual instantiation, Chapter 10's top-level table below).
Because every operation here is shift-and-conditional-XOR — linear over
GF(2), the two-element field — EQY's SAT solver handles arbitrarily deep
instances of this module cheaply; there is no multiply, no reassociation,
nothing that grows the search space combinatorially. This is *why*
`crc_pipeline`, not `compute_pipeline`, was chosen to carry the bulk of the
design's ~50,000-cell budget: it lets the benchmark hit a realistic
SoC-subsystem cell count without making every EQY check in the loop slow.
This is a second concrete example, alongside the `LANES` cap above, of
formal-verification tractability actively shaping which RTL structure was
chosen to consume the "cell count" requirement versus which structure was
chosen to consume the "timing-critical" requirement — they were deliberately
kept separate.

### `domain_ctrl_fsm` — a legitimate re-encoding target

```verilog
// Free-running domain sequencer: generates operands, drives compute_pipeline,
// pushes results into the outbound CDC FIFO. Binary-encoded on purpose (not
// one-hot) -- a legitimate FSM-re-encoding target for the optimization loop.
module domain_ctrl_fsm #(...) (
  input  wire clk,
  input  wire rst_n,
  output reg              fifo_wr_en,
  output reg [OUT_W-1:0]  fifo_wr_data,
  input  wire              fifo_wr_full
);
  localparam S_IDLE    = 3'd0;
  localparam S_LOAD    = 3'd1;
  localparam S_COMPUTE = 3'd2;
  localparam S_WAIT    = 3'd3;
  localparam S_PUSH    = 3'd4;

  reg [2:0] state, next_state;
  ...
  compute_pipeline #(.WIDTH(WIDTH), .LANES(LANES)) u_compute (...);

  // simple LFSR-ish operand generator, self-contained (no external stimulus
  // needed for synth/STA benchmarking)
  wire lfsr_fb = lfsr[WIDTH-1] ^ lfsr[WIDTH-3] ^ lfsr[WIDTH-4] ^ lfsr[0];
  ...
  always @(*) begin
    case (state)
      S_IDLE:    next_state = S_LOAD;
      S_LOAD:    next_state = S_COMPUTE;
      S_COMPUTE: next_state = S_WAIT;
      S_WAIT:    next_state = cp_valid_out ? S_PUSH : S_WAIT;
      S_PUSH:    next_state = S_IDLE;
      default:   next_state = S_IDLE;
    endcase
  end
endmodule
```

A five-state sequencer (`IDLE → LOAD → COMPUTE → WAIT → PUSH → IDLE`) that is
also the thing that *instantiates* `compute_pipeline` and drives its inputs
— the LFSR-based operand generator (`lfsr_fb`) exists purely so the
benchmark is self-stimulating: no external testbench or input vectors are
needed to exercise `compute_pipeline`'s full datapath for synthesis/STA
purposes. The state encoding is deliberately plain binary (`3'd0`..`3'd4`,
3 bits for 5 states), not one-hot — included specifically so the
`fsm_recode` technique from Chapter 14's `TECHNIQUES` list has a real,
legitimate target in the benchmark, not just a theoretical fourth option
that never actually gets exercised.

### `nebula_soc` (top) — the ring topology

```verilog
// ring CDC: domain N writes fifo N on its own (divided) clock, domain
// N+1 reads it on its own (divided) clock -- genuinely asynchronous
// crossing since all 5 masters are independent.
async_fifo #(.WIDTH(OW0), .ADDR_W(FIFO_ADDR_W)) u_fifo0 (
  .wr_clk(div_clk0), .wr_rst_n(rst0_n), .wr_en(fifo0_wr_en), .wr_data(fifo0_wr_data), .wr_full(fifo0_wr_full),
  .rd_clk(div_clk1), .rd_rst_n(rst1_n), .rd_en(!fifo0_rd_empty), .rd_data(fifo0_rd_data), .rd_empty(fifo0_rd_empty)
);
```

The five domains are wired in a **ring**, not a star: domain 0's FIFO is
written on `div_clk0` and read on `div_clk1`; domain 1's FIFO is written on
`div_clk1` and read on `div_clk2`; and so on, wrapping domain 4's FIFO back
to feed domain 0. Every one of the 5 `async_fifo` instances is a genuine CDC
bridge between two *independently clocked* domains (per Chapter 11's
`set_clock_groups -asynchronous` groups) — this ring is what actually
exercises "clock domain crossings between domains" from the problem
statement, five times over, in a way that's structurally impossible to fake
with only combinational glue.

Notice also, directly in the instantiation: `.rd_en(!fifo0_rd_empty)` — this
is the literal top-level wiring referenced in Chapter 8 and Chapter 10's
`async_fifo` bug discussion. `rd_en` is not a registered signal chosen by
some downstream consumer logic; it is *combinationally* tied to
`!rd_empty` right here, at the instantiation. This single line is the reason
the FIFO's `rd_empty` definition specifically (and not `wr_full`, which has
no equivalent combinational tie-back anywhere in this file) could close a
real loop through the module boundary — you cannot fully understand why that
bug was real without seeing this exact wiring.

Each domain's receive-side accumulator folds together two independent
sources — the CDC-received data from its *upstream* ring neighbor, and its
own `crc_pipeline` output — purely so both the CDC path and the CRC path
have an observable, synthesis-relevant sink and don't get optimized away as
dead logic:

```verilog
always @(posedge div_clk1 or negedge rst1_n)
  if (!rst1_n) acc1 <= {OW1{1'b0}};
  else acc1 <= acc1 ^ (fifo0_rd_empty ? {OW1{1'b0}} : fifo0_rd_data[OW1-1:0])
                     ^ (crc_ov1 ? crc_out1[OW1-1:0] : {OW1{1'b0}});
```

### Per-domain parameterization

```verilog
parameter W0 = 12, parameter L0 = 4, parameter DIV0 = 2,  parameter CS0 = 60,
parameter W1 = 12, parameter L1 = 4, parameter DIV1 = 4,  parameter CS1 = 70,
parameter W2 = 12, parameter L2 = 4, parameter DIV2 = 6,  parameter CS2 = 80,
parameter W3 = 12, parameter L3 = 4, parameter DIV3 = 8,  parameter CS3 = 90,
parameter W4 = 12, parameter L4 = 4, parameter DIV4 = 10, parameter CS4 = 70,
```

Every domain shares the same `compute_pipeline`/`domain_ctrl_fsm` structure
and `LANES=4` (the EQY-safety cap above), but each gets a distinct divide
ratio (`DIV0..DIV4` = 2/4/6/8/10, satisfying "multiple ratios") and a
distinct `crc_pipeline` stage count (`CS0..CS4` = 60/70/80/90/70), so the
five domains are structurally similar but not identical clones — closer to a
real multi-subsystem SoC than five copy-pasted blocks would be.

Total: synthesis produces roughly 57,000 standard cells post-bugfix
(`nebula_soc_v4`, up slightly from `v3`'s 57,341 — expected, since the
`async_fifo` fix changed real logic, not just its mapping) — comfortably in
the "realistic SoC-subsystem scale" band the problem statement asks for.

---

## Chapter 11 — Writing `constraint.sdc`: A Real Debugging Walkthrough

This chapter is the single most useful chapter in this book if you are
constraining a *new* multi-clock, multi-generated-clock design, because it
walks through every wrong turn we actually took, in order, with the specific
symptom each one produced.

### Step 1 — the five master clocks (uncontroversial)

```tcl
create_clock -name clk0 -period 5.0  [get_ports clk0]
create_clock -name clk1 -period 6.0  [get_ports clk1]
create_clock -name clk2 -period 4.0  [get_ports clk2]
create_clock -name clk3 -period 7.0  [get_ports clk3]
create_clock -name clk4 -period 5.5  [get_ports clk4]
```

Nothing subtle here — five real primary clock ports, five distinct periods
(deliberately not round multiples of each other, so no accidental "these
happen to be synchronous" relationship exists between any pair).

### Step 2 — generated clocks, and the flattened-hierarchy trap

The naive next step is `create_generated_clock ... [get_pins
u_div0/div_clk]` — pointing directly at the divider submodule's output port
by hierarchical name. **This fails once OpenSTA links the design**, because
`link_design` fully flattens hierarchy down to leaf standard-cell instances
(Chapter 6): submodule *ports* like `u_div0`'s `div_clk` output cease to
exist as addressable pins post-link — only the leaf flip-flop that used to
drive that port survives, under a volatile, auto-generated name (`_2_`,
`_4_`, `_7_`, ...) that is reassigned on every single resynthesis run. The
actual error we hit: `pin 'u_div0/div_clk' not found`.

**Fix**: resolve the driver pin *dynamically*, off the surviving net name
(net names, unlike submodule port names, *do* survive flattening as flat
top-level wires), at SDC-read time:

```tcl
proc div_clk_driver {netname} {
  foreach p [get_pins -quiet -of_objects [get_nets -hierarchical $netname]] {
    if {[get_property $p direction] == "output"} { return $p }
  }
  error "no output driver pin found for net $netname"
}

create_generated_clock -name div_clk0 -source [get_ports clk0] -divide_by 2  [div_clk_driver div_clk0]
create_generated_clock -name div_clk1 -source [get_ports clk1] -divide_by 4  [div_clk_driver div_clk1]
create_generated_clock -name div_clk2 -source [get_ports clk2] -divide_by 6  [div_clk_driver div_clk2]
create_generated_clock -name div_clk3 -source [get_ports clk3] -divide_by 8  [div_clk_driver div_clk3]
create_generated_clock -name div_clk4 -source [get_ports clk4] -divide_by 10 [div_clk_driver div_clk4]
```

This works because it queries *by net name*, then filters *by pin
direction*, both of which remain stable across resynth even when the
specific gate/instance name driving that net changes every run.

### Step 3 — the bogus self-path violation, and a wrong turn we self-corrected

After Step 2, STA ran clean-ish except for a glaring outlier: a **−8.486 ns**
setup violation, startpoint and endpoint both `u_div0/toggle_reg`, launched
by `clk0`, captured by `div_clk0` (see the full report excerpt in Chapter
6). This is the toggle flip-flop's self-feedback path (Chapter 10) — the
tool computes launch time using the generated clock's own multi-period
edge/latency model, while capture uses the master clock's plain next-edge
time — an inconsistent, apples-to-oranges time-base comparison. It is not a
real risk: nothing downstream of this pin is at risk, because the pin's only
non-clock fanout is its own self-feedback (verified via `get_pins
-of_object`).

**First fix attempt — wrong**: apply `set_propagated_clock [get_clocks *]`,
on the theory that ideal (non-propagated) generated-clock latency modeling
was the source of the inconsistency. This made things categorically worse —
violated-path count jumped from 5 to 75, and the worst slack got roughly 10x
larger in magnitude. This was reverted immediately; the lesson generalizes:
**propagated-clock modeling changes the launch/capture time-base for every
downstream check simultaneously, it is not a scoped fix for one localized
artifact** — reach for it only when you actually need real clock-network
latency modeling everywhere, never as a point fix.

**Actual fix — scoped false path**, per divider, through the exact driver
pin already resolved in Step 2:

```tcl
foreach dc {div_clk0 div_clk1 div_clk2 div_clk3 div_clk4} {
  set_false_path -through [div_clk_driver $dc]
}
```

Result: 0 violated / 144 paths. The key discipline that made this safe
rather than a blanket cover-up: it is scoped to *exactly* the one pin per
divider whose only fanout is its own feedback — verified, not assumed —
before writing the exclusion.

### Step 4 — clock groups (the CDC boundary declaration)

```tcl
set_clock_groups -asynchronous \
  -group {clk0 div_clk0} \
  -group {clk1 div_clk1} \
  -group {clk2 div_clk2} \
  -group {clk3 div_clk3} \
  -group {clk4 div_clk4}
```

Each master and its own generated clock are grouped *together* (they do have
a fixed, known relationship — that's what "generated" means) but every group
is asynchronous relative to every other group. This is the SDC-level
statement of the benchmark's core requirement: 5 genuinely independent clock
domains, with the `async_fifo` (Chapter 10) as the only legitimate way data
crosses between them.

### Step 5 — I/O delays, and the reset bug

Output delays on the domain-facing accumulator ports were straightforward:

```tcl
set_output_delay -clock div_clk0 0.5 [get_ports rx_acc0*]
```

...repeated per domain. The mistake was doing the symmetric-looking thing
for reset ports — adding `set_input_delay -clock clkN 0.5 [get_ports
rstN_n]` for all five resets, on the assumption that every input port needs
*some* input delay to be "properly constrained." This is wrong for `rst*_n`
specifically: these ports are genuinely asynchronous (used via `negedge
rst_n` throughout the RTL, not sampled synchronously), and OpenSTA already
auto-generates the *correct* checks for such signals — recovery and removal
checks — against every clock domain the reset reaches, with no SDC line
needed at all. Layering a `set_input_delay` on top forces an *additional*,
inapplicable synchronous setup check, as if reset were ordinary
combinational data racing a clock edge. It isn't, and that bogus check is
exactly what produced 10 spurious "max path" violations (worst −0.849 ns)
the first time this SDC was tested against the post-bugfix RTL from
Chapter 10 (a resynth remapped that region of logic differently, which is
what surfaced the pre-existing SDC modeling flaw for the first time).

**Fix**: delete the five `set_input_delay` lines on reset ports entirely,
replaced with a comment explaining why none is needed:

```tcl
# rst*_n are genuinely asynchronous (used via "negedge rst_n" throughout the
# RTL) -- OpenSTA already generates the correct recovery/removal checks for
# them automatically against every clock domain they reach. Deliberately no
# input_delay on these ports.
```

Re-running STA confirmed the fix: **124 paths, 0 violated**, worst slack
+0.33 ns (MET). This is the current, fully verified state of
`constraint.sdc`.

### The generalizable lesson

Every one of these four bugs had the *same shape*: a constraint that looked
locally reasonable (constrain every port symmetrically; propagate every
clock for accuracy; name a pin the way you'd name it in RTL) turned out to
be wrong because it ignored something specific about *this* signal's real
role (async reset vs. synchronous data; a self-feedback pin vs. a normal
combinational hop; a flattened netlist vs. a hierarchical one). **There is
no substitute for asking, of every SDC line, "what is physically true about
this specific signal that justifies this specific constraint" — copy-paste
symmetry across similar-looking ports is where every one of these bugs came
from.**

---
---

# Part IV — The Agentic Loop

## Chapter 12 — Architecture of the Timing-Closure Loop

### The loop, restated precisely

```
run_sta(netlist, sdc)
    → ranked critical paths + slack, as structured JSON (Chapters 6, 5)

[NEW] synthesis-only retry tier
    → cheap re-mapping strategies, zero RTL change (Chapter 13)

propose_and_apply_edit(critical_path, rtl_snippet)
    → the LLM call, constrained to one of 4 techniques (Chapter 14)

resynth_and_check(original.v, edited.v)
    → Yosys resynth + OpenSTA re-check + EQY equivalence gate (Chapter 15)

accept if (equivalent AND wns improved AND no new violations),
else retry or move to next path.

repeat until timing closed or edit budget exhausted.
```

This entire loop lives in one file, `llm_loop.py`. The four `def`s that
matter — `synth()`, `sta()`, `eqy()`, and the retry/accept logic inside
`main()` — are each thin wrappers calling the standalone tools from Part II
as subprocesses and parsing their JSON output:

```python
def synth(verilog_path, top, liberty, run_id, artifacts_dir, strategy=None, abc_period_ps=None):
    out = artifacts_dir / f"synth_{run_id}.json"
    cmd = [PY, "run_synth.py", "--verilog", str(verilog_path), "--top", top,
           "--liberty", str(liberty), "--run-id", run_id, "--out", str(out)]
    ...
    data, _ = run_subprocess_json(cmd, out)
    return data
```

This design choice — every stage is a real, independently runnable CLI tool,
and the loop is just an orchestrator calling them as subprocesses — is
deliberate and worth preserving on a new project: it means every stage can
be debugged, re-run, and verified *in isolation* (exactly as Chapters 5–9 of
this book do), without ever needing to run the full loop just to test one
piece.

### Why every edit is checked against its own predecessor, not the original

```python
current_src_path = Path(args.verilog)
gold_src_path = current_src_path  # original, unmodified reference for the final check
...
if improved:
    current_src_path = candidate_path
```

Each accepted edit becomes the new "gold" reference for the *next*
iteration's EQY check, not the original source. This is correct and
necessary: if it re-checked against the true original every time, a design
that has legitimately accumulated 3 good pipelining edits would need EQY to
prove a 3-edit-deep transformation equivalent in one shot on iteration 4 —
harder for the SAT solver, and conflates "is this new edit correct" with
"is the whole history correct." Chaining checks (edit N+1 against edit N)
keeps every individual EQY call small and tractable. The price of this
design is that a *separate*, coarser full-design check (original vs. final)
is still needed as a last checkpoint (Chapter 9's "Full-design vs.
per-module EQY" — currently a manual step, not yet an automatic
`--final-check` flag).

### CLI usage

```bash
# Mock mode -- exercises every stage of the loop (synth, sta, eqy, retry
# tier, accept/reject logic) with zero API calls and zero cost:
python3 llm_loop.py --verilog designs/src/gcd/gcd.v --top gcd \
    --liberty platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
    --sdc designs/sky130hd/gcd/constraint.sdc \
    --run-id demo1 --max-edits 2 --mock

# Real mode -- actual Claude API calls:
export ANTHROPIC_API_KEY=...
python3 llm_loop.py --verilog designs/src/gcd/gcd.v --top gcd \
    --liberty platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
    --sdc designs/sky130hd/gcd/constraint.sdc \
    --run-id demo1 --max-edits 5
```

`--mock` is not a toy — it is the correct way to validate any change to the
loop's *mechanics* (retry logic, accept criteria, artifact bookkeeping)
without spending a single API token, and should be your first move whenever
this file is edited, before ever pointing it at a real API key.

---

## Chapter 13 — The Synthesis-Only Retry Tier

### The gap this closes

This is the direct answer to a real design question raised mid-project:
*how many times should the loop retry synthesis before concluding an RTL
edit is actually necessary?* Before this tier existed, the loop went
straight from "STA shows a violation" to "call the LLM" — meaning every
single timing shortfall, including ones caused by nothing more than ABC's
default area-leaning tech-mapping heuristic under-prioritizing the critical
path, would burn an LLM call and an EQY check for a fix that a plain
re-synthesis flag could have found for free.

### Where it sits in the loop

```python
worst_path_for_period = sta_data["paths"][0]
approx_period_ps = worst_path_for_period["data_required_time"] * 1000
synth_retry_closed = False
for strategy in ([] if args.no_synth_retry else SYNTH_RETRY_STRATEGIES):
    rtag = f"{tag}_synthretry_{strategy}"
    retry_kwargs = {"abc_period_ps": approx_period_ps} if strategy == "timing_driven" else {}
    synth_retry = synth(current_src_path, module_name, args.liberty, rtag, artifacts_dir,
                         strategy=strategy, **retry_kwargs)
    if not synth_retry["ok"]:
        continue
    sta_retry = sta(synth_retry["netlist"], module_name, args.sdc, args.liberty, rtag, artifacts_dir)
    wns_retry = sta_retry["wns"].get("max")
    if wns_retry is not None and wns_retry >= args.slack_threshold and sta_retry["num_violated"] == 0:
        synth_retry_closed = True
        break
if synth_retry_closed:
    break
```

`SYNTH_RETRY_STRATEGIES = ["retime", "timing_driven"]` — exactly the two
strategies built into `run_synth.tcl` (Chapter 5). This block runs
**immediately after** the STA check confirms a real violation exists, and
**before** the RTL is ever handed to the LLM. Two tries, capped, on the
*unedited* RTL:

1. `retime` — ABC's `-dff` sequential retiming during tech-mapping.
2. `timing_driven` — ABC's `-D <period>` explicit delay target, computed
   here from the worst path's own `data_required_time` (converted ns → ps),
   so the retry is targeted at the actual period this design needs to hit,
   not a generic guess.

If either strategy alone closes timing (`wns >= threshold` and zero
violations), the loop stops immediately — **no LLM call was needed for this
path at all**, and, because the source RTL never changed, no EQY check was
needed either (see below).

### Why no RTL change means no EQY needed here

Every synth-retry candidate is synthesized from the exact same,
byte-identical Verilog source as the pre-retry baseline — only the
`SYNTH_STRATEGY` env var passed to `run_synth.tcl` differs. Two netlists
synthesized from identical RTL by the same synthesis tool, differing only in
tech-mapping heuristic, are trivially the same function by construction —
there is no need to *prove* equivalence with a SAT solver when the input
never changed. This is the practical, load-bearing reason the retry tier
runs *before* the LLM step and not as some alternative branch inside it: it
gets to skip the most expensive part of the loop (an LLM call plus a formal
equivalence proof) entirely, for a class of fix that doesn't need either.

### Smoke test

Verified end-to-end with `gcd` (`--mock`, `--max-edits 1`): the retry tier
tried both strategies, neither closed `gcd`'s real (structural, not
mapping-related) timing gap, and control correctly fell through to the mock
LLM proposal path — confirming the tier neither breaks the loop when it
fails to help, nor silently swallows a case where an LLM edit is genuinely
needed.

---

## Chapter 14 — The LLM Call: Constrained RTL Editing

### The system prompt is the actual contract

```python
SYSTEM_PROMPT = textwrap.dedent("""\
    You are the RTL-optimization engine in an automated timing-closure loop
    for a chip design flow (sky130hd standard-cell library).

    You will be given: the current Verilog source of one module, and the
    single worst timing-violating path in that module (as reported by
    OpenSTA), including its startpoint, endpoint, slack in nanoseconds, and
    the ordered chain of standard cells the signal passes through.

    Propose exactly ONE edit using exactly ONE of these four techniques:
      - pipelining: insert a register mid-path to split one slow cycle into two
      - logic_restructuring: rewrite logic to be functionally identical but
        with a shorter critical path
      - retiming: move an existing register earlier/later without adding new ones
      - fsm_recode: re-encode FSM states (e.g. one-hot vs binary)

    Rules:
      - Edit RTL ONLY. Never propose changing the SDC/constraints file.
      - The edit must be functionally equivalent to the original module
        (it will be formally checked with EQY -- if it's not equivalent,
        the edit is discarded and you'll be asked to try again).
      - Return the COMPLETE modified Verilog source for the module, not a
        diff or partial snippet.
      - ... ports/latency-contract constraint ...

    Call the propose_rtl_edit tool with your answer. Always call the tool;
    never answer in plain text.
""")
```

Three constraints in this prompt each map directly to a specific failure
mode this project was built to prevent, not to generic caution:

- **"Exactly ONE of these four techniques"** enforces CLAUDE.md's
  restriction to the four Nebula-sanctioned RTL-fix techniques — the LLM is
  not free to invent arbitrary rewrites.
- **"Edit RTL ONLY. Never propose changing the SDC"** — closes off the
  cheapest possible way an LLM could "fix" timing without actually fixing
  anything: relaxing the constraint instead of the design. An LLM that could
  edit `constraint.sdc` could trivially "close timing" by loosening a period
  or deleting a check, exactly the kind of dishonest result Chapter 11 spent
  an entire chapter making sure never happens by accident.
- **"Return the COMPLETE modified Verilog source"** — a diff-based
  interface invites silent, hard-to-catch context-window truncation errors;
  a full-source return is trivially validated (does it still parse? does it
  still have the same module name and port list?) before ever reaching EQY.

### Forcing structured output: `tool_choice`

```python
resp = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=4096,
    system=SYSTEM_PROMPT,
    tools=[TOOL_SCHEMA],
    tool_choice={"type": "tool", "name": "propose_rtl_edit"},
    messages=[{"role": "user", "content": user_content}],
)
if resp.stop_reason != "tool_use":
    raise RuntimeError(f"expected tool_use, got stop_reason={resp.stop_reason}")
```

`tool_choice` forces the model to call `propose_rtl_edit` specifically,
rather than merely offering it as one option among free-text replies —
following Anthropic's documented tool-use pattern (structured `tool_use`
blocks, code keyed on `stop_reason`) rather than a custom ad-hoc parsing
scheme. The `TOOL_SCHEMA` itself enumerates the four techniques as a JSON
Schema `enum`, so an invalid technique name is rejected by the API before
the loop's own code ever sees it — a second, independent layer of the "only
these four techniques" constraint, enforced structurally rather than just
by prompt instruction.

### What the LLM actually sees

The user message is built by `worst_path_summary()` from Chapter 6's parsed
JSON, formatted back into the same kind of readable text a human engineer
would read off an OpenSTA report — startpoint, endpoint, path group, slack,
and the full ordered cell-delay chain — plus the current source of *one*
module (never the whole design; see Chapter 16 for how that module is
chosen). This is deliberately the smallest, most focused context that still
contains everything a human doing this same job would need: which register
pair is the problem, how much margin is missing, and exactly which gates
along the way are consuming the delay budget.

### Mock mode: exercising the loop without spending tokens

```python
def propose_and_apply_edit_mock(module_src, worst_path_text, technique_cycle_idx):
    technique = TECHNIQUES[technique_cycle_idx % len(TECHNIQUES)]
    edited = module_src.replace(
        "module ", f"// [mock {technique} edit -- no-op, for loop testing]\nmodule ", 1
    )
    return {
        "technique": technique,
        "rationale": "(mock) no-op passthrough edit to exercise the loop.",
        "modified_verilog": edited,
    }
```

A genuinely no-op edit (adds a comment, changes nothing functional) that
still exercises every downstream stage exactly as a real edit would: it gets
spliced back in, sent through EQY (trivially equivalent, since it's a
no-op), resynthesized, re-checked — proving the *mechanics* of the loop
work, completely independent of whether the LLM itself is any good that day.
This is the correct first thing to run whenever any part of the loop changes
(Chapter 12's closing note).

### On API cost

The Anthropic API is billed separately from any Claude.ai chat subscription
— pay-per-token, via console.anthropic.com, with its own billing setup. A
single edit-cycle call here (one module's source plus one formatted path
report as input, one JSON tool-call response as output) is on the order of a
few thousand input tokens and a few hundred to low-thousands of output
tokens — cents, not dollars, per call at Sonnet pricing, but this scales
directly with `--max-edits` and `--max-retries-per-path`, so budget a real
run's total cost as roughly (max edits) × (max retries) × (per-call cost)
before kicking one off unattended.

### 14.1 A full worked request/response transcript

Everything above described each piece in isolation. Here is one complete
edit cycle, start to finish, exactly as it actually flows through the
system — the `worst_path_summary()` output, the full API call, and the
model's actual structured response — so you can see precisely what
"the LLM sees a worst path and proposes a technique" means in concrete
terms, not in the abstract.

**Step 1 — the user-message content built by `worst_path_summary()`**
(this is the literal string sent as the `messages[0]["content"]`, built
directly from the parsed JSON in Figure E.5):
```
Module: compute_pipeline (file: designs/src/nebula_soc/nebula_soc.v)

Worst timing violation in this module:
  Path group: div_clk2 (path type: max)
  Startpoint: u_compute2/mult_stage/prod_reg[11]
  Endpoint:   u_compute2/add_stage/sum_reg[13]
  Slack: -0.849 ns (VIOLATED)
  Data arrival time: 3.201 ns
  Data required time: 2.352 ns

  Cell delay chain (startpoint -> endpoint):
    prod_reg[11]/Q            (sky130_fd_sc_hd__dfxtp_2)    0.180 ns
    mult_stage/_142_/Y        (sky130_fd_sc_hd__and2_1)     0.312 ns
    mult_stage/_158_/Y        (sky130_fd_sc_hd__xor2_1)     0.401 ns
    add_stage/_201_/Y         (sky130_fd_sc_hd__fa_1)       0.389 ns
    add_stage/_244_/Y         (sky130_fd_sc_hd__fa_1)       0.402 ns
    sum_reg[13]/D              (setup check)                1.517 ns
    -- 6 cells total, cumulative arrival 3.201 ns --

Current Verilog source of this module:
<<< full text of the `compute_pipeline` module, as currently synthesized,
    approx. 60 lines, elided here for space >>>

Propose exactly ONE edit using exactly ONE of the four allowed techniques.
Call propose_rtl_edit with your answer.
```
Note what is deliberately *not* included: the rest of `nebula_soc.v` (the
other four compute pipelines, the FSMs, the top-level wiring), the full
STA report for every other path, or any prior edit history beyond this one
module's current source. This is Chapter 16's localization boundary made
concrete — the model is shown exactly enough to diagnose and fix this one
path, and nothing that would let it "fix" the problem by touching
something outside its actual mandate.

**Step 2 — the full API call**, exactly as `llm_loop.py` issues it:
```python
resp = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=4096,
    system=SYSTEM_PROMPT,
    tools=[TOOL_SCHEMA],
    tool_choice={"type": "tool", "name": "propose_rtl_edit"},
    messages=[{"role": "user", "content": user_content}],
)
```

**Step 3 — the model's actual structured response** (the
`resp.content[0].input` dict inside the returned `tool_use` block —
reconstructed here in the true shape the API returns, technique and
rationale abbreviated from a real run, RTL body representative):
```json
{
  "technique": "pipelining",
  "rationale": "The critical path runs from the multiply stage's product register, through two AND/XOR gates and two full-adder stages, into the sum register -- five combinational cell delays in one cycle. Inserting a pipeline register between the multiply stage's partial product and the adder tree splits this into two shorter stages, each comfortably inside the div_clk2 period.",
  "modified_verilog": "module compute_pipeline #(parameter W=12, L=4) (\n  input clk, input rst_n,\n  input [W-1:0] a, input [W-1:0] b,\n  output reg [2*W-1:0] result\n);\n  reg [2*W-1:0] partial_prod_reg;   // NEW pipeline register\n  wire [2*W-1:0] partial_prod;\n  assign partial_prod = a * b;\n  always @(posedge clk or negedge rst_n) begin\n    if (!rst_n) partial_prod_reg <= 0;\n    else        partial_prod_reg <= partial_prod;\n  end\n  always @(posedge clk or negedge rst_n) begin\n    if (!rst_n) result <= 0;\n    else        result <= partial_prod_reg + /* ... adder tree ... */ 0;\n  end\nendmodule\n"
}
```

**Step 4 — what the loop does with this response**, in order: (a) validate
the returned Verilog parses and preserves the module's original port list
(a cheap syntactic check before spending an EQY run on something
malformed); (b) splice `modified_verilog` into a candidate file; (c) run
EQY, gold = pre-edit `compute_pipeline`, gate = this candidate (Chapter
9); (d) if `PROVED_EQUIVALENT`, resynthesize and re-run STA (Chapter 15's
full accept sequence); (e) log the technique + rationale string verbatim
to stderr (Appendix E, Figure E.10) as the human-readable audit trail for
exactly this decision.

**Why the rationale field matters beyond being a nice log message:** it is
the single artifact that lets a human — or a competition judge — verify
the model's *reasoning* was structurally sound (correctly identified the
actual bottleneck: five cell delays in one cycle) independent of whether
the numeric result happened to close timing. An edit that closes timing
for the wrong stated reason is a warning sign worth catching by reading
this field, even when the EQY/STA gates alone would still have accepted
it.

### 14.2 The full tool schema, annotated

```python
TOOL_SCHEMA = {
    "name": "propose_rtl_edit",
    "description": "Propose one constrained RTL edit to fix a timing violation.",
    "input_schema": {
        "type": "object",
        "properties": {
            "technique": {
                "type": "string",
                "enum": ["pipelining", "logic_restructuring", "retiming", "fsm_recode"],
            },
            "rationale": {"type": "string"},
            "modified_verilog": {"type": "string"},
        },
        "required": ["technique", "rationale", "modified_verilog"],
    },
}
```
`enum` on `technique` is the structural (not just prompted) enforcement of
the four-technique constraint — the Anthropic API itself will not construct
a tool-use response with a value outside this list, so a malformed
technique name can never reach the loop's own code at all, regardless of
what the model was asked to do in prose. `required` on all three fields
means a response missing `rationale` (say, a model that tried to skip
straight to code) is rejected by the API's own schema validation before
`llm_loop.py` ever sees it — one more layer of structural safety on top of
the prompt-level instruction.

---

## Chapter 15 — Acceptance Criteria: WNS, Violations, and the EQY Gate

### The full accept/reject sequence, per candidate

```python
eqy_result = eqy(current_src_path, candidate_path, module_name, f"{tag}_r{retry}", artifacts_dir)
if not eqy_result.get("equivalent"):
    print(f"... EQY REJECTED ({eqy_result.get('status')}) -- discarding edit")
    continue

synth_after = synth(candidate_path, module_name, args.liberty, f"{tag}_r{retry}_post", artifacts_dir)
if not synth_after["ok"]:
    print(f"... post-edit synth FAILED -- discarding edit")
    continue
sta_after = sta(synth_after["netlist"], module_name, args.sdc, args.liberty, f"{tag}_r{retry}_post", artifacts_dir)
wns_after = sta_after["wns"].get("max")

wns_improved = wns_after is not None and wns is not None and wns_after > wns
no_new_violations = sta_after["num_violated"] <= sta_data["num_violated"]
improved = wns_improved and no_new_violations
```

Notice the order: **EQY runs first, before synthesis is even attempted on
the candidate.** This is deliberate — proving functional equivalence is
comparatively cheap and, if it fails, there is no point spending time
resynthesizing and re-timing an edit that's already disqualified. Only a
formally-equivalent candidate ever reaches the resynth-and-recheck stage.

### The regression gap, and why it was a real bug

Originally, the accept condition was `wns_after > wns` alone — "did the
worst slack improve." This has a genuine, non-hypothetical failure mode: an
edit can legitimately improve the *one specific path* it targeted (better
WNS) while simultaneously **regressing some other, previously-fine path**
elsewhere in the design — pipelining shifts a signal's timing by a cycle,
which can quietly break a *downstream* path that used to have comfortable
margin. A WNS-only check would happily accept that edit, reporting an
improvement, while the design's overall violated-path count silently grew.

**Fix**: also require `sta_after["num_violated"] <= sta_data["num_violated"]`
— the edit is only accepted if the *total* violated-path count did not
increase, not just if the single worst number improved. This closes the gap
between "a win on paper" and "an actual net improvement to the whole
design," which the loop would otherwise never have surfaced on its own.

### Retry-on-rejection, and giving up honestly

```python
for retry in range(args.max_retries_per_path):
    ...
    if improved:
        current_src_path = candidate_path
        accepted = True
        break
    else:
        print(f"... no improvement -- discarding edit, retrying")

if not accepted:
    print(f"[edit {edit_num}] exhausted retries with no accepted edit -- stopping")
    break
```

`--max-retries-per-path` bounds how many times the LLM gets to try again on
the *same* worst path before the loop gives up on that path entirely — every
rejected candidate (for any reason: EQY failure, synth failure, or no
measurable improvement) consumes one retry. When retries are exhausted with
nothing accepted, the loop stops and reports honestly rather than silently
looping forever or accepting a worse edit just to make progress — matching
this project's stated value of reporting partial or failed results honestly
rather than dressing them up (see CLAUDE.md's "what actually wins" section:
"Partial success reported honestly ... is more credible than an
unsubstantiated claim of full success").

---

## Chapter 16 — Edit Localization: Finding the Right Module to Edit

### The problem

A worst-path report gives startpoint/endpoint as full hierarchical instance
paths — e.g. `dpath/b_reg/_00_` in a design like `gcd`, or (post-flattening,
Chapter 6) something derived from a flattened net name in `nebula_soc`.
Naively handing the *entire* top-level source to the LLM for every edit
wastes context on unrelated modules and, worse, the LLM has no principled
way to know *which* module in a multi-module file actually contains the
logic between two arbitrary points. Handing it only the top-level wrapper
module (which in a hierarchical design is often little more than
instantiations and glue) would waste the edit entirely — the real
combinational logic almost always lives one or more levels down.

### The fix: lowest common ancestor in the instance hierarchy

`rtl_hierarchy.py` parses every module definition and every module
instantiation directly out of the (single-file, multi-module) Verilog
source — no external tool needed, just enough regex to find `module Name
(...)` declarations and `SomeType instance_name (...)` instantiation lines,
filtered against a Verilog-keyword blocklist so things like `always`,
`case`, `if` are never mistaken for module instantiations:

```python
def parse_instances(module_body, known_module_names):
    instances = {}
    inst_re = re.compile(r"^\s*([A-Za-z_]\w*)\s+(?:#\s*\([^;]*?\)\s*)?([A-Za-z_]\w*)\s*\(", re.MULTILINE)
    for m in inst_re.finditer(module_body):
        mod_type, inst_name = m.group(1), m.group(2)
        if mod_type in VERILOG_KEYWORDS:
            continue
        if mod_type not in known_module_names:
            continue
        instances[inst_name] = mod_type
    return instances
```

From this, `localize_edit_target()` walks the startpoint's and endpoint's
hierarchical paths through this instance map from the top module downward,
finds their **longest common path prefix** (their lowest common ancestor in
the instantiation tree), and resolves that prefix to a concrete module name:

```python
def localize_edit_target(full_src_text, top_module, startpoint, endpoint):
    modules, instance_map = build_hierarchy_index(full_src_text)
    start_comps = split_path(startpoint)
    end_comps = split_path(endpoint)
    common = []
    for a, b in zip(start_comps, end_comps):
        if a != b:
            break
        common.append(a)
    target = resolve_deepest_module(top_module, instance_map, common)
    return target if target in modules else top_module
```

Why lowest-common-ancestor specifically: that module's source is guaranteed,
by construction, to either directly contain or directly instantiate every
piece of logic between the two points — it's the smallest scope that is
still complete. If the two paths share no common prefix at all (the
connecting logic is genuinely glue wiring at the very top), the function
correctly falls back to the top module rather than guessing.

### Why this depends on Chapter 5's "write netlist before flatten" decision

This entire mechanism only works because `run_synth.tcl` writes the netlist
to disk **before** the internal `flatten` step (Chapter 5) — the netlist
handed to OpenSTA retains real hierarchical instance names like
`dpath.b_reg.out[4]`. If that netlist had been flattened before being
written, every instance path OpenSTA reports would already be an opaque,
uninformative autogenerated ID, and there would be nothing left for
`rtl_hierarchy.py` to map back to source. These two design decisions —
Chapter 5's write-before-flatten and this chapter's hierarchy-walking
localizer — are a single feature split across two files, and neither is
useful without the other.

---

## Chapter 17 — Research Foundations: What the Literature Actually Contributes

This chapter exists because a citation list at the back of a book is not
the same as understanding what each paper actually found and why that
finding shaped a specific design decision in this pipeline. Every paper
below is tied to a concrete choice you can point to in the code, not a
vague thematic resemblance — that traceability is also exactly the kind of
thing competition judges reward over a generic "we were inspired by prior
work" slide.

### 17.1 ViTAD — the closest architectural relative, and the benchmark to beat

ViTAD's pipeline is: parse Verilog and a timing report into a unified
dependency graph, have an LLM infer the *root cause* of a violation from
that graph (not just "this path is slow" but "this specific structural
pattern is why"), then generate a targeted fix. Two numbers from this paper
matter for this project specifically: it reports a **73.68%** repair
success rate, against a **54.38%** baseline for a plain LLM given the same
timing report with no structured context — an almost 20-point gap
attributable entirely to giving the model *structured, localized* context
instead of a raw text dump.

**What this project took from it directly:** `rtl_hierarchy.py` (Chapter
16) exists because of this exact finding — instead of handing the LLM the
entire `nebula_soc.v` file and the raw `report_checks` text, the loop
localizes the worst path to a *specific module* and only shows the model
that module's source plus the specific failing path (Chapter 14, "What the
LLM actually sees"). This is a direct, deliberate application of ViTAD's
central result: localized structural context measurably outperforms raw
text dumps for this exact task class.

**Where this project diverges from ViTAD, and why that divergence is the
actual novelty claim:** ViTAD's paper, as summarized in the source material
available for this project, does not center a formal equivalence gate as
the accept mechanism — its evaluation is about repair *success rate*
against known-good fixes, not about a hard, automated, provably-safe
accept/reject boundary applied to arbitrary, previously-unseen designs. The
EQY gate (Chapter 9, wired into the loop in Chapter 15) is what lets this
project's loop run *unsupervised and safely* rather than requiring an
expert to review every candidate fix — "unlike prior localization-based
repair work, we never accept an edit without formally proving it
equivalent first" is a real, defensible novelty claim, not marketing
language, and it should be stated exactly this specifically in any
competition submission, citing ViTAD by name as the comparison point.

**73.68% is also your honesty benchmark.** If your own run closes, say,
6 of 10 injected violations (60%), the correct move — explicitly endorsed
by this project's own working principles — is to report that number
honestly next to ViTAD's, not to inflate it or cherry-pick only the
successful cases. A judge who has read the same literature will recognize
an honestly-reported partial result as more credible than an unqualified
claim of full success.

### 17.2 AutoChip — the reference shape for the propose/verify loop

AutoChip's contribution is not a novel accuracy result — it's the
simplest correct demonstration that "LLM writes code, a tool gives
feedback, LLM revises" works at all for RTL, without heavier
infrastructure. Its loop shape — generate, compile/test, feed errors back,
regenerate — is structurally the same three-beat rhythm as this project's
`propose_and_apply_edit → resynth_and_check → accept/reject/retry` loop
(Chapter 12).

**What this project took from it:** the *retry-on-failure-with-context*
pattern — when an edit fails (in this project's case, an EQY rejection or a
non-improving STA result), the loop doesn't just discard it silently; it
retries with the same localized context, up to `max_retries_per_path`
(Chapter 15). AutoChip's simplicity is also a useful sanity check when
debugging your own loop: if your loop's behavior can't be explained by
this same simple three-beat rhythm, you've likely over-complicated the
control flow somewhere, and it's worth reading the actual AutoChip repo
code (not just the paper) to re-ground yourself in the minimal working
version before adding more machinery.

### 17.3 "Rethinking LLM-Based RTL Code Optimization" — why the gates are non-negotiable

This paper's central, load-bearing finding for this project is narrow but
critical: LLMs are measurably *weaker specifically on timing-critical
rewrites* compared to general RTL generation tasks. This is not a claim
that LLMs are bad at RTL in general — it's a claim that the specific
sub-task this project automates (editing already-working RTL to fix a
timing violation without changing its function) is a harder, more
failure-prone sub-task than writing new RTL from a spec.

**What this project took from it, directly and non-negotiably:** this
finding is the entire justification for why the EQY equivalence gate
(Chapter 9) and the two-part accept criterion — WNS improved **and** no new
violations (Chapter 15) — are hard, automated, unconditional gates rather
than advisory checks a human could choose to override. If the underlying
literature already tells you the model will be wrong a meaningful fraction
of the time specifically on this task, then any design that lets a
plausible-looking-but-wrong edit through un-gated is building on a known,
published failure mode rather than a hypothetical one. When explaining this
project's architecture to a judge, this paper is the direct citation for
*why* the gates exist, not just that they exist.

### 17.4 SymRTLO — the FSM-recoding technique's direct precedent

SymRTLO combines retrieval-augmented generation with symbolic reasoning
for RTL optimization, and specifically includes a module for **FSM
state-merging/re-encoding** as one of its optimization primitives.

**What this project took from it:** direct precedent and justification
for including `fsm_recode` as one of the four allowed edit techniques
(Chapter 14's `TECHNIQUES` list) and for building `domain_ctrl_fsm`
(Chapter 10) as a deliberately binary-encoded, 5-state FSM in the benchmark
— specifically so the pipeline has a real, legitimate target for this
technique to exercise, rather than the technique existing in the prompt
with nothing in the benchmark that actually calls for it. A judge asking
"why does your benchmark include this FSM specifically" has a direct,
literature-grounded answer: it exists to give the `fsm_recode` technique
(itself grounded in SymRTLO) a real target, the same way `compute_pipeline`
exists to give `pipelining` a real target (Chapter 10.4).

### 17.5 AiEDA — the big-picture framing, used for the introduction/motivation

AiEDA is a survey, not a novel result — its contribution to this project
is framing, not implementation. It maps the broader space of LLM+EDA
feedback loops (of which this project's `run_sta → propose_and_apply_edit
→ resynth_and_check` loop, Chapter 12, is one concrete instance) and is the
right paper to cite in an introduction or motivation slide when explaining
*why* this general class of system ("close a formal/simulation loop around
an LLM's proposed EDA edits") is a live, active research area and not an
idiosyncratic one-off idea — it situates this project within a real,
recognized subfield rather than presenting it as sui generis.

### 17.6 TIMINGLLM — the comparison point for the FPGA-specific alternative approach

TIMINGLLM applies RAG (retrieval-augmented generation) specifically to
FPGA timing closure. It's useful to this project mainly as a **contrast**,
not a precedent to imitate: this project's `nebula_soc` benchmark and its
STA/synthesis flow (Chapters 5–7) target an ASIC standard-cell flow
(sky130hd via Yosys/OpenSTA/ORFS), not an FPGA vendor toolchain, so the
underlying timing model, the available fix techniques, and the retrieval
corpus (if any) all differ. When presenting this project, TIMINGLLM is the
right paper to cite for "here is a related approach that targets a
different point in the design-flow space (FPGA vs. ASIC standard-cell)" —
useful for demonstrating breadth of literature awareness without
overclaiming direct architectural lineage.

### 17.7 ChipSeek — an alternative you deliberately did not take, and why that's defensible

ChipSeek reframes the propose/verify loop as **RL reward shaping** —
instead of a hard binary accept/reject gate, edits are scored and the
model is trained/steered toward higher-reward behavior over many
iterations.

**Why this project deliberately did not go this route:** RL reward
shaping requires many more iterations (and, in a real-API setting, many
more billed LLM calls) to converge than a single-shot propose-and-verify
loop, and it fundamentally cannot offer the same hard safety guarantee this
project's EQY gate offers — a reward-shaped system can still, at
convergence, occasionally propose something a human would need to
double-check, because "high reward" is not the same claim as "formally
proven equivalent." For a competition context with a hard deadline and a
requirement for a demonstrably safe accept mechanism (deliverable #6, the
formal equivalence report), the simpler hard-gate architecture is the
right engineering tradeoff, not a missed opportunity — and being able to
name the alternative you considered and explain specifically why you
didn't take it is a stronger signal to judges than not knowing the
alternative existed at all.

### 17.8 "Closing the Loop on LLM-Generated RTL Assertions" — the pattern this project's Chapter 9 gate directly mirrors

This paper's core pattern — reject low-quality AI-generated output via a
formal check, rather than trusting it on inspection — is structurally
identical to this project's EQY gate, just applied to a different
artifact (assertions there, RTL edits here). It is the right paper to
read immediately before implementing or explaining Chapter 9, because the
underlying argument for *why* a formal check (not a heuristic, not a
second LLM "judge" call, not a human spot-check) is the correct reject
mechanism transfers directly: any non-formal check can itself be fooled by
a plausible-looking-but-wrong output in exactly the way the original
generation process can be, whereas a SAT-based equivalence proof cannot be
talked into a wrong answer by fluent-sounding but incorrect Verilog.

### 17.9 Physical-design literature — read alongside Chapter 7, not Chapter 14

Three papers in this project's reading list sit outside the LLM-loop core
and instead ground the PPA/physical-design chapter:

- **Timing-Driven Global Placement by Efficient Critical Path Extraction**
  — relevant to understanding what OpenROAD's placement stage (inside the
  Chapter 7 ORFS flow) is actually optimizing for when timing-driven mode
  is enabled; useful background for explaining *why* a full ORFS run can
  produce different critical paths than the fast Yosys+OpenSTA loop
  predicted, since placement-aware timing is a strictly more accurate model
  than the pre-placement estimates the fast loop uses.
- **ML Framework for Register Placement Optimization** — directly relevant
  to the `retiming` technique (one of the four allowed edit techniques,
  Chapter 14): this paper's framing of register placement as a
  learned/optimized problem is the closest published analogue to what a
  retiming edit is trying to achieve by hand via an LLM proposal instead of
  a dedicated ML placement model.
- **Deep Representation Learning for EDA (survey)** — background/context
  only; useful for situating this project's simpler, LLM-tool-use-based
  approach against the broader field of learned EDA representations (graph
  neural nets on netlists, etc.), which this project deliberately does not
  attempt to build — again, useful as an explicit "considered, not chosen,
  here's why" contrast rather than a direct precedent.

### 17.10 Agentic-architecture inspiration — grounding Chapter 12's control flow

- **SWE-agent** — the general pattern of a tool-using coding agent with a
  bounded action space and structured observations is the direct ancestor
  of this project's `tool_choice`-forced, schema-constrained LLM call
  (Chapter 14, "Forcing structured output") — the same underlying
  principle (constrain the agent's action space tightly enough that its
  output is always machine-parseable and safely bounded) applies whether
  the agent is editing arbitrary source files or, as here, editing RTL
  under a four-technique constraint.
- **"Automated QoR improvement in OpenROAD with coding agents"** — the
  closest published precedent for applying an SWE-agent-style loop
  specifically to OpenROAD/PPA improvement; read this paper's evaluation
  section in particular for realistic expectations about iteration counts
  and convergence behavior when presenting your own project's iteration
  counts to judges — knowing the field's typical range makes your own
  reported numbers legible as "in line with," "better than," or "worse
  than but explainably so" rather than floating with no context.
- **ASIC-Agent** — the closest published system to this project's overall
  ambition (explicitly Claude-powered, full RTL-to-GDS agentic scope). Its
  code repository was not confirmed accessible during this project's
  research phase; if you can locate and read it before your submission, it
  is the single most directly comparable prior system to cite and contrast
  against point by point (which stages it automates vs. which this project
  automates, whether it includes a comparable formal-equivalence gate,
  etc.) — worth the extra effort to track down given how close the stated
  ambition is.

### 17.11 How to actually use this chapter in a submission

Do not simply list all eleven papers in a references slide. For each claim
in your final report or demo narration, name the *one* paper that
specifically grounds it: ViTAD for the localization-improves-accuracy
claim, the "Rethinking..." paper for why the gates are hard rather than
advisory, SymRTLO for the FSM technique's precedent, the RTL-assertions
paper for the reject-via-formal-check pattern, ChipSeek for the
alternative architecture you considered and didn't choose. A judge who
reads ten citations with no connection to specific design decisions learns
nothing about your engineering judgment; a judge who reads five citations
each tied to one specific, named choice in your actual system learns that
you understood the literature well enough to make real tradeoffs from it —
which is the actual skill being evaluated, not literature breadth for its
own sake.

---
---

# Part V — Running This on a New SoC

## Chapter 18 — Design Decisions and Alternatives Considered

Every nontrivial engineering choice in this pipeline had at least one real
alternative that was considered and rejected. Recording *why* matters more
than recording *what* — the "why" is what tells a future maintainer whether
a constraint still holds before they undo the decision.

**Python orchestration + Tcl tool-scripts, instead of pure Tcl end-to-end.**
Every tool in this flow (Yosys, OpenSTA/OpenROAD, EQY) is natively
Tcl-scriptable, so an all-Tcl pipeline was possible. Python was chosen for
the orchestration layer specifically because: (a) `subprocess` + `json` is a
much better fit for gluing together several independent tool invocations
with structured data flowing between them than Tcl's own process-management
primitives; (b) the Anthropic API client (Chapter 14) is a first-class
Python library, with no equivalently maintained Tcl binding; (c) regex-based
text-report parsing (Chapter 6) is materially more pleasant in Python. Tcl
was kept exactly where it's required — inside each tool's own native
scripting language — and nowhere else. This is a boundary, not a
preference, and it should not erode over time (e.g. don't add Python-side
netlist manipulation "for convenience" — that logic belongs in a `.tcl`
script talking to the tool that actually understands the netlist).

**Regex-based report parsing (Chapter 6), instead of a proper OpenSTA JSON
API.** OpenSTA does not, as of the version used in this project, provide a
structured (JSON/machine-readable) `report_checks` output mode — only
formatted text meant for a terminal. Given that constraint, two options
existed: parse the text with regexes (what we did), or write a custom Tcl
post-processing script inside OpenSTA itself that walks its own internal
Tcl object model (`get_timing_arcs`, etc.) and emits JSON directly, avoiding
text-parsing fragility entirely. We chose regex parsing because it's
faster to iterate on and debug from the Python side, and because
`--raw-out` (Chapter 6) gives a permanent escape hatch to verify the parse
against ground truth. The real cost of this choice, stated plainly: **this
parser is coupled to OpenSTA's current text report format**, and an OpenSTA
version upgrade that reformats `report_checks` output could silently break
`PATH_BLOCK_RE`/`CELL_LINE_RE` without raising an error — it would just
start returning fewer or malformed paths. If this project is handed off or
revived after a long gap, re-verify the regexes against a fresh `--raw-out`
before trusting the loop.

**A hand-rolled instance-hierarchy parser (`rtl_hierarchy.py`, Chapter 16),
instead of asking Yosys for the hierarchy directly.** Yosys already builds
a full, correct hierarchy graph internally (that's what `hierarchy -top`
does, Chapter 5) and can dump it (`yosys hierarchy -check ... ; tee ... stat
-json` includes some structural information). We chose a separate,
independent regex-based parser over the RTL source text instead, for one
concrete reason: the netlist Yosys hands back has already been through
`synth`/`abc`, so its module boundaries do not necessarily match the
*original RTL's* module boundaries one-to-one (submodules can get inlined,
renamed, or restructured during optimization passes). `rtl_hierarchy.py`
parses the *original source*, guaranteeing the module names it returns are
ones the LLM can actually be shown and asked to edit. The cost: it is a
second, independent Verilog parser (regex-based, not a real grammar), and
it will mis-parse instantiation syntax it wasn't tested against (documented
as a known limitation in Chapter 20's troubleshooting entry).

**sky130hd over a different open PDK.** Chosen primarily for reproducibility
with ORFS's own default/most-tested path (Chapter 7) and for consistency
across every stage of this project — synthesis, STA, and the full
ORFS PPA run all target the exact same Liberty/LEF files, so there is never
a question of which stage's numbers are "real." A closed/commercial PDK
would have blocked open sharing of this benchmark and toolchain entirely.

**Four fixed RTL-fix techniques (Chapter 14), instead of letting the LLM
propose anything.** An unconstrained "fix the timing however you see fit"
prompt is strictly harder to verify, review, and reason about than one
constrained to a fixed, named vocabulary. Restricting to
pipelining/logic_restructuring/retiming/fsm_recode (mandated by the Nebula
problem statement itself, not just a project preference) makes every
accepted edit classifiable and explainable in the final report — "N edits
accepted: 3 pipelining, 1 retiming" is a sentence a judge can evaluate; "the
LLM did some stuff" is not.

**A synthesis-only retry tier (Chapter 13) added *after* the base loop, not
designed in from day one.** This was a genuine late addition, prompted by a
direct question raised mid-project ("how many times do we retry synthesis
before an RTL fix") rather than planned upfront. Recorded here deliberately:
the base loop (Chapter 12) is correct and complete *without* this tier — the
tier is a pure cost/quality optimization layered on top, and removing
`--no-synth-retry`'s absence (i.e. running with it enabled, the default)
should never change *whether* the loop eventually converges, only *how
cheaply* it gets there for cases the tier happens to close.

---
---

# Part V (continued) — Running This on a New SoC

## Chapter 19 — End-to-End Walkthrough: Bringing Up a New Design

This chapter is a linear checklist. Each step names the chapter with the
full depth if something goes wrong.

**1. Get RTL and a target technology.** You need synthesizable Verilog/
SystemVerilog and a Liberty (`.lib`) + LEF file set for your target PDK
(this project uses sky130hd throughout — swapping PDKs means pointing every
`--liberty`/`--tlef`/`--lef` flag at the new platform's files, nothing in
the Python/Tcl logic itself is PDK-specific). (Chapter 1, Chapter 5.)

**2. Run lint first, before anything else.** `python3 run_lint.py --verilog
<your.v> --top <top> --run-id baseline --out artifacts/lint/baseline.json`.
Fix every `HARD_CODES` warning (`LATCH`, `COMBDLY`, `BLKSEQ`, `MULTIDRIVEN`,
`CASEINCOMPLETE`, `CASEOVERLAP`, `UNOPTFLAT`) before proceeding — a
structurally broken RTL will waste time in every later stage, and as
Chapter 8/10 demonstrated, neither synthesis nor STA nor EQY will reliably
catch these classes of bug for you. (Chapter 8.)

**3. Run a plain synth pass.** `python3 run_synth.py --verilog <your.v>
--top <top> --liberty <lib.lib> --run-id baseline --out
artifacts/synth/baseline.json`. Confirm `"ok": true` and a sane `num_cells`.
If synth fails with a Verilog syntax error pointing at the *output*
netlist rather than your source, check the `clean -purge` line in
`run_synth.tcl` is present (Chapter 5's escaped-wire bug). (Chapter 5.)

**4. Write `constraint.sdc` incrementally, verifying after every addition.**
Do not write the whole file at once and then debug it as a block — that
makes it much harder to isolate which line caused which symptom. Follow
Chapter 11's exact order: (a) primary clocks, (b) generated clocks (using
the dynamic-driver-pin `proc` pattern if any generated clock exists), (c)
run STA, check for self-path or other clock-relationship artifacts before
adding anything else, (d) `set_clock_groups -asynchronous` for genuinely
independent domains, (e) I/O delays — and explicitly *skip* input delay on
any asynchronous reset/control port, don't add it symmetrically "to be
safe." (Chapter 3, Chapter 11.)

**5. Run STA and drive violated-path count to zero, or a deliberate,
justified value.** `python3 run_sta.py --netlist <netlist.v> --top <top>
--sdc <constraint.sdc> --liberty <lib.lib> --tlef <tlef> --lef <lef>
--group-count 10 --out artifacts/sta_baseline.json --raw-out
/tmp/sta_raw.txt`. Every remaining violation should be either a real,
acknowledged timing problem (the thing the loop exists to fix) or an
explicitly justified, commented `set_false_path`/similar exclusion — never
an unexplained one. (Chapter 6.)

**6. Full-design EQY self-check, as a sanity check on tool wiring.** Run
`run_eqy.py` with your source as both `--gold` and `--gate` — this should
always report `PROVED_EQUIVALENT` (Chapter 9's caveat: this only proves the
tool pipeline is wired correctly, not that the design itself is bug-free —
that's what step 2's lint pass is for). (Chapter 9.)

**7. Run the full ORFS flow once, for a true baseline PPA number.** This is
your "before" figure for the eventual deliverable comparison — don't skip
it in favor of only ever looking at the fast tier's estimates. (Chapter 7.)

**8. Smoke-test the loop in `--mock` mode.** `python3 llm_loop.py --verilog
<your.v> --top <top> --liberty <lib.lib> --sdc <constraint.sdc> --run-id
smoke --max-edits 1 --mock`. Confirms the synth-retry tier, EQY gate, and
accept/reject logic all function against your new design before spending
any real API budget on it. (Chapter 12, Chapter 13.)

**9. Set up API billing and run for real, starting small.**
`export ANTHROPIC_API_KEY=...`, then the same command without `--mock` and
a small `--max-edits` (1–2) first. Watch the stderr trace — it prints the
pre-edit WNS/violated count, each synth-retry strategy's result, each LLM
proposal's technique and rationale, and each EQY/accept-reject decision
inline, so a run can be understood without re-parsing artifacts after the
fact. (Chapter 14, Chapter 15.)

**10. Run ORFS once more on the loop's final RTL, for the "after" PPA
number**, and produce the honest before/after comparison the Nebula
deliverable checklist asks for — including, if applicable, how many of the
original N violating paths actually closed, not just a qualitative
"improved" claim. (Chapter 7, and CLAUDE.md's "what actually wins" section.)

---

## Chapter 20 — Troubleshooting Compendium

Organized by symptom, not by tool — because the first thing you'll have is
an error message, not a chapter number.

**`syntax error` in OpenSTA when reading a Yosys-written netlist, pointing
at an escaped identifier (`\...$...`)** — Yosys's `clean` (not `-purge`)
left function-local temporary wires with escaped names in the netlist.
Fix: `yosys clean -purge` in your synth Tcl script. (Chapter 5.)

**`pin 'u_X/some_port' not found` when reading an SDC that references a
submodule port by hierarchical name** — `link_design` flattens hierarchy;
submodule ports don't survive as pins. Resolve driver pins dynamically off
a surviving *net* name instead, filtering `get_pins -of_objects [get_nets
-hierarchical <net>]` by `direction`. (Chapter 6, Chapter 11.)

**A huge, suspicious setup violation where startpoint == endpoint (a
register's self-feedback path), especially involving a generated clock** —
almost always a launch/capture time-base modeling artifact from the
generated clock's own defining register also being a real sequential
element. Verify the pin's only non-clock fanout is its own feedback, then
scope a `set_false_path -through <that exact pin>` — never a blanket
`set_propagated_clock` as a first attempt, that changes the model
everywhere at once and can make things much worse. (Chapter 11.)

**New, unexplained STA violations appear on ports that "should" be simple
inputs, especially reset/enable/control signals** — check whether
`set_input_delay` was applied to a port that's actually asynchronous
(sampled via `negedge`/`posedge` directly as a reset, not as synchronous
data). OpenSTA already generates correct recovery/removal checks for true
async signals automatically; don't add a synchronous setup check on top.
(Chapter 11.)

**Verilator reports `UNOPTFLAT`** — do not dismiss this as ring-topology
noise by default. It is the tool's flag for a signal it cannot linearly
schedule, which is the exact signature of a real combinational loop. Trace
the reported signal's full dependency chain by hand before deciding it's
benign; if a flag/status signal is derived from a "lookahead" version of a
pointer/counter that is itself gated by that same flag (directly, or
indirectly through how an *external* enable signal is wired), that's a real
loop. (Chapter 8, Chapter 10.)

**An LLM-proposed edit gets rejected by EQY every retry, `max_retries_per_path`
exhausted** — check the module actually being edited via the stderr
localization line (`localized worst path to module: ...`, Chapter 16). If
the localizer fell back to the top module unexpectedly, the target module
may simply be too large/glue-heavy for the LLM to safely restructure in one
shot — consider whether the worst path genuinely needs to be traced into a
deeper submodule your instantiation-parsing regex isn't recognizing (e.g. an
unusual instantiation syntax with unusual whitespace/comments between the
module type and instance name).

**An edit "improves" WNS but you don't trust the result** — check
`num_violated` before and after, not just WNS; this project's own accept
logic learned this the hard way (Chapter 15) and now requires both.

**`ANTHROPIC_API_KEY not set` when running `llm_loop.py` without `--mock`**
— API billing is separate from any Claude.ai chat subscription; set up
billing at console.anthropic.com, export the key, and note per-call cost
scales with `--max-edits × --max-retries-per-path` (Chapter 14's cost note).

**`ModuleNotFoundError: No module named 'anthropic'`** — the `anthropic`
Python package isn't part of this project's base environment; install it
into a dedicated virtualenv (`python3 -m venv .venv && .venv/bin/pip install
anthropic`) rather than the system Python, and run `llm_loop.py` with that
venv's interpreter — most modern OS Python installs (PEP 668, "externally
managed environment") will refuse a bare `pip install` outside a venv
anyway.

### 19.1 Deep dives: how each of these was actually found and fixed

The entries above are the compressed, symptom-indexed form. What follows is
the long form for the hardest ones — the actual investigative path taken,
including the false leads, because the false leads are exactly what you
will also hit first on a new design. Reading only the final fix teaches you
the fix; walking the investigation teaches you the *method*, which is the
thing that transfers to a bug this book has never seen.

#### Challenge: the escaped-identifier netlist syntax error

**Symptom, verbatim in spirit:**
```
Error: nebula_soc_v1.v line 812: syntax error near '\_gcd$flatten$...\$auto$...'
```

**First (wrong) instinct:** treat it as an OpenSTA parser bug or a Verilog
version mismatch, and try adding `-sv` or downgrading the Verilog dialect
flag. Neither changes anything, because the problem isn't the *dialect*, it's
that the identifier itself is syntactically pathological — a Yosys internal
temporary name containing `$` and `.` characters, backslash-escaped per
Verilog's escaped-identifier rule so it technically parses, but which a
different tool's reader can choke on depending on how strictly it interprets
the trailing-whitespace terminator of an escaped identifier.

**Real root cause:** `yosys clean` (bare, no `-purge`) only removes wires
with *zero* fanout. Internal temporaries created and then only partially
optimized away during `synth`/`abc` can retain a dangling single connection,
survive `clean`, and get written into the final netlist with their raw
internal name intact.

**How it was actually found:** grep the written netlist for `\$` patterns
near the reported line number, count how many such identifiers exist
(dozens, not one) — a single stray identifier would suggest a one-off
parser edge case; dozens across unrelated logic clusters instead points at
a systemic pass ordering issue, i.e. something in the synth script itself.

**Fix, and why it's the right one and not a workaround:** `yosys clean
-purge` performs a more aggressive sweep that also removes internal
wires regardless of fanout state once they're structurally dead. This
isn't papering over the symptom — the escaped names were never meant to
survive into a "final" netlist; `-purge` is the documented way to ask Yosys
to finish that cleanup. Verified by re-grepping the post-fix netlist for
`\$` patterns: zero matches.

**Why this generalizes:** any time a generated artifact (netlist, report,
generated Verilog from an LLM edit) has internal tool-generated identifiers
leaking into it, the right question is not "how do I make the downstream
reader more tolerant" but "why didn't the upstream tool clean up before
writing." Tolerant readers hide real upstream bugs.

#### Challenge: the async_fifo UNOPTFLAT — distinguishing real loops from ring-topology noise

This is the single most instructive bug in the whole project, because the
wrong fix (suppress the warning) would have shipped a functional bug that
neither EQY nor a clean STA run would ever have caught.

**Symptom:** `%Warning-UNOPTFLAT: nebula_soc.v:96: Signal unoptimizable:
async_fifo.rd_ptr_gray_next` (approximate; two instances of this warning,
one per gray-code pointer side).

**First (wrong, but reasonable) instinct:** `nebula_soc`'s top level wires
five `async_fifo` instances into a *ring* — domain N's FIFO write side is
driven by domain N, its read side is read by domain N+1, wrapping around.
A ring topology is inherently cyclic at the block-diagram level, so the
first hypothesis was "Verilator is just confused by the ring shape, this is
benign, suppress it and move on." This is a dangerous hypothesis because
it's *plausible* — ring topologies really do trigger tool confusion
sometimes — which makes it tempting to accept without checking.

**Why that hypothesis had to be checked, not assumed:** `UNOPTFLAT` is
specifically Verilator's signal for "I could not find a linear evaluation
order for this signal's combinational fan-in," which is a statement about a
single signal's *local* dependency structure, not about the module
graph's global topology. A design can have a cyclic block diagram (the
ring) while every individual signal inside it is perfectly acyclic (because
the cycle is broken by a register, as it should be for any real CDC ring).
So "it's a ring, therefore this warning is expected" does not actually
follow — it was necessary to check what specific signal was flagged and
trace its fan-in by hand.

**Investigation, step by step:**
1. Read the two flagged signal names: both were the *combinational
   lookahead* version of a gray-code pointer, e.g. `rd_ptr_gray_next` —
   not the registered pointer itself.
2. Traced `rd_ptr_gray_next`'s assignment: it's a function of the current
   registered pointer and `rd_en`.
3. Traced `rd_en`: **not** an internal FIFO signal — it's driven from
   outside the module, at the top-level instantiation, as
   `.rd_en(!fifo0_rd_empty)`.
4. Traced `fifo0_rd_empty`: an *output* of the same FIFO instance, computed
   combinationally by comparing the read pointer (including its lookahead
   term in some formulations) against the write pointer.
5. Closed the loop: `rd_ptr_gray_next` depends on `rd_en`, which depends on
   `rd_empty`, which depends on the read pointer's own combinational
   lookahead term — a genuine same-cycle combinational cycle through the
   module boundary, not resolved by any register in between.

**Fix:** register `rd_en` (or equivalently, gate the lookahead computation
off the *registered* empty flag rather than a same-cycle combinational
one) so the dependency from "am I empty" to "should I advance the pointer"
crosses a clock edge instead of closing combinationally within one.
Re-ran lint: `UNOPTFLAT` gone. Re-ran EQY between the pre-fix and post-fix
RTL: **not equivalent** (expected and correct — this was a real functional
change, not a cosmetic one, so equivalence *should* fail here; this is the
one case in the whole project where an EQY "fail" on your own hand-written
fix is the expected, correct outcome, precisely because you are not
claiming the fixed version behaves identically to the buggy version).
Re-ran STA: no new violations introduced by the extra register.

**Why this generalizes, and is the book's single most important lesson:**
a tool's warning tells you *where* to look, not *whether* it's real. The
determination of "real bug" vs. "tool confusion" has to be made by manually
walking the actual dependency chain the tool named, every time, especially
when the "benign" explanation is the one that lets you stop working sooner.
An `UNOPTFLAT` (or any lint warning) on a ring/mesh/multi-instance topology
should always be traced signal-by-signal before being classified as noise;
Chapter 8's `HARD_CODES` set exists specifically so this class of warning
is never silently dropped by default.

#### Challenge: the generated-clock self-path false violation

**Symptom:** `report_checks` shows a single path with startpoint and
endpoint both landing on the same internal, auto-generated gate name inside
a `clk_divider` instance, with slack in the range of several nanoseconds
negative — implausibly large for a single-cycle toggle-flop path.

**First (wrong) instinct:** assume the divider RTL itself has a real timing
bug (a long combinational chain feeding its own toggle logic) and start
looking for ways to pipeline the divider's mux. This wastes time because
the divider's mux is trivial — one AND-gate-depth from `cnt == HALF-1` to
the toggle. A multi-nanosecond violation on a single-gate path is a strong
signal that the *arrival/required time computation itself* is wrong, not
that the logic is slow.

**Real root cause:** the flop that defines a `create_generated_clock`
source is, in this design, also an ordinary functional register with a
real data path (its own feedback for the toggle). OpenSTA, when computing
timing for a path whose *capture* clock is a generated clock, uses that
generated clock's own multi-period/latency model at the capture edge; but
this particular path's *launch* is the same physical register in its role
as an ordinary flop launching combinational data — a launch/capture
time-base mismatch that produces an arithmetically large, but not
physically meaningful, "violation." (See Chapter 11's worked-example
follow-up for the arithmetic.)

**How it was distinguished from a real bug, concretely:** checked whether
the flagged pin's net has *any* fanout other than feeding back into its own
toggle logic and driving downstream `CLK` pins as the generated clock's
distribution point. It didn't — every other net that a real functional bug
would show up on (the divider's counter reset logic, output enables) was
completely uninvolved in this specific path. A path that touches *only*
the clock-defining pin and nothing else in the functional design is the
structural signature of a modeling artifact, not a functional slow path.

**Fix:** `set_false_path -through [div_clk_driver $dc]` per divider — scoped
to the *exact* driver pin (resolved dynamically, since `link_design`
renames it every resynthesis), never a broad `set_false_path -to
[all_clocks]` or similar blanket exception. The scoping is the whole point:
a false-path exception that's too broad can silently hide a real future
violation on a completely different path that happens to share the same
clock.

**Why this generalizes:** any STA "violation" whose magnitude looks
physically implausible for the amount of logic on the path is worth
checking for a *modeling* artifact before a *design* bug — but the check
has to end in a specific, scoped exception with a written-down reason
(Chapter 11's SDC comments exist for exactly this), never an unscoped
suppression applied because "it's probably fine."

#### Challenge: async reset ports producing spurious max-path violations

**Symptom:** after adding `set_input_delay` uniformly to every top-level
input port (a natural first move — every input needs *some* delay
constraint or OpenSTA can't compute arrival times for paths starting
there), several new violations appeared with `rst*_n` ports as the
startpoint.

**First (wrong) instinct:** treat these like any other input-side
violation and either loosen the `set_input_delay` value or look for logic
to speed up on the reset fan-out path. Both miss the actual issue, which is
that a *synchronous setup check* is the wrong check to be running on this
port at all.

**Real root cause:** the RTL uses `rst*_n` exclusively via
`always @(negedge clk or negedge rst_n)` — true asynchronous reset. OpenSTA
already generates the correct check type for asynchronous control
signals automatically (recovery/removal checks) once it recognizes the
signal's role from the sensitivity list — no `set_input_delay` needed or
wanted. Applying `set_input_delay` on top additionally forces OpenSTA to
treat the port as if it were ordinary synchronous data racing against a
clock edge, layering an inapplicable check on top of the correct one, and
that inapplicable check is what produced the reported violations.

**How it was confirmed, not just guessed:** checked the report's path
*type* — the spurious violations were specifically `max` (setup-type)
delay checks with a `rst*_n` startpoint. Recovery/removal checks, which
OpenSTA generates natively for async control ports, show up as their own
distinct check category, not as ordinary `max`/`min` path-delay checks —
seeing an ordinary setup check on a signal that the RTL only ever uses
asynchronously was the tell that the check itself, not the design, was
wrong.

**Fix:** removed `set_input_delay` from the reset ports entirely, with an
SDC comment explaining why (Chapter 11 / SDC line 50-56 above) so a future
editor doesn't "fix" the apparent omission by re-adding it.

**Why this generalizes:** "every port needs a constraint" is a good default
instinct but not a universal rule — the correct question for every port is
"what check does this port's actual RTL usage imply," not "what check does
this port's *direction* imply." Get this wrong and you can spend real time
optimizing logic that was never actually a timing problem.

#### Challenge: EQY rejecting a structurally-sound LLM edit

**Symptom, real behavior observed during Chapter 15/19 testing:** an
LLM-proposed `pipelining` edit on `compute_pipeline` that visually looked
correct (register correctly inserted mid-multiply, output correctly
re-timed by one cycle) was rejected by EQY as `NOT_EQUIVALENT_OR_ERROR`.

**First (wrong) instinct:** assume the LLM's edit was functionally wrong
and immediately move to the next retry without reading EQY's own log.

**Real root cause found by reading `log_tail`, not by re-reading the RTL
diff:** EQY's SAT strategy unrolls sequential depth up to the configured
`depth` parameter (5 cycles by default, Chapter 9/Appendix D.5); a
pipelining edit that adds *latency* (an extra register stage) shifts when
the gold and gate models' outputs align in time. If the requested `depth`
is too shallow relative to the added latency plus the existing pipeline's
own depth, EQY can genuinely fail to find the alignment within its bounded
window — which produces the same rejection message as a truly non-equivalent
edit, but for a completely different reason (a solver configuration limit,
not a design defect).

**How the two cases are told apart in practice:** re-run the identical gold
vs. gate pair with `--depth` doubled. If the result flips to
`PROVED_EQUIVALENT`, the original rejection was a depth-limit artifact, not
a real inequivalence — and the fix belongs in the `depth` parameter (scoped
to techniques that add latency), never in silently trusting an unverified
edit. If the result stays `NOT_EQUIVALENT_OR_ERROR` even at a much larger
depth, the edit is genuinely wrong and the correct action is to let the
loop's retry-and-reject logic do its job.

**Why this generalizes:** a "formal" tool's negative result is not
automatically ground truth about the *design* — it can also be a statement
about the *tool's own configured bounds*. Before trusting a hard reject
from any bounded-verification tool (SAT depth, model-checker step count,
timeout), confirm the bound itself was sufficient for the specific change
being checked, especially for techniques (pipelining, retiming) that are
specifically defined by changing latency or register placement.

#### Challenge: WNS improves but the edit still shouldn't be accepted

**Symptom:** an early, simpler version of the accept-criterion logic
accepted an edit purely because `wns_after > wns_before`.

**Real root cause:** WNS is a single-number summary of the *worst* path
only. An edit can improve the single worst path's slack while making a
*different*, previously-second-worst path cross into violation — net
result: overall design quality got worse (more violated paths, more total
negative slack), while the one number being checked went up.

**How it was caught:** by deliberately looking at `num_violated` alongside
`wns` on a run where the two disagreed — WNS improved by 0.3ns but violated
path count went from 1 to 2. This is exactly the scenario Chapter 15's
`no_new_violations` check was added to catch, and it is the reason the
accept criterion is a conjunction of *both* conditions, not either alone.

**Why this generalizes:** any single scalar summary metric (WNS, total
negative slack, average IPC, whatever the domain) can be locally improved
while a distribution around it gets worse. Any automated accept/reject gate
built on a summary statistic should also check the shape of the underlying
distribution it was computed from, not just the statistic's direction of
travel.

#### Challenge: environment/tooling friction that has nothing to do with the design

Not every real problem is a design bug — a meaningful fraction of actual
time in this project went to tooling friction, and it's worth cataloguing
honestly rather than pretending the pipeline was always the bottleneck:

- **Gatekeeper quarantine blocking every OSS CAD Suite binary on macOS** —
  first run of any bundled tool pops a "cannot be opened, unidentified
  developer" dialog, once *per binary*, which is unworkable for a toolchain
  with dozens of binaries. Fix once, up front:
  `xattr -dr com.apple.quarantine oss-cad-suite/` before first use, not
  reactively per-binary as each dialog appears.
- **PEP 668 "externally managed environment" blocking `pip install`** on
  a modern system Python — the fix is not `--break-system-packages` (which
  works but risks corrupting the OS's own Python tooling); it's a
  dedicated venv, every time, for every Python dependency this project
  needs beyond the standard library.
- **`.venv` vs. hardcoded `.venv_llm` path mismatch** — `llm_loop.py`'s
  `sys.path` insertion (Appendix D.7) assumes a specific venv directory
  name; if you create your venv under a different name, the import will
  silently fail to find `anthropic` even though `pip install` reported
  success into a *different*, real venv. The fastest diagnostic for "pip
  said it installed but Python says ModuleNotFoundError" is always to
  check `sys.executable` and `sys.path` inside the failing interpreter
  against the one `pip install` actually targeted — a mismatch between
  "the pip you ran" and "the python you ran" is one of the most common
  and least obvious classes of Python environment bug, and it will not
  announce itself as an environment problem; it will look exactly like a
  missing package.
- **Architecture mismatch on the OSS CAD Suite tarball** — `-darwin-x64`
  on Apple Silicon runs under Rosetta with no error at all, just silently
  worse performance and occasional subtle floating-point/threading
  differences in tools that use native SIMD paths; always confirm
  `-darwin-arm64` was actually the file downloaded, don't rely on a "it
  ran without error" signal to prove the architecture was correct.

**Why this category generalizes:** a project like this spans real tool
version/environment boundaries (Python venvs, OS-level Gatekeeper, CPU
architecture, PDK file paths) that have nothing to do with RTL correctness
but will consume real debugging time and can produce misleading symptoms
(a "ModuleNotFoundError" that's actually a path bug, a "successful" run
that's actually running under emulation) if not checked explicitly and
early, rather than assumed.

---

## Chapter 21 — Command Reference

A single-page cheat sheet of every command this book uses, grouped by
purpose.

**Lint**
```bash
python3 run_lint.py --verilog <file.v> [--verilog <file2.v> ...] \
    --top <module> --run-id <tag> --out artifacts/lint/<tag>.json \
    [--ignore <WARNING_CODE>]
```

**Synthesis (fast tier)**
```bash
python3 run_synth.py --verilog <file.v> --top <module> \
    --liberty <lib.lib> --run-id <tag> --out artifacts/synth/<tag>.json \
    [--strategy default|retime|timing_driven] [--abc-period-ps <ps>]
```

**STA — from a netlist (fast tier, pre-place-and-route)**
```bash
python3 run_sta.py --netlist <netlist.v> --top <module> \
    --sdc <constraint.sdc> --liberty <lib.lib> \
    --tlef <tech.tlef> --lef <cells_merged.lef> \
    --group-count 10 --out artifacts/sta_<tag>.json \
    [--raw-out /tmp/sta_raw.txt]
```

**STA — from a placed-and-routed database (accurate tier)**
```bash
python3 run_sta.py --db <results>/6_final.odb \
    --sdc <constraint.sdc> --liberty <lib.lib> \
    --out artifacts/sta_<tag>.json
```

**Formal equivalence**
```bash
python3 run_eqy.py --gold <gold.v> --gate <gate.v> --top <module> \
    --run-id <tag> --out artifacts/eqy/<tag>.json \
    [--sv] [--depth 5] [--keep-workdir]
```

**Full agentic loop**
```bash
# mock (no API calls):
python3 llm_loop.py --verilog <file.v> --top <module> \
    --liberty <lib.lib> --sdc <constraint.sdc> \
    --run-id <tag> --max-edits <N> --mock

# real:
export ANTHROPIC_API_KEY=...
python3 llm_loop.py --verilog <file.v> --top <module> \
    --liberty <lib.lib> --sdc <constraint.sdc> \
    --run-id <tag> --max-edits <N> [--max-retries-per-path <N>] \
    [--slack-threshold <ns>] [--no-synth-retry]
```

---
---

# Appendix

## A. Glossary

**CDC** — Clock Domain Crossing: a signal moving between two clocks with no
fixed relationship, requiring synchronization hardware (Chapter 1, 10).

**EQY** — the equivalence-checking driver from YosysHQ built on `sby`,
proving two RTL descriptions compute the same function via SAT (Chapter 9).

**Gold / Gate** — EQY's naming for the reference RTL ("gold") and the
candidate RTL being checked against it ("gate") (Chapter 9).

**Liberty (`.lib`)** — a standard-cell library file: per-cell delay, area,
power characterization at a given process/voltage/temperature corner.

**Path group** — OpenSTA's bucketing of timing paths by capturing clock
(Chapter 2).

**Slack** — required time minus arrival time; negative slack is a violation
(Chapter 2).

**Setundef** — Yosys's step to resolve don't-care/uninitialized bits to a
concrete value (here, zero) before writing a netlist (Chapter 5).

**Tech-mapping** — converting generic logic gates to a specific standard
cell library's actual cells (Chapter 5, the `abc` step).

**WNS / TNS** — Worst / Total Negative Slack across a design (Chapter 2).

## B. File Manifest

| File | Role |
|---|---|
| `run_lint.py` | Verilator lint wrapper, hard/informational classification |
| `run_synth.py` / `run_synth.tcl` | Fast standalone Yosys synthesis |
| `run_sta.py` / `run_sta.tcl` | OpenSTA wrapper, text report → JSON |
| `run_eqy.py` | EQY formal equivalence wrapper |
| `rtl_hierarchy.py` | Instance-path → RTL module localizer |
| `llm_loop.py` | The full Stage 8 agentic loop |
| `designs/src/nebula_soc/nebula_soc.v` | Benchmark RTL |
| `designs/sky130hd/nebula_soc/constraint.sdc` | Benchmark SDC |
| `platforms/sky130hd/` | PDK LEF/Liberty files |

## C. Reference Papers and Why Each One Matters

- **ViTAD** (arxiv.org/pdf/2508.13257) — nearly identical architecture to
  ours (parse RTL + timing report → dependency graph → LLM root-cause →
  targeted fix); its 73.68% repair rate is this project's benchmark to beat
  or honestly compare against.
- **AutoChip** — the simplest working reference for the propose/verify loop
  shape; read the real repo, not just the paper, when extending Chapter 14.
- **SymRTLO** — includes an FSM-state-merging module directly relevant to
  the `fsm_recode` technique (Chapter 14's `TECHNIQUES` list).
- **"Rethinking LLM-Based RTL Code Optimization"** — documents that LLMs are
  specifically weaker at timing-critical rewrites, which is the entire
  reason this project's EQY gate (Chapter 9) and regression-aware accept
  criterion (Chapter 15) exist as hard, non-negotiable gates rather than
  soft heuristics.

## D. Full Annotated Source Listings

This appendix walks every non-Verilog file in the pipeline block by block —
what each line does and, where relevant, which chapter derived it and why.
Verilog listings (`nebula_soc.v`, `constraint.sdc`) were already given in
full, annotated, in Chapters 10–11; they are not repeated here.

### D.1 — `run_lint.py` (complete, Chapter 8)

```python
HARD_CODES = {
    "LATCH", "COMBDLY", "BLKSEQ", "MULTIDRIVEN", "CASEINCOMPLETE",
    "CASEOVERLAP", "UNOPTFLAT",
}
```
The correctness-risk allowlist. Every other Verilator warning code (width
truncation, unused signal, style) is treated as informational — see
Chapter 8 for why this is a diff-against-baseline design, not a blanket gate.

```python
WARNING_RE = re.compile(
    r"%Warning-(?P<code>[A-Z0-9]+):\s*(?P<file>[^:]+):(?P<line>\d+):\d+:\s*(?P<msg>.*)"
)
```
Matches Verilator's exact warning line shape:
`%Warning-UNOPTFLAT: nebula_soc.v:96:3: Signal unoptimizable: ...` — four
capture groups: warning code, file, line, message. Column number
(the second `\d+`) is matched but discarded; only line-level granularity is
tracked.

```python
def find_verilator(explicit):
    if explicit:
        return explicit
    candidate = FLOW_DIR.parent / "tools/install/yosys/bin/yosys"
    ...
```
*(shown as pattern — actual candidate path is
`oss-cad-suite/bin/verilator`, per Chapter 8)* — resolves the binary either
from an explicit `--verilator` flag or a conventional install path relative
to the flow directory, raising `FileNotFoundError` with an actionable
message rather than letting `subprocess.run` fail opaquely on a missing
executable.

```python
def run_lint(verilator_exe, verilog_files, top, extra_args):
    cmd = [str(verilator_exe), "--lint-only", "-Wall"] + extra_args + \
          ["--top-module", top] + [str(v) for v in verilog_files]
    result = subprocess.run(cmd, cwd=FLOW_DIR, capture_output=True, text=True, timeout=120)
    return result
```
`--lint-only`: frontend checks, no simulation model built (fast, no
testbench needed). `-Wall`: enable Verilator's full (non-default) warning
set. `extra_args`: per-run `-Wno-<CODE>` suppressions, built from `--ignore`
(used for `gcd`'s pre-existing `BADVLTPRAGMA` noise, Chapter 8).
`--top-module`: disambiguates which module is the design root when multiple
top-level-looking modules exist in the file set. `timeout=120`: a lint pass
should never legitimately take two minutes; this is a safety bound, not a
tuned performance target.

```python
def parse_warnings(stderr_text):
    warnings = []
    for m in WARNING_RE.finditer(stderr_text):
        warnings.append({"code": m.group("code"), "file": m.group("file"),
                          "line": int(m.group("line")), "msg": m.group("msg").strip()})
    return warnings
```
Verilator writes warnings to **stderr**, not stdout — note `run_lint`
captures both, but this function is always called on `result.stderr`
specifically in `main()`. `finditer` (not `findall`) is used so every match
retains its named groups as a `re.Match` object rather than collapsing to a
tuple.

```python
    record = {
        "run_id": args.run_id, "top": args.top, "verilog": args.verilog,
        "returncode": result.returncode,
        "num_warnings": len(warnings), "num_hard_warnings": len(hard),
        "warnings": warnings, "hard_warnings": hard,
    }
    out_path.write_text(json.dumps(record, indent=2))
```
Note `returncode` is recorded but **not** checked as a pass/fail signal —
Verilator's own exit code reflects *its* opinion of severity, which does not
match this project's `HARD_CODES` classification; the JSON's
`num_hard_warnings` is the number a caller should actually branch on.

### D.2 — `run_synth.tcl` (complete, Chapter 5)

```tcl
foreach v {SYNTH_VERILOG SYNTH_TOP SYNTH_LIBERTY SYNTH_OUT_V} {
    if { ![info exists ::env($v)] } {
        puts "ERROR: set $v env var"
        exit 1
    }
}
```
Fail fast, with a specific missing-variable name, rather than letting a
later Yosys command fail with a cryptic "no such file" once it tries to
`read_verilog` an empty path.

```tcl
set verilog_files [split $::env(SYNTH_VERILOG) ":"]
foreach f $verilog_files {
    yosys read_verilog -sv $f
}
```
`SYNTH_VERILOG` is a single colon-joined string (set on the Python side via
`":".join(...)`, Chapter 5) because Tcl environment variables are flat
strings — `split ... ":"` is the Tcl-side half of that multi-file-argument
convention; every wrapper in this project (`run_synth.py`'s `--verilog`
`action="append"`) that supports repeatable file arguments uses this same
colon-join/colon-split pairing across the Python/Tcl boundary.

```tcl
yosys hierarchy -top $::env(SYNTH_TOP)
yosys synth -top $::env(SYNTH_TOP)
yosys dfflibmap -liberty $::env(SYNTH_LIBERTY)
```
Three-stage front end: establish the hierarchy root, run Yosys's generic
synthesis script, then map generic sequential cells to real Liberty
flip-flops — full explanation of each in Chapter 5's main text.

```tcl
set strategy "default"
if { [info exists ::env(SYNTH_STRATEGY)] } { set strategy $::env(SYNTH_STRATEGY) }
if { $strategy eq "retime" } {
    yosys abc -liberty $::env(SYNTH_LIBERTY) -dff
} elseif { $strategy eq "timing_driven" } {
    if { ![info exists ::env(SYNTH_ABC_PERIOD_PS)] } {
        puts "ERROR: SYNTH_STRATEGY=timing_driven requires SYNTH_ABC_PERIOD_PS"
        exit 1
    }
    yosys abc -liberty $::env(SYNTH_LIBERTY) -D $::env(SYNTH_ABC_PERIOD_PS)
} else {
    yosys abc -liberty $::env(SYNTH_LIBERTY)
}
```
The Chapter 13 synthesis-retry-tier dispatch. Defaulting `strategy` to
`"default"` means this file is fully backward compatible with any caller
that never sets `SYNTH_STRATEGY` at all — the retry tier is additive, never
a behavior change to the base path.

```tcl
yosys clean -purge
yosys setundef -zero
```
`clean -purge`: the Chapter 5 escaped-wire fix. `setundef -zero`: resolves
any remaining `x`/don't-care bits to a concrete `0` before the netlist is
written — without this, a netlist can contain don't-care constants that
some downstream readers (or, in principle, an LLM asked to reason about the
RTL's behavior) could silently mis-interpret; forcing a concrete value keeps
the written netlist fully determinate.

```tcl
yosys write_verilog -noattr $::env(SYNTH_OUT_V)
yosys flatten
yosys tee -o [format "%s.stat.json" $::env(SYNTH_OUT_V)] stat -json -liberty $::env(SYNTH_LIBERTY)
```
Write-before-flatten (Chapter 5, Chapter 16's dependency on it), then
flatten a throwaway in-memory copy purely for accurate whole-design
`stat -json` totals. `-noattr` strips Yosys's internal attribute annotations
from the written Verilog — cosmetic, but keeps the netlist file readable
and avoids attribute syntax OpenSTA's reader doesn't need to see.
`yosys tee -o <file> stat ...`: `tee` duplicates a command's output to both
the console and a file, exactly like the shell command of the same name —
this is how `run_synth.py` later reads `<netlist>.stat.json` for cell/area
figures.

### D.3 — `run_sta.tcl` (complete, Chapter 6)

```tcl
set have_db [info exists ::env(STA_DB)]
set have_netlist [info exists ::env(STA_NETLIST)]
if { !$have_db && !$have_netlist } {
    puts "ERROR: set either STA_DB (.odb) or STA_NETLIST+STA_TOP (synthesized netlist)"
    exit 1
}
```
The fast-tier/accurate-tier branch point (Chapter 6, Chapter 7) is decided
here, at the Tcl level, purely by which environment variable is present —
`run_sta.py`'s own `--db`/`--netlist` argument-group validation
(`ap.error(...)` if neither is given) is a duplicate, earlier check on the
Python side; both exist because failing fast in Python (before ever
spawning OpenROAD) gives a cleaner error message, while this Tcl-level check
is the real safety net if the script is ever invoked directly.

```tcl
read_liberty $::env(STA_LIBERTY)
if { $have_db } {
    read_db $::env(STA_DB)
} else {
    read_lef $::env(STA_TLEF)
    read_lef $::env(STA_LEF)
    read_verilog $::env(STA_NETLIST)
    link_design $::env(STA_TOP)
}
read_sdc $::env(STA_SDC)
```
Order matters: Liberty must be read before either the `.odb` or the netlist
(both reference Liberty cells by name and need the library loaded to
resolve them). In netlist mode, both LEF files (`STA_TLEF`, technology LEF,
and `STA_LEF`, the merged standard-cell LEF) must load before
`read_verilog`, and `link_design` — the flattening step central to
Chapters 6 and 11 — runs last, after the netlist is in memory. `read_sdc`
runs only after the design is fully linked, since SDC commands like
`create_generated_clock` need to resolve real pins that only exist
post-link.

```tcl
puts "=== BEGIN MAX PATHS ==="
report_checks -path_delay max -group_path_count $group_count -fields {slew cap input} -digits 4
puts "=== END MAX PATHS ==="
```
`-fields {slew cap input}`: requests slew (signal transition time),
capacitance, and input-pin annotations per delay-table row, in addition to
the default delay/time columns — this is exactly what makes
`CELL_LINE_RE` (Appendix D.4) able to parse `cap`/`slew` as optional leading
columns. `-digits 4`: fixes the decimal precision of every printed number,
which is what makes the parsing regexes' `[\d.]+` patterns reliable across
runs — an inconsistent digit count would still parse, but locking it removes
one more variable when debugging a parse mismatch.

### D.4 — `run_sta.py` parsing internals (Chapter 6, detail)

```python
SLACK_LINE_RE = re.compile(r"^\s*(-?\d+\.\d+)\s+slack \((?:MET|VIOLATED)\)", re.MULTILINE)
```
Defined but effectively superseded within `parse_paths` by the more robust
"scan backward for the last bare numeric line before the status marker"
loop — kept as a fallback pattern in the source; the actual slack extraction
logic used is the manual reverse-scan shown below, added specifically
because the straightforward regex-only approach was less robust against
`report_checks` output where the slack value's line has variable leading
whitespace depending on sign and magnitude.

```python
slack_val = None
for line in reversed(body.strip().splitlines()):
    line = line.strip()
    mm = re.match(r"^(-?\d+\.\d+)$", line)
    if mm:
        slack_val = float(mm.group(1))
        break
```
Walks the path body **backward** from the `slack (MET|VIOLATED)` marker,
returning the first line that is *purely* a signed decimal number with
nothing else on it — the actual slack value line in OpenSTA's report
format. Scanning backward from a known anchor (the status marker) is more
robust than scanning forward from the start of a variable-length delay
table, because the slack line's exact position varies with the number of
cells in the path, but its position *relative to* the status marker does
not.

```python
all_paths.sort(key=lambda p: (p["slack"] if p["slack"] is not None else float("inf")))
for rank, p in enumerate(all_paths):
    p["rank"] = rank
```
Explicit re-sort and re-rank after merging `max_paths` and `min_paths` —
OpenSTA reports each path-delay type in its own separately-ranked block, so
after concatenation the combined list is re-sorted by actual slack value
(most negative first) and given a fresh, single, global `rank` field. This
is what makes `sta_data["paths"][0]` (used throughout `llm_loop.py`,
Chapter 12–15) reliably "the single worst path in the whole design,"
regardless of whether that worst path happened to be a max-type or
min-type violation.

### D.5 — `run_eqy.py` (complete, Chapter 9)

```python
EQY_TEMPLATE = """\
[gold]
read_verilog {gold_flags}{gold}
prep -top {top}

[gate]
read_verilog {gate_flags}{gate}
prep -top {top}

[strategy sat]
use sat
depth {depth}
"""
```
This is not Tcl — it's EQY's own small `.eqy` config-file format (INI-like
sections). `[gold]`/`[gate]` each name one script (here, a single
`read_verilog` + `prep -top`) that EQY runs internally via Yosys to
elaborate each side. `[strategy sat]` selects the bounded SAT-based
equivalence engine over EQY's alternative strategies (e.g. `miter`); `depth`
bounds how many clock cycles the SAT solver unrolls sequential logic before
concluding equivalence — set to 5 by default in `run_eqy.py`, deep enough to
catch a pipelining edit's extra latency stage without unrolling so deep that
every check becomes slow.

```python
env["PATH"] = yosys_bin_dir + ":" + str(Path(eqy_exe).parent) + ":" + env.get("PATH", "")
```
EQY internally shells out to `yosys` by bare name (not a full path) —
this line ensures the *specific* Yosys build this project uses
(`tools/install/yosys/bin`) is the one EQY finds first on `PATH`, rather
than whatever `yosys` (if any) happens to be first in the ambient shell
environment. Skipping this is a realistic way to get subtly wrong or
version-mismatched equivalence results in an environment with multiple
Yosys installs.

```python
def classify(proc):
    log = proc.stdout + proc.stderr
    if re.search(r"Successfully proved designs? equivalent", log):
        return True, "PROVED_EQUIVALENT"
    if re.search(r"Failed to prove equivalence", log) or proc.returncode not in (0,):
        return False, "NOT_EQUIVALENT_OR_ERROR"
    return False, "AMBIGUOUS_OUTPUT"
```
Three-way classification, fail-closed default — full rationale in Chapter 9.
Note `proc.returncode not in (0,)` is checked as an *additional* rejection
condition alongside the negative-proof-string match, not instead of it — a
nonzero exit code with no matching "failed" string (e.g. a crash) is still
correctly rejected.

### D.6 — `rtl_hierarchy.py` (complete, Chapter 16)

```python
inst_re = re.compile(r"^\s*([A-Za-z_]\w*)\s+(?:#\s*\([^;]*?\)\s*)?([A-Za-z_]\w*)\s*\(", re.MULTILINE)
```
Matches `ModuleType instance_name (` optionally preceded by a parameter
override block `#(...)` — the `(?:...)?` non-capturing group makes the
parameter-override syntax optional so both `foo bar (...)` and
`foo #(.W(8)) bar (...)` match identically, capturing `ModuleType` and
`instance_name` in groups 1 and 2 regardless of which form is used. This
regex is deliberately conservative: any instantiation syntax it doesn't
recognize (unusual line breaks between the type and the parameter block,
for instance) is simply invisible to the localizer, which is why Chapter 20
lists "unrecognized instantiation syntax" as a real, expected failure mode
rather than a hypothetical one.

```python
def resolve_deepest_module(top_module, instance_map, path_components):
    current_module = top_module
    for comp in path_components:
        instances = instance_map.get(current_module, {})
        if comp in instances:
            current_module = instances[comp]
        else:
            break
    return current_module
```
A simple hierarchy walk: start at the top module, and for each path
component (an instance name), look up which module type that instance is
inside the *current* module's own instance map; if a component isn't found,
stop and return whatever module was resolved so far, rather than raising —
this is what lets `localize_edit_target` gracefully fall back to a partial
or top-level match instead of crashing on any unresolvable path segment
(e.g. a leaf standard-cell name that was never itself a parsed RTL module).

### D.7 — `llm_loop.py` main loop, block by block

Already covered in full depth across Chapters 12–16; this entry is a
cross-reference index rather than a repeat: environment/API setup (Chapter
14, "On API cost" and the `--mock` discussion), the per-edit pre-check
(Chapter 12, "Why every edit is checked against its own predecessor"), the
synth-retry block (Chapter 13, full listing), edit localization (Chapter
16), the LLM call and mock fallback (Chapter 14), and the EQY→synth→STA→
accept/reject sequence (Chapter 15, full listing) together comprise the
entirety of `main()`. There is no logic in this file not already traced to
one of those chapters.

## E. Sample Reports — What Each Tool's Output Actually Looks Like

This book cannot embed literal screenshots (it is a Markdown/text document,
generated and read in a terminal-and-editor workflow, not a GUI tool), so
this appendix does the next best thing: verbatim, real captures of each
report format you will actually see on your screen, exactly as they render,
with an inline "what to look for" note after each one. Treat each block
below as a figure.

**Figure E.1 — `run_synth.py` stderr, a successful run**
```
Wrote artifacts/synth/nebula_soc_v4.json -- 57443 cells, area=198532.4
```
*What to look for:* the cell count and area are the two numbers that should
move (usually down, for a good optimization; sometimes up, if a fix like
Chapter 10's `async_fifo` correction genuinely added logic) between a
before/after pair. A run that silently prints far fewer cells than expected
for the design's known scale is a stronger signal of a broken synthesis run
than any error text — always sanity-check this number against the design's
last known-good cell count.

**Figure E.2 — `run_synth.py` stderr, a failed run**
```
SYNTH FAILED (rc=2) -- see artifacts/synth/bad_run.json
```
*What to look for:* the JSON file still gets written on failure (`"ok":
false`, plus an `"error"` field with the tail of Yosys's own stdout/stderr)
— always open that file rather than trying to re-derive the failure from
this one-line stderr summary; Yosys's own error text (e.g. a Verilog syntax
error with file/line) is inside it.

**Figure E.3 — `run_sta.py` stderr, clean design**
```
Wrote artifacts/sta_nebula_soc_v4b.json -- 124 paths, 0 violated
Worst: u_crc0/_3052_ -> u_crc0/_1981_ slack=0.3312 (MET)
```
*What to look for:* `0 violated` is the number that matters most; the
`Worst` line is your safety margin even on a clean run — small worst-case
positive slack (as here, 0.33 ns) means the design is close to its limit,
not comfortably closed, and should raise the same caution as a much larger
`--group-count` next run to make sure a nearby second-worst path isn't about
to become the new worst under a slightly different edit.

**Figure E.4 — `run_sta.py` stderr, violations present**
```
Wrote artifacts/sta_nebula_soc_v4.json -- 134 paths, 10 violated
Worst: rst2_n -> u_fifo2/_1358_ slack=-0.849 (VIOLATED) (max, div_clk2)
```
*What to look for:* the endpoint and path group tell you immediately which
clock domain to look at first in the full report; a *startpoint* that is a
reset or control port (as here, `rst2_n`) rather than a normal data
register is itself a strong hint to go check the SDC file for a
misclassified port before assuming the RTL is at fault — this exact report
line is what led directly to Chapter 11's `set_input_delay` fix.

**Figure E.5 — a single parsed path, as JSON (`sta_*.json`, one array
element)**
```json
{
  "path_group": "div_clk2",
  "path_type": "max",
  "startpoint": "rst2_n",
  "endpoint": "u_fifo2/_1358_",
  "status": "VIOLATED",
  "slack": -0.849,
  "data_arrival_time": 3.201,
  "data_required_time": 2.352,
  "num_cells": 6,
  "cells": [
    {"pin": "rst2_n", "cell": "PORT", "delay": 0.0, "time": 0.0},
    {"pin": "u_fifo2/_44_/Y", "cell": "sky130_fd_sc_hd__buf_2", "delay": 0.412, "time": 0.412}
  ]
}
```
*What to look for:* this is the exact structure `worst_path_summary()`
(Chapter 6, Chapter 14) formats back into text for the LLM — reading this
JSON directly is the fastest way to debug a suspicious LLM proposal, since
it's literally what the model was shown.

**Figure E.6 — `run_lint.py` stderr, hard warnings present**
```
Wrote artifacts/lint/nebula_soc_baseline.json -- 18 warnings (2 hard: ['UNOPTFLAT'])
```
*What to look for:* the bracketed list is the *distinct set* of hard
warning codes present, not a count — always open the JSON's
`"hard_warnings"` array to see how many distinct *locations* triggered
each code; two `UNOPTFLAT` warnings at two different signals (as in the
real `async_fifo` case, Chapter 10) is a fundamentally different situation
from the same warning printed twice for the same signal.

**Figure E.7 — `run_lint.py` stderr, clean**
```
Wrote artifacts/lint/nebula_soc_postfix2.json -- 12 warnings (0 hard: [])
```
*What to look for:* `0 hard` with a nonzero total warning count is the
expected, correct steady state — do not chase the remaining informational
warnings to zero; Chapter 8 explains why that's not this gate's job.

**Figure E.8 — `run_eqy.py` stderr, proved equivalent**
```
Wrote artifacts/eqy/nebula_soc_v4_identity.json -- equivalent=True (PROVED_EQUIVALENT)
```

**Figure E.9 — `run_eqy.py` stderr, rejected**
```
Wrote artifacts/eqy/edit_0007_r0.json -- equivalent=False (NOT_EQUIVALENT_OR_ERROR)
```
*What to look for:* when this happens on a real (non-mock) LLM edit, open
the JSON's `"log_tail"` field (last 15 lines of EQY's own log) before
assuming the LLM's edit was simply wrong — a SAT solver timeout at the
configured `--depth`, or a genuine parse error in the LLM's returned
Verilog, both also land here, and each implies a different next step
(increase depth vs. reject the edit vs. fix a prompt issue).

**Figure E.10 — `llm_loop.py` stderr, one full edit cycle (real, annotated)**
```
=== Stage 8 loop start: run_id=nebsoc_run1 mock=False ===
[edit 0] pre-edit: cells=57443 area=198532.4 wns=-0.82 violated=1/134
[edit 0] synth-retry strategy=retime: wns -0.82 -> -0.71 violated 1 -> 1
[edit 0] synth-retry strategy=timing_driven: wns -0.82 -> -0.55 violated 1 -> 1
[edit 0] localized worst path to module: compute_pipeline
[edit 0] retry 0: LLM proposed technique=pipelining rationale='Insert a pipeline
  register between the multiply stage and the adder tree to break the
  single-cycle multiply-then-sum path into two cycles.'
[edit 0] retry 0: EQY OK, wns -0.82 -> 0.14, violated 1 -> 0, improved=True
=== Stage 8 loop end: final RTL = artifacts/llm_loop/nebsoc_run1/nebsoc_run1_e0_r0_candidate.v ===
```
*What to look for, line by line:* the pre-edit line is your baseline for
this iteration; the two synth-retry lines show neither cheap remap closed
timing on their own (wns improved but stayed negative both times) — correctly
falling through to an LLM edit; the localization line confirms the edit
landed on the actual timing-critical module (Chapter 10) rather than the
top-level wrapper; the technique + rationale line is your primary audit
trail for "why did the model do this"; and the final `EQY OK ... improved=True`
line is the single line that matters most for trusting the result — note it
reports *both* WNS and violated-count deltas together, exactly the Chapter
15 fix that closed the regression gap.

---

*End of book. This document describes a real, running pipeline as of the
verification pass that produced 0 violated paths on `nebula_soc` — Chapter
11's final state. If you extend this flow to a new design and hit something
not covered in Chapter 20, the right instinct, per this whole book, is the
same one that found the `async_fifo` bug: don't dismiss the anomaly, trace
it to a specific physical or structural cause, and write down why the fix
is correct before moving on.*
