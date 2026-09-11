# Nebula 2026 — Digital Track: what was built, and how

Team **Timing Blinders** — Shubhanshu Shivhare, Nagarjun BV (IIT Bombay).
Topic: *Constraint Optimization through RTL Enhancement Using Generative AI*.

Working notes, written 10 September 2026. This is a record of the system as it
actually stands in the repo, including the parts that do not work. Numbers here
were read out of the artifacts, not remembered.

---

## 1. The one-paragraph version

An LLM is given a critical path from a real routed design and asked to rewrite
the RTL that causes it. It is not trusted. Every proposal passes through a
chain of gates — structural validation, formal equivalence, CDC structure,
generated-clock safety — and only then is the edit folded into a working tree.
The frozen input RTL is never written to. On the final repaired and routed
candidate, the loop moved the target `clk_s5` domain from 25.65 MHz to
89.09 MHz (3.47x), while cell area fell 1.60%. Formal gates proved the accepted
leaves and the declared stream-latency contract; the ordinary parent miter also
records why the result is not cycle-by-cycle equivalent.

The differentiator against the cited literature is the gate chain, and
specifically the two gates that are *not* equivalence checks: an edit can be
provably equivalent and still broken in silicon.

---

## 2. The benchmark design

Not a toy. `bench/rtl/` holds **55 Verilog modules** — a RISC-V SoC subsystem:
5-stage pipelined core, L1 I/D caches, AXI-lite interconnect with 8 slaves, DMA
controller, UART, GPIO, timer, interrupt controller, CSR file, branch
predictor, plus an FP4/FP8 dot-product accelerator.

Meets the required benchmark shape:

| requirement | what the design has |
|---|---|
| 5 independent async master clock domains | `clk1`–`clk5` |
| ≥1 generated clock per master | `clk_s1_gate`, `clk_s2_gate`, `clk_s4_gate`, `clk_s5_gate` |
| clock domain crossings | async FIFOs + 2-flop synchronizers between domains |
| clock dividers at multiple ratios | `clk_div_mux.v`, `clk_gate.v` |
| ~50k standard cells | **480,545 instances** post-route, sky130hd |

Constraints in `bench/constraints/nebula.sdc`. PDK is sky130hd throughout, so
every number is reproducible on open tools.

**The accelerator is where the interesting timing sits.** `fp8_adder` →
`fp4_dot_unit` → `axi_lite_dot` on `clk_s5` is the worst path in the design and
is what the loop actually attacked.

---

## 3. Flow, end to end

```
bench/rtl  (frozen, never edited)
   |
   v
OpenROAD-flow-scripts  --> routed ODB (sky130hd)
   |
   v
run_sta.py / OpenSTA   --> ranked critical paths, JSON
   |
   v
hierarchy.py + slicer.py
   |    turns a gate-level instance path back into an RTL file
   v
llm.py  --> proposal: one of five allowed transforms, as JSON
   |
   v
GATE CHAIN  (section 4)
   |
   +-- reject --> history.jsonl --> quoted back to the model, retry x2
   |
   +-- accept --> working RTL tree
                     |
                     v
                  ORFS re-run (G3, batched) --> metrics.py, fmax.py
```

### The bridge that made this possible at all

Yosys and OpenROAD invent their own names. A critical path comes back as
`_1370_`, `place25344` — strings that exist nowhere in the source. Without a
way to map an instance path back to a file and a line, the LLM has nothing to
edit. `hierarchy.py` + `slicer.py` are that bridge, and they were more work
than the LLM call itself.

`slicer.py` also decides *which* paths are worth a call: on the baseline it
found 7 candidate targets and cut them to **3 worth spending a token on**
(negative slack, RTL-fixable lever, parents included so a pipeline change can
be propagated).

---

## 4. The gate chain — the actual contribution

Ordered cheapest-first, because anything a millisecond check can reject must
never reach a ninety-minute one.

| gate | script | question | cost |
|---|---|---|---|
| validate | `transforms.py` | Is it one of the five allowed transforms? Does it parse? | ms |
| G1 | `g1_equiv.py` | Same outputs, every cycle? SAT miter vs the golden module. | s–min |
| G1b | `g1b_contract.py` | A module correct *N cycles later* — will its parent tolerate that? | s–min |
| G1c | `g1c_stream.py` | When the parent is no longer cycle-identical: same output *stream*? | s–min |
| G2 | `g2_cdc.py` | Did the new flop land on a CDC synchronizer stage? | ms |
| G2c | `clockcheck.py` | Are generated clocks still glitch-free? | ms |
| G3 | ORFS + `metrics.py` | Did PPA and Fmax actually improve after real place-and-route? | ~90 min |

**G2 and G2c are the gates no cited paper has.** Both catch edits that are
provably equivalent and still wrong:

- A two-flop synchronizer reduced to one flop is logically equivalent and
  metastability-broken. Equivalence is a statement about logic, not about
  settling time.
- A retimed generated clock can grow a runt pulse. A SAT miter samples at clock
  edges; it cannot see what a waveform does between them.

**G1b exists because of a real failure.** Pipelining a module makes it correct
*N cycles later*, which is only safe if the parent waits. G1 passes it happily.
G1b checks the parent's contract; G1c handles the case where the parent is no
longer cycle-identical and only the output stream can be compared.

### Allowed transforms (bounded action space, by design)

Latency-preserving: `logic_restructure`, `retime`, `fsm_encode`, and
`duplicate_driver`. Latency-changing (needs G1b/G1c): `pipeline`. FSM
re-encoding additionally aligns reset before its bounded miter because the two
encodings need not represent reset with the same raw state bits.

The action space is bounded on purpose. An unconstrained "rewrite this module"
prompt produces edits no gate can classify, and an unclassifiable edit cannot
be routed to the right proof.

---

## 5. Results

### 5.1 Timing — the headline

Fmax by binary search over the SDC period, baseline vs optimised tree:

| clock | baseline | optimised | delta |
|---|---|---|---|
| **`clk_s5`** | **25.65 MHz** | **89.09 MHz** | **+63.44 MHz (3.47x)** |
| `clk1` | 86.81 MHz | 95.90 MHz | +9.09 MHz |
| `clk_s3` | 95.90 MHz | 100.80 MHz | +4.90 MHz |
| `clk_s1` | 154.68 MHz | 126.74 MHz | **−27.94 MHz** |
| `clk_s2` | 117.51 MHz | 123.52 MHz | +6.01 MHz |
| `clk_s4` | 136.99 MHz | 112.26 MHz | **−24.73 MHz** |
| `clk_s8` | 86.81 MHz | 95.90 MHz | +9.09 MHz |
| `clk_s1_gate` | ≥800.00 MHz | 510.91 MHz | baseline hit sweep floor |
| `clk_s2_gate` | 473.93 MHz | 450.86 MHz | **−23.07 MHz** |
| `clk_s4_gate` | ≥500.00 MHz | ≥500.00 MHz | both hit sweep floor |
| `clk_s5_gate` | 508.91 MHz | 534.76 MHz | +25.85 MHz |

`clk_s5` was the target. It went from −25.2539 ns to +1.4876 ns at the nominal
12.5 ns period. The full chip is not timing-clean: `clk1` is −0.1659 ns and
`clk_s8` is −0.1494 ns after optimisation. Several non-target domains also
move materially, including regressions, so they are reported rather than
attributed to the targeted RTL change.

#### Self-audit finding: the first timing headline was optimistic

The saved ideal-clock headline, positive WNS and zero TNS figures re-read
`6_final.odb` without `6_final.spef`. ORFS writes the ODB
before RC extraction, then reads the SPEF and propagates clocks for its finish
report. After `metrics.py` and `fmax.py` were corrected, the extractor matched
ORFS exactly on the final candidate (`WNS −0.1659`, `TNS −1.9487`) and the
measured headline became 25.65 → 89.09 MHz. We caught the optimistic
measurement and corrected it against the flow's own signoff report.

These physical numbers describe the repaired `artifacts/final_candidate/rtl`
tree. Its isolated ORFS run reached `6_final` with DRC 0. The detailed antenna
check still reports one violating net and one pin; it is not reported as clean.

`clk2`–`clk5` report no timing path at all. Those are marked *no paths*
everywhere in the reports and excluded from every aggregate: an unconstrained
domain is an open question, not a passing clock. Printing them as 0.000 ns
slack would put four clean-looking rows in the table that no tool ever checked.

Generated-clock Fmax (the `_gate` rows near 900 MHz) is *not* design headroom.
A generated clock is divided from its master and moves only when the master
moves. Those rows show where slack sits, nothing more.

### 5.2 Loop behaviour

From `artifacts/loop/history.jsonl`:

| outcome | count |
|---|---|
| ACCEPTED | 2 |
| rejected at `g1` (formally disproved) | 3 |
| rejected at `validate` (not a legal transform) | 1 |

The accepted loop record changed `fp8_adder.v` and `fp4_dot_unit.v`. The
repaired combined candidate additionally changes `axi_lite_dot.v` and adds
`fp4_dot_stage.v`.
**Three of six proposals were formally disproved by a counterexample.** That is
the number that justifies the whole architecture — half of what a competent
model proposed for a real critical path was wrong, and the gates caught it.

### 5.3 Formal equivalence sweep

Hierarchical, leaf-first, RTL vs the gate-level netlist (`artifacts/eqy/hier4.log`):

| verdict | modules |
|---|---|
| PROVED_EQUIVALENT | **36** |
| TIMEOUT @ 180 s | 10 |
| UNPROVEN @ depth 5 | 7 |
| tool error | 1 |
| **NOT_EQUIVALENT** | **0** |

36 of 54, up from 27 after four sweeps. Nothing in the sweep is a
counterexample.

A proved module becomes a blackbox stub read on *both* sides of every later
check, so its parent never re-pays for it. A module that fails is deliberately
*not* boxed, so its parent inherits the full cone — soundness costs runtime, on
purpose. That is why 10 modules time out: a large child below them is unproven
and therefore not boxed.

Three bugs were found getting from 27 to 36, and **every one was in the
checker, not the design**: a missing solver on `PATH`, a cut-point file leaking
stubs for modules that were not children, and a gate netlist whose net names
had been renamed away by ABC.

The ORFS netlist cannot be used for this at all — it flattens, then ABC renames
every flop, so EQY finds no internal match point and k-induction on an
accumulator is unprovable at any depth. A separate `synth_named.ys` keeps
hierarchy and net names.

### 5.4 Lint

`lint.py` runs Verilator twice and diffs. Verdict: **NO_NEW_WARNINGS**.

Baseline has 9 findings (8 `WIDTHTRUNC`, 1 `UNUSEDSIGNAL`) and the optimised
tree has the same 9. Warnings are keyed on `(code, file, message)` with the
line number stripped — a pipeline transform inserts lines, so line-based
diffing would report every warning below the edit as new.

The point is not "is this code clean" — the RTL was already clean before the
model touched it. The only claim worth making is that it is *still* clean.

### 5.5 Multi-model comparison

Same targets, same gates, same budget; one flag changes. The corrected table is
generated from the preserved histories at
`artifacts/bakeoff_all_20260911/bakeoff_all.md`:

| licence | model | proposals | accepted | died at |
|---|---|---|---|---|
| open-weight | `nvidia/nemotron-3-ultra-550b` | 7 | **1** | validate 3, audit 1, g1 2 |
| open-weight | `nvidia/nemotron-3-super-120b` | 5 | 0 | propose 2, validate 2, g1 1 |
| open-weight | `nvidia/nemotron-3-nano-30b` | 5 | 0 | propose 2, validate 2, g1 1 |
| open-weight | `google/gemma-4-31b` | 1 | *not tested* | backend (429) |
| free-closed | `gemini-3.5-flash` | 6 | **1** | propose 1, g1 4 |
| free-closed | `gemini-3.1-pro` | 1 | *not tested* | backend (quota) |

**Read the "died at" column, not the accept count.** A model that never named a
legal transform, one that named a real transform and was then formally
disproved, and one whose provider never answered are three different failures.
A single accept rate makes them look identical.

Two arms hit provider rate limits before a single proposal reached a gate.
Those are an absence of evidence, not evidence of failure, and are marked *not
tested* rather than scored as zero. They must be re-run alone once quota resets.
`gemma-free` was retried alone on 11 September after its slug was successfully
probed; OpenRouter again returned HTTP 429 after five attempts, so it remains
not tested. The retry is preserved in
`artifacts/bakeoff_signoff_gemma_free_20260911/`.

#### Self-audit finding: one historical acceptance changed the wrong target

The original Nemotron Ultra row said 2/7 accepted, but its second accepted
record targeted `fp4_dot_unit` while the proposal and G1 proof both named
`fp8_adder`. The final tree confirmed the mismatch: only `fp8_adder.v` changed.
That record is now classified as `audit`, leaving the honest score **1/7**.
The preserved history was not edited.

`loop.py` now records `proposal_module`, rejects a proposal whose primary
module differs from the requested target, and rejects a byte-identical rewrite
before formal verification. Both guards were exercised offline: the wrong
module and the exact current module each produced `REJECTED` at `validate` and
zero accepts. `bakeoff.py` also reconstructs historical accepted snapshots so
old no-op/wrong-target records cannot inflate a merged table.

"Open source" here means **weights someone else can download**, not a free API.
Gemini is free and closed; putting it in the open column would be the kind of
claim a judge is right to poke at.

**The paid-Claude arm has not been run yet** — it needs an API key. That is the
missing half of this comparison.

---

## 6. What is in the repo

```
bench/rtl/                55 modules, frozen input, never written to
bench/constraints/        nebula.sdc
bench/DECISIONS.md        every design decision with its reasoning
bench/scripts/
  llm.py                  one backend interface, every provider, + mock (no key needed)
  loop.py                 the agentic loop
  transforms.py           transform catalog + structural validation
  slicer.py               critical path -> RTL file + the lines worth showing
  hierarchy.py            instance path -> module (the Yosys-name bridge)
  g1_equiv.py             plain miter
  g1b_contract.py         parent contract under +N latency
  g1c_stream.py           output-stream equivalence
  g2_cdc.py               CDC structure preserved
  clockcheck.py           generated clocks glitch-free
  cdc_classify.py         classifies every crossing in the design
  metrics.py              PPA extraction from a routed ODB
  fmax.py                 per-domain Fmax by binary search over SDC period
  lint.py                 REPORT 1 — golden vs candidate, diffed
  ppa_report.py           REPORT 4 — PPA + per-clock timing + Fmax
  bakeoff.py              multi-model sweep runner (+ --probe for dead slugs)
  bakeoff_merge.py        merges sweeps into the one comparison table
scripts/submission_check.py  one-command evidence, signoff and hash audit
demo.py                   eight-act replay demo, runs offline with no API key
artifacts/                every run kept: loop, eqy, wns, metrics, bakeoff, lint, ppa
```

8 commits on `nebula-digital`, all local and unpushed.

---

## 7. Decisions worth defending

**Cheapest gate first.** A structural check costs milliseconds, a full PnR
costs ninety minutes. G3 therefore runs *once at the end* over the accepted
set, not once per proposal.

**`died_at` is a Counter, not a score.** Collapsing where a proposal died into
one number erases the only interesting finding.

**Rejections are quoted back to the model, twice.** The retry path is a feature
of the harness, not of the model — which is why the tables track
first-attempt accepts separately.

**A mock backend that behaves identically offline.** The demo must not depend
on a network or a key. Canned proposals can be a *list*, so the scripted
sequence "reply the gates reject, then the repair" is testable with no model at
all — and that retry path is where most of the loop's logic lives.

**Keys live only in environment variables**, read from `~/.config/nebula/env`
(chmod 600, outside the repo so it cannot be committed). `llm.py` refuses to
start without the env var and never logs the credential. Never passed as a
command-line argument, where it would land in shell history.

**A 4xx that is not 429 fails immediately.** Retrying a bad key or a mistyped
model id turns it into a 62-second wait whose error reads "failed after 5
tries", which sends the debugger towards the network. 429/503/529 back off
properly — a free tier meets them routinely and 1+2+4 s is far too short.

**Model slugs are probed before a sweep starts.** They drift; a wrong slug is a
404, not a useful error. Half of a first plausible-looking guess was already
dead. A typo should cost one second, not surface three arms into an overnight
run.

---

## 8. What is not done

| gap | state |
|---|---|
| Paid Claude arm | needs API key. Comparison is incomplete without it. |
| `gemma-free` arm | retried alone 11 Sep; still HTTP 429 before any gate, so not tested |
| `gemini-pro` arm | rate-limited; re-run alone when quota/billing status is confirmed |
| Synthesis report | REPORT 2 of 4 — generator and current report exist |
| EQY clean report | REPORT 3 of 4 — generator reads the preserved sweep; report exists |
| Single frozen-vs-final equivalence artifact | exists; verdict is equivalence modulo declared +4 stream latency, not cycle identity |
| Final-candidate PnR | complete through `6_final`; DRC 0, one antenna net/pin violation remains |
| 18 unproved modules | 10 timeout, 7 unproven, 1 tool error |
| Demo video | not recorded (`source orfs/env.sh` first) |
| Push | 8 commits local |
| Final report | current 13-page PDF exists; paid-model row will be added after that arm runs |

All four report generators now exist: `lint.py`, `synth_report.py`,
`eqy_report.py`, and `ppa_report.py`.

---

## 9. Honest framing for the report

Three things that should be said plainly rather than smoothed over:

1. **The signoff candidate is not fully timing-clean.** `clk1` and `clk_s8`
   retain small setup violations, and four generated/non-target clock rows
   lose slack even though the `clk_s5` target improves by 63.44 MHz.
2. **Four clock domains report no timing path.** They are unconstrained, not
   passing. Every table marks them.
3. **Two bake-off arms were never tested.** Rate limits, not model failure.

Partial success reported honestly — with the counterexamples the gates caught
as evidence — is a stronger submission than a clean claim nobody can check.
ViTAD reports 73.68% repair success against a 54.38% plain-LLM baseline; a
number in that range, with a formal proof attached to every accepted edit, is
the claim this system can actually support.
