# Digital submission verification summary

## READY_EXCEPT_PAID_MODEL_AND_VIDEO

All local work required before the paid-model comparison is complete. `python3 scripts/submission_check.py` passes every evidence and signoff consistency check.

- `clk_s5`: **25.65 -> 89.09 MHz (3.47x)**
- Setup WNS: **-25.2539 -> -0.1659 ns**
- Setup TNS: **-3384.4421 -> -1.9487 ns**
- Routed area: **-1.60%**; instances: **-4,927**
- Lint: **NO_NEW_WARNINGS**
- Synthesis: **SYNTHESIS_VALID**
- Formal coverage: **45/54 modules** — 36 unrestricted EQY proofs plus 9 reset-constrained bounded proofs; 0 real-design counterexamples
- Top artifact: **equivalent modulo declared +4-cycle stream latency**; ordinary cycle equivalence is `NOT_EQUIVALENT`
- Demo replay rehearsal: **exit 0**, final signoff numbers shown, no network/API used

## Bake-off correction

Nemotron Ultra is **1/7 valid accepts**. Its historical second accept targeted `fp4_dot_unit` but rewrote `fp8_adder`; the raw evidence remains preserved and the merged audit excludes it. Gemma free was retried alone on 11 September and again received HTTP 429 before any proposal reached a gate.

## Expected negative result during this run

`ppa_report.py` emitted its complete report and exited 1 because four constrained clocks have worse slack: `clk_s1`, `clk_s1_gate`, `clk_s2_gate`, and `clk_s4`. This is the report generator's intended stop condition. The target clock and overall timing improved, but the regression is retained.

## Still pending

- Paid Claude comparison arm
- Demo video recording

The first synthesis-report invocation passed RTL directories and failed with `File .../bench/rtl not found or is a directory`. The corrected invocation used the two mapped, hierarchy-preserving netlists and returned `SYNTHESIS_VALID`.
