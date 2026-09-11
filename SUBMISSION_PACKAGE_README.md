# Nebula 2026 Digital — Timing Blinders

Topic: **Constraint Optimization through RTL Enhancement Using Generative AI**

Team: Shubhanshu Shivhare and Nagarjun BV, IIT Bombay

Package status on 11 September 2026: **READY_EXCEPT_PAID_MODEL_AND_VIDEO**.

Start with:

1. `WORKLOG.md` for verified history, failures, and open items.
2. `output/pdf/Nebula_Digital_Final_Report.pdf` for the submission report.
3. `artifacts/submission_20260911/summary.md` for the compact evidence index.
4. `scripts/submission_check.py` for the offline end-to-end evidence check.

## Verified results

- `clk_s5`: 25.65 MHz to 89.09 MHz (3.47x).
- Setup WNS: -25.2539 ns to -0.1659 ns.
- Setup TNS: -3384.4421 ns to -1.9487 ns.
- Routed area: -1.5957%; instances: -4,927 (-1.025%).
- DRC: 0. Antenna: 1 net / 1 pin.
- 9 of 11 timed clocks close. `clk1` and `clk_s8` retain small violations.
- Four clocks (`clk2` through `clk5`) have no timing paths; they are not counted as passing.
- Top result: equivalent modulo one declared four-cycle stream latency change. Ordinary cycle-by-cycle top-level equivalence is not claimed.
- EQY sweep: 36/54 proved, 10 timeout, 7 unproven, 1 tool error, 0 counterexamples.
- Final lint: no new warnings.

## Model comparison

- Nemotron Ultra: 1 valid accepted proposal of 7. One historical no-op was previously miscounted and is now flagged by the audit.
- Gemini Flash: 1/6 accepted.
- Nemotron Super and Nano: 0/5 each.
- Gemma free: HTTP 429 after all retries; no proposal reached a gate, so it is **not tested**, not scored as a model failure.
- Paid/Claude model arm is intentionally pending until team approval and API setup.

## Package scope

Package contains frozen and final RTL, scripts, constraints, macro views, formal/lint/synthesis/PPA reports, raw bake-off histories, selected signoff reports, and final report PDF.

Multi-gigabyte EQY solver workdirs and intermediate OpenROAD ODB/DEF/SPEF files are excluded. They are scratch/rebuild products, not submission deliverables. Full local workspace retains them. Corrected merged bake-off report in `artifacts/bakeoff_all_20260911/` is the source of truth when old per-run summaries disagree.

No API key or environment file is included. Demo video remains pending; use replay mode only while recording.
