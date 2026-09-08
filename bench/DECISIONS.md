# nebula_bench — design decisions

Locked 8 Sep 2026. Deadline 15 Sep 2026, 23:00.

Submission is a 10-12 page report plus a recorded demo video, scored on
coverage of all deliverables, innovation, and thought process. That wording
drives most of what follows: a system that covers every deliverable partially
beats one that covers half of them well, and the reasoning behind a decision
scores as much as the decision.

---

## D1 — The loop

    slice -> LLM -> G1 equivalence -> G2 CDC -> synth -> G3 post-PnR

Cheap gates first. G1 and G2 run on RTL in minutes; a full PnR iteration is
~10 minutes, so only proposals that already passed both are worth placing.

## D2 — Three gates

| gate | checks | on |
|---|---|---|
| G1 | original RTL vs optimized RTL, module by module | RTL |
| G2 | CDC structure intact | RTL |
| G3 | WNS / TNS / area / power / wirelength delta | post-route |

G1 is table stakes. G2 is the differentiator: CDC correctness is not an
equivalence property, so G1 cannot see it. A two-flop synchronizer reduced to
one flop passes G1 and is silicon-broken. G3 is what OpenROAD buys us —
decisions made on routed numbers, not synthesis estimates.

## D3 — Transform catalog v1 (five, no more)

Bounded action space is the point. Five transforms, split by whether they
change latency, because that decides which proof G1 runs.

**Latency-preserving** — plain miter:

- `balance_tree(target, op)` — reassociate a chain of one operator into a
  balanced tree
- `split_mux(target, depth)` — priority/wide mux into a balanced tree
- `duplicate_driver(net, n)` — split a high-fanout net across n drivers
- `precompute_mux_input(target)` — push logic ahead of a mux select

**Latency-changing** — N-delayed miter:

- `pipeline(target, N)` — insert N register stages in a combinational path

### Dropped: `recode_fsm`

State re-encoding is not provable by structural equivalence induction —
internal states stop corresponding, which is exactly the failure class that
produced our six UNPROVEN modules on the previous design. Proving it needs an
IO-only bisimulation, which is not a seven-day build. Listed as future work in
the report, with the reason.

## D4 — How a transform is applied

**Decision: the LLM writes the replacement RTL; the gates verify the claim.**

The earlier plan was for the LLM to only select a transform, with deterministic
Python appliers doing the edit. That was wrong for this timeline: five real
Verilog AST rewriters is not a seven-day build, and no parser is set up here.

So the LLM returns a structured proposal:

    {"transform": "balance_tree", "module": "fp4_dot_unit",
     "latency_delta": 0, "params": {...}, "rtl": "<rewritten region>",
     "reason": "..."}

A script splices it in and validates:

- module port list unchanged (structural)
- `latency_delta` must be 0 for a latency-preserving transform
- G1 enforces the latency claim: `latency_delta: 0` is proven by a plain miter,
  `N` by a miter with the golden outputs delayed N flops

The action space stays bounded where it matters — the *claim* is bounded and
machine-checkable, even though the *text* is generated. A proposal that lies
about its transform type or its latency fails G1 by construction.

## D5 — G1 implementation

RTL vs RTL, changed module plus its parent. Yosys:

    miter -equiv -flatten -make_assert -make_outputs
    sat -seq 12 -prove-asserts -set-init-zero -verify

Depth 12. On the previous design, going 10 -> 20 moved nothing: the UNPROVEN
cell counts were identical at both depths, so the failures were
depth-independent and more depth only bought runtime.

Per-module timeout 300 s. TIMEOUT is recorded as its own verdict, never as a
pass. A fast loop matters more than a complete one.

For `latency_delta: N`, the golden side's outputs pass through N flops before
the miter compares them.

## D6 — G2 implementation

Region protection, not full CDC analysis. Buildable, and it catches the real
failure.

1. Map clock domains once, from the SDC and the `always @(posedge ...)` in each
   module.
2. Mark crossings: written in domain A, read in domain B.
3. Freeze the NO-TOUCH set — everything inside `asynchronous_fifo_gen`, every
   two-flop synchronizer chain, all gray-code pointer logic.
4. After a transform, check: NO-TOUCH untouched; synchronizer depth unchanged;
   no combinational logic inserted between synchronizer flops; no new crossing
   created.

## D7 — Which paths, and the demo moment

Top 20 distinct violating endpoints. The two worst are already known:

    clk_s5  dot_0/fifo_timer_r/mem[*][6]     38.31 ns vs 11.97  -- inside a FIFO
    clk1    d_cache_0/i_mem_2/mem[0][*]/DE   22.91 ns vs  8.60  -- cache write enable

The worst path in the design sits inside a CDC structure. Any pipelining there
passes G1 and fails G2. That is the demo: a proposal that formal equivalence
accepts and the CDC gate rejects.

## D8 — LLM backend

OpenRouter, one key, model as config. Frontier Claude first. Extended thinking
on — the model has to trace a path through logic. Prompt caching on; the
catalog and instructions are fixed across every call.

Day 4: same 20 paths, three models, one loop, accept-rate measured. The loop is
its own benchmark, so the model is chosen from data rather than argued about,
and the comparison is a report figure.

## D9 — History store

One JSON line per proposal: path signature, transform, params, three gate
verdicts, PPA deltas. Feeds the retrieval-augmented prompt and every figure in
the report.

## D10 — Out of scope, deliberately

- **LLM tuning PnR knobs** (density, die area, halo). That is hyperparameter
  search, where random or Bayesian search beats an LLM at lower cost, and the
  topic is *RTL* enhancement. Using PnR as a signal source and a measurement
  is on-topic; using an LLM as a knob-turner is not.
- **`recode_fsm`** — see D3.
- **SDC agent** (real path vs false/multicycle) — architecture in the report,
  built only if the core lands early.
- **Congestion -> RTL** — the strongest stretch goal. Needs congestion tiles
  resolved to net names to RTL modules. Day 5 if the core is done.

## D11 — Cell count

113,036 standard cells against the ~50K in the benchmark spec. Not shrinking
further: the criteria list coverage, innovation and thought process, and a day
spent on cell count buys none of them. Documented honestly in the report
instead. A mentor question is pending on whether ~50K is a hard requirement.

## D12 — Proof depth for latency-changing transforms is latency + 2, and that is complete

The first attempt at proving the pipelined `fp4_dot_unit` ran `sat -seq 12`
and returned nothing after 1847 s. Depth 12 was inherited from the
latency-preserving case, where it was a bounded check on a design with
feedback. A register-insertion transform on a feed-forward datapath has no
feedback at all: once the pipe has filled, every output cycle is a fresh
function of that cycle's inputs. So `latency + 2` is not a weaker bound, it
is the point past which further cycles repeat a case already covered — the
proof is complete for this transform class, not bounded.

The same run at depth 4 returned EQUIVALENT in 164 s.

The gate does not infer this. A proposal declares `latency_delta`, and the
loop picks `latency_delta + 2` for transforms the catalog marks
feed-forward; anything else keeps the depth-12 bounded check and is reported
as bounded.

## D13 — The miter is opt_merge'd before the solver sees it

Both halves of the miter are elaborated from the same RTL, so every cell the
transform did not touch appears twice, structurally identical and driven by
the same primary inputs. `opt -fast` does not run `opt_merge`, so the solver
was being handed eight duplicated FP multipliers and a duplicated adder level
that could never differ. `opt_expr; opt_merge -share_all; opt -full` deletes
them. This and D12 together are the whole 1847 s -> 164 s difference; neither
weakens the claim.

## D14 — G2 is a regression gate, not an audit of the baseline

`soc_top` already crosses `mem_hit` from `clk_s8` into `clk1` through a
single flop. It feeds `soc_obs`, an XOR accumulator built for observability
that drives no control logic. It is a real unsynchronised crossing and it is
the design's own choice.

An absolute rule ("every crossing must have depth >= 2") fails the golden
design against itself, which would make every candidate fail for a reason no
candidate caused. So G2 compares candidate against golden: a crossing that
is new, that lost synchroniser depth, or that gained logic between stages is
a FAIL; a pre-existing weakness is reported as an inherited warning and the
gate passes. Absolute checks still apply at full strength to crossings the
candidate introduced.

## D15 — A crossing is identified by its receiving flop, not just its signal

Duplicating a driver is a legitimate catalogue transform: it cuts load on a
high-fanout net and shortens the path. Applied to the input of a
synchroniser it is a silicon bug. Two flops sampling the same asynchronous
signal can resolve metastability in opposite directions on the same edge, so
the two copies disagree and the reader sees a value the writer never sent.

The two circuits are logically identical by construction, so no equivalence
check can separate them — G1 passes it. G2 sees it only because a crossing
is keyed on `(signal, source domain, destination domain, receiving flop)`;
keyed on the signal alone the duplicate collapses onto the original and
disappears.

This is the concrete case behind the claim that equivalence is not
sufficient. It is not hypothetical: the worst path in this design starts and
ends inside `asynchronous_fifo_gen`, so it is exactly the module a
path-directed optimiser reaches for first.

## D16 — a stateless module gets a complete proof at depth 1, not a bounded one at depth 12

G1's default is `sat -seq 12`, and its verdict is honestly reported as
"equivalent for twelve cycles from a zero initial state". D12 already carved
out one exception: a feed-forward register insertion needs only `latency + 2`,
and that is complete rather than bounded.

There is a second, cheaper exception that was being missed. A module holding no
state is a pure function of its inputs. One cycle of the miter therefore covers
every distinct case there is — two combinational circuits that agree on all
inputs for a single cycle agree forever — so depth beyond 1 buys nothing at all,
and the verdict is a *complete* proof of equivalence.

This is not a small bookkeeping point. `fp8_adder` is the module carrying 85.7%
of the worst path, it is purely combinational, and it is where the optimizer
spends most of its attempts. Under the old rule its proofs were labelled
bounded and cost 6.3s; under this rule they are complete and cost 0.6s. The
report can claim a complete equivalence proof for the module that matters most,
which is a materially different claim from a twelve-cycle check.

Two guards on it:

* **Both sides must be stateless.** If the transform introduced a flop, the
  miter is a sequential problem again and the depth-1 argument evaporates.
* **The question is asked of the elaborated design, not the source.** Grepping
  for `always @(posedge ...)` misses a latch accidentally inferred by an
  incomplete `always @(*)`, and a latch is state however the source reads.
  `stateless()` runs `proc; opt_clean; stat` and looks for `$dff`/`$dlatch`/
  `$mem` cells, because Yosys has already settled the question by the time it
  emits cells. A yosys failure returns False: when completeness cannot be
  established, it is not claimed.

The G1 record now carries `proof: combinational | feed-forward | bounded`
alongside `complete`, so every verdict in the report says which of the three
arguments it rests on.

## D17 — a latency change is checked at the parent, not just at the module

G1 proves the pipelined module correct against its own outputs delayed by N.
That proof is sound and it is not enough, because it never asks the only
question that matters to the chip: is anybody upstream willing to wait N
cycles?

The loop produced the case itself. Given the reset rule from D16 and a
summarised counterexample, Gemini pipelined `fp4_dot_unit` into four clean
stages — no resets on the datapath registers, textbook levelling of the adder
tree — and G1 passed it. The module is genuinely correct. Its parent is not:

```verilog
fp4_dot_unit fp4_dot_0(clk_2, rst_2, va, vb, dot_out);
assign fifo_data_write = dot_out;
assign w_en   = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);
assign r_en_1 = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);
```

The same cycle that pops the operands out of the two input FIFOs pushes
`dot_out` into the result FIFO. That was correct while the dot unit was
combinational. With four stages inside it, `w_en` now stores whatever the
pipeline is holding — the product of operands popped four cycles earlier, or
reset garbage. Equivalent module, broken SoC.

The check for this turns out to be the same machinery one level up, with the
delay wrapper removed: build the parent over the original child and over the
transformed child, and miter the two parents against each other with
`latency 0`. The parent is not supposed to be late; it is supposed to be
identical. A parent that absorbs the latency behind a handshake or a valid
chain passes; a parent that assumed the old timing fails, and the
counterexample is the cycle where the SoC diverges.

`g1b_contract.py` does exactly this and returned `CONTRACT_BROKEN` on
`axi_lite_dot` in 18.8s. The loop now runs it whenever `latency_delta != 0`
and feeds the failure back as its own kind of repair prompt — one that asks
for a latency-preserving rewrite rather than another pipeline — because unlike
every other gate, a G1b failure is not a bug in the model's edit. The edit is
correct. The contract around it is what broke.

Cost is paid only where it is owed: a latency-preserving transform cannot
violate a timing contract it did not touch, so G1b is skipped for those.

## D18 — the slicer says which lever closes each path, and the LLM only sees `rtl`

Not every violation is an RTL problem, and spending a model call plus an
equivalence proof on one the synthesiser was going to fix by upsizing a cell is
pure waste. So the slicer now labels every path `none`, `gate`, or `rtl`, with
the arithmetic attached.

The bound is `GATE_HEADROOM = 0.20` of the path's own combinational delay —
what sizing, buffering, cell swaps and a tighter placement can plausibly
recover. It is deliberately the optimistic end of the published range for an
open PDK, and sky130hd is single-Vt, so the usual escape hatch of a low-Vt swap
does not exist here. Erring high means the selector prefers the cheap lever and
only escalates when even an optimistic gate-level bound falls short.

On this design the split is stark. Eleven of twelve targets are `none` — they
already meet timing, and optimising them changes no reported number. `clk_s5`
needs 12.5 ns and takes 32.196 ns: a 19.7 ns gap against a gate-level reach of
roughly 6.4 ns, three times what any sizing pass can deliver, with 85.7% of the
path inside three chained `fp8_adder` instances. That is a structural problem
and the label says so.

One veto overrides the arithmetic: a path shorter than four stages goes back to
`gate` however bad its slack, because a deep cell or a long wire has no
structure to restructure and pipelining it would buy back a register's clk-to-q
and setup for nothing.

The practical effect is the call budget. Twelve targets become two calls, and
the report can state which paths were deliberately *not* sent to a model, with
the number that decided it.

## D19 — clock structure gets its own gate, because neither of the other two can see it

Two tools guard this flow and there is a class of bug that is invisible to
both.

Equivalence checking cannot see it. A combinational clock mux and a
flop-based one compute the same function of `sel`. They differ only in what
the waveform does *between* the cycles a solver samples, and a SAT miter has
no notion of a pulse too short to clock a flop. The two structures are
equivalent, and one of them destroys the chip.

STA cannot see it either. OpenSTA is told `clk_out` is a clock, believes it,
and reports timing against a clean idealised waveform. The tool is not wrong;
nobody asked it whether that waveform is producible.

`clockcheck.py` asks. It is structural and cheap: find every one-bit net the
module treats as a clock, keep the ones driven combinationally (a clock out of
a flop is glitch-free by construction and is skipped), and classify the shape.

Run over the 55-module baseline it returns exactly two findings and no false
positives:

```
GLITCHY_MUX    clk_div_mux.clk_out
    selected combinationally among clk, clk_div2, clk_div4, clk_div8
GLITCHY_GATE   clk_gate.clk_out
    clk_out = clk_in & clk_en, no low-phase latch on the enable
```

Both are real, both are in the benchmark design as written, and `clk_div_mux`
is slicer target #8 with 100% path share — the optimizer reaches it.

Getting to zero false positives took two rules beyond the name. A clock net
must be **one bit wide**: `soc_top` holds `clkcfg_rdata`, `clk_config_reg` and
`clk_en_reg` — clock-*configuration* registers, all buses — and a name-only
rule reported the AXI read mux over them as a glitchy clock mux. And a name
ending `_en`, `_sel`, `_gate`, `_valid` or `_req` is what *gates* a clock, not
a clock: without that, every clock gate in the design reads as a two-source
mux.

The checker also has to recognise the *fix*, or it can only ever say no.
Rewriting `clk_gate` in the standard ICG form —

```verilog
always @(*) if (!clk_in) en_lat = clk_en;
assign clk_out = clk_in & en_lat;
```

— flips it to `SAFE_ICG`, and all three regression directions behave: golden →
fixed passes, fixed → golden fails, and the untouched `clk_div_mux` finding is
reported as inherited rather than blamed on the candidate.

The loop runs it in regression mode next to G2, with the same stance G2 takes
on crossings and for the same reason: the baseline already contains two of
these, and a gate that failed every candidate for a bug the candidate did not
introduce would be switched off within a day. A transform may inherit a
glitchy structure. It may not create one.

What the checker does not claim: it recognises the shapes it has been taught.
An unfamiliar hand-built gate reads `UNRECOGNISED`, not `GLITCHY`. Recognising
a safe form proves nothing; failing to recognise one is a prompt to go look.

## D20 — where the model judges, its answer is advisory and carries no verdict

G2 can prove a one-bit crossing has two flops and no combinational logic
between them. On a bus it cannot, and it warns instead: the pointers of
`asynchronous_fifo_gen` come back "multi-bit; gray or handshake encoding
assumed, not proven". That warning is honest and useless on its own — two flops
per bit is not a synchronizer for a bus, since the bits resolve independently
and a value in flight can be sampled as a combination that never existed on the
source side. Safety comes from the *encoding*, which is not a structure a
depth-counting checker can see.

`cdc_classify.py` classifies the encoding in two layers, and the line between
them is the decision:

- **structural** — a gray signature (`x ^ (x >> 1)`, or the concatenation
  spelling `x ^ {1'b0, x[msb:1]}` this design actually uses), a dual-clock FIFO
  instantiation, a `req`/`ack` pair. Sound, no model, reported with its
  evidence.
- **model** — everything else, recorded `basis: "model", advisory: true`, with
  **no verdict field**. It gates nothing and never appears in a pass/fail line.

This is deliberately the inverse of how the model is used everywhere else in
the flow. There the LLM proposes and formal tools judge; here the model would
be judging, and a model that says "this is gray-coded" has produced a
hypothesis for a human to check, not a guarantee. A CDC bug waved through
because a model was confident is exactly the failure mode this project exists
to argue against, so the output format makes it structurally impossible for an
advisory classification to be read as a verdict.

Matching is against the driver of the signal in question, not against any gray
conversion anywhere in the module: a FIFO holds two pointers and crediting the
wrong one is precisely the mistake the check is meant to prevent.
