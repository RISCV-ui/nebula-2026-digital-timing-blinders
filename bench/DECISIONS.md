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

## G1c datapath abstraction (2026-09-09)

**Decision.** G1c proves the stream contract against surrogate arithmetic
leaves (`fp4_mul`, `fp8_adder`) rather than the real ones, and the loop's
default bound moved from 10 to 16.

**Why.** Measured, the gate did not work before this. The correct candidate
proved in 5.6 s at bound 4, 362 s at bound 6, and not at all in 2400 s at
bound 10. The buggy candidate -- a pipeline missing its drain term -- was not
reachable at bounds 4 or 5 and was only caught at bound 10. There was no bound
at which G1c both accepted what it should and rejected what it should. Tuning
the bound down for speed would have produced a gate that reports a proof and
passes the bug.

The five stream properties are control properties; none of them mentions
floating-point arithmetic. Abstracting the leaves identically on both sides
preserves what P3 asserts and removes what the solver was spending its time
on. With it: bound 16 proves the correct candidate in 22.5 s and rejects the
buggy one in 1.2 s.

**Cost, stated.** A candidate that changes the arithmetic itself passes G1c.
G1 covers that case directly and cheaply on the combinational leaf
(`fp8_adder`, 1.0 s). The argument is the pair of gates, not either one.

**Surrogates are non-commutative** so a transform that reassociated the adder
tree cannot pass abstractly while failing concretely.

## FSM re-encoding, and the reset-align wrapper it needed (2026-09-09)

**Decision.** Add `fsm_encode` to the transform catalog, and add a
`--reset-align PORT` mode to G1 without which it could never pass.

**Why the transform.** The problem statement names four techniques:
pipelining, logic restructuring, retiming and FSM optimization. The catalog
had the first three plus `duplicate_driver`, so the fourth was simply absent.
A judge reading the four techniques against our catalog would have found three.

**Why the wrapper.** Measured, not assumed. G1 builds its miter with
`sat -seq ... -set-init-zero`, so both halves start from all-zeros. All-zeros
means *different things under different encodings*: `read_buffer_i_cache`
encodes idle as `2'b01`, so the golden starts in a code it does not own and is
rescued one cycle later by its own `default` arm, while the binary re-encoding,
whose idle is `1'b0`, starts legitimately idle. They disagree on cycle 0 for a
reason that has nothing to do with the transform. A correct re-encoding was
rejected in 0.3 s.

The wrapper holds the module's reset asserted for exactly one cycle on **both**
halves and masks the outputs while it is, so each machine lands in its own
reset state and the encodings correspond from cycle 1 on. Same wrapper on both
sides: nothing is assumed about one half that is not assumed about the other.

| candidate | without alignment | with alignment |
|---|---|---|
| correct binary re-encode | NOT_EQUIVALENT, 0.3 s | **EQUIVALENT, 5.8 s** |
| re-encode with the reset assignment left on the old literal | — | **NOT_EQUIVALENT, 0.5 s** |

The second row is the one that matters: the wrapper does not make G1 permissive.

**A subtlety worth recording.** The wrapper's `__started` flag must be declared
`reg __started = 1'b0;`. Without the initialiser, `opt` sees a flop whose D
input is constant 1 and whose init is unset, treats the init as a don't-care,
and folds the register to constant 1 — long before `sat -set-init-zero` runs.
Reset is then never asserted and the wrapper silently does nothing. That is
exactly what happened on the first attempt, and the symptom was identical to
having no wrapper at all.

**Stated limits.**

* Active-high synchronous resets only (`RESET_NAMES`). On an active-low port
  the wrapper's `(rst) || !__started` term *releases* reset instead of
  asserting it, so it would do the opposite of its job in silence. A module
  without a matching reset gets `ERROR`, not a proof. This benchmark is
  uniformly active-high.
* Reset alignment and a latency change are refused in combination. `fsm_encode`
  preserves latency, so the case does not arise, and emitting a wrapper whose
  proven statement nobody can state is worse than refusing.
* An FSM has loops in its state graph, so G1 returns a **bounded** proof here
  (depth 12), not the complete one it gives feed-forward logic. Reported as
  `proof: bounded`, which is what it is.

## The observability probe, and the false accept it closes (2026-09-09)

**Decision.** A bounded G1 proof no longer reports EQUIVALENT on its own. When
the depth is the fixed bounded depth of 12 -- the branch that is not a complete
proof -- `g1_equiv.py --observe` first proves that some input of the module
reaches an output inside that window. If it cannot, the verdict is
INCONCLUSIVE, not EQUIVALENT. `loop.gate1` passes `--observe` on exactly that
branch.

**Why.** `retime` and `duplicate_driver` had never been exercised in either
direction -- 0 proposals anywhere in the artifacts -- which is the same blind
spot that hid the `fsm_encode` problem. Building a real retime of
`fp4_dot_unit` (adder level 1 moved back across the stage-0 register boundary,
so stage 0 holds four sums instead of eight products; latency and stage count
unchanged, register count 12 -> 8) and a deliberately mis-wired copy of it
produced this:

| depth | correct retime | mis-wired retime |
|---|---|---|
| 4 | EQUIVALENT 2.7 s | **EQUIVALENT 2.6 s** |
| 5 | TIMEOUT | NOT_EQUIVALENT 5.4 s, counterexample at cycle 5 |
| 12 | TIMEOUT 300 s | -- |

The bold cell is a false accept. `fp4_dot_unit`'s output sits four flops behind
its inputs, so in a four-cycle window both halves of the miter are still
sitting on their reset values and the solver proves them equal without having
compared anything the edit touched. The verdict flipped on the depth alone.

The probe is golden against golden with one input bit inverted, run at the same
depth through the same passes. A model found means the flip reached an output
inside the window. No model found means no input can, and the proof was
vacuous. Inverting is used rather than tying low because a tie only differs
when the solver picks a 1 there, while an inversion differs on every vector.
Ports are tried widest first, three at most: a wide data port is what a
datapath consumes, and a narrow control bit can be legitimately unused.

**Limits.** The probe answers "yes" / "no" / "unknown"; on a timeout it says
unknown, the verdict stands, and the detail field records that the window was
not established. It is not run on the two complete branches -- depth 1 on a
stateless module is the whole theorem, and latency+2 on a feed-forward
insertion derives its window from the latency -- so it costs nothing on the
common case.

**What the retime experiment also settled.** The hypothesis going in was that
`retime` carried the same zero-init encoding bug as `fsm_encode`, since
retiming changes what each register holds. It does not: the correct retime
proves EQUIVALENT from an all-zero start at depth 4, because the reset values
still correspond. What it hit instead was the depth, and a correct retime of
`fp4_dot_unit` is not provable inside the budget at all -- TIMEOUT at depth 5
and at depth 12. That is reported as a rejection, which is the right side to
fail on.

`duplicate_driver` was checked the same way on `branch_comp_decoder` (the two
opcode comparators duplicated per output bit): correct copy EQUIVALENT, one
copy given the wrong opcode NOT_EQUIVALENT, both in 0.0 s at depth 1 with a
complete proof. Purely combinational duplication has no start-state question
at all, which is why it was the low-risk one.

## The cut-point file that failed EQY before it started (2026-09-09)

**Decision.** `scripts/eqy_hier.py` writes into `cutpoints.v` only the proved
*children* of the module about to be checked, not every module proved so far.

**What it fixed.** The accumulated file was read on both sides with
`read_verilog -lib`, which turns each entry into a blackbox declaration. `prep
-top <module>` then removes unused *real* modules but keeps unused blackboxes,
so the gold design for a leaf module arrived at EQY carrying nineteen modules
it does not instantiate — `alu`, `arbiter`, `fp4_mul`, `clk_gate` and the rest
of the proved list. The gate design, built from the netlist, had none of them,
because there they were real modules and `prep` pruned them. EQY compared the
two module lists and stopped:

```
combine: ERROR: Unmatched module exists in gold that does not exist in gate.
         This should not happen. Please report this bug.
```

Both EQY passes died there, on every module, and the wrapper fell through to
the plain Yosys `equiv_induct` miter — which closes combinational logic and
does not close sequential logic. That is the whole shape of the sweep's
results, over the 44 modules the sweep reached before it was stopped: **15 of
15 combinational modules proved, 8 of 29 sequential ones, and not one
combinational module failed.** The split is on state, not on size or on
clocked-block count -- eleven of the failures have a single `always
@(posedge)` block, exactly like the eight that passed. It read like a solver
limit and was a module-list mismatch three steps upstream.

Measured on `mem_axi_slave` (36 unproven cells) with the file cut back to the
macro stubs alone, EQY combines and runs for the first time:

| pass | before | after |
|---|---|---|
| partitioned | `Failed to combine designs` | `NOT_EQUIVALENT` (partition cut point — see the false-counterexample note above) |
| merged | `Failed to combine designs` | `UNPROVEN_EQY (equivalence unknown) at depth 5` |
| yosys-equiv | `UNPROVEN (36 cells)` | `UNPROVEN (36 cells)` |

The verdict is still not a proof, but the reason has moved from "the tool
refused to start" to "the bound is too shallow", which is a question depth can
answer and the previous one was not.

**Second thing it fixed.** The file was a function of the entire pass/fail
history above a module, so an unrelated module changing verdict changed the
design every later module was checked against. Two modules that passed the
previous sweep failed the next one for exactly that reason —
`i_rom_32x256` and `id_memory_256x64_wrap`, same pass, same depth, different
accumulated stub file. Boxing only children makes a module's check depend on
its own subtree and nothing else, which is what the compositional soundness
argument claims in the first place.

**Cost.** A module now sees fewer cut points, so parents of unproven children
stay expensive. That was already true by design; the change only stops the
saving from being taken where it was never justified.

## Bind every proposal to its requested target, and reject no-op accepts (2026-09-11)

**Decision.** `loop.py` records the module returned by the model separately
from the requested target and rejects the proposal unless they match. A
derived parent proposal may still rewrite children through `submodules`, but
the parent named in the prompt must remain the primary module. After applying
the proposal to a candidate tree, the loop also rejects a byte-identical tree
before running formal verification.

**Why.** The original Nemotron Ultra bake-off recorded two acceptances, but
the second record targeted `fp4_dot_unit` while its proposal and G1 result both
named `fp8_adder`. In the fresh signoff-target rerun the second candidate was
byte-identical to the first accepted candidate. Formal equivalence correctly
proved that identical input, and the loop counted a second acceptance even
though the requested target was untouched. The actual final tree changed only
`fp8_adder.v`.

The historical history files remain unchanged. `bakeoff.py` reconstructs each
accepted candidate snapshot against the preceding working tree and marks this
record `audit`, so the corrected row is **1/7 accepted**, not 2/7. Offline mock
checks cover both failure modes: a wrong primary module and an exact repeat
each stop at `validate` with zero accepts. This check belongs before G1 because
the theorem "unchanged RTL is equivalent" is true but irrelevant to whether
the model improved the requested path.
