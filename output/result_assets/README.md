# Digital result asset pack

Ready-to-paste figures are in `figures/` as both SVG and 1600x900 PNG. Machine-readable tables are in `data/`.

## Figure map

1. `01_proof_gated_flow` - innovation and complete loop.
2. `02_verified_dashboard` - headline signoff numbers and limits.
3. `03_model_gate_outcomes` - same-task stacked outcome comparison.
4. `04_model_rate_runtime` - valid acceptance rate and end-to-end wall time.
5. `05_agent_loop_verdicts` - six final-design proposal outcomes.
6. `06_fmax_before_after` - measured Fmax across clocks with timing paths.
7. `07_clock_slack_delta` - improvements and regressions per clock.
8. `08_physical_ppa` - routed area, instances, WNS and TNS.
9. `09_formal_verification` - EQY coverage and latency-aware proof.
10. `10_rtl_change_scope` - changed cone versus byte-identical RTL.
11. `11_model_comparison_table` - all model rows, including untested arms.
12. `12_complete_clock_table` - every clock, including four NO PATH rows.
13. `13_stage_aware_area` - mapped synthesis versus routed PPA without mixing stages.
14. `14_eqy_targeted_retries` - deeper retry results and zero-new-proof outcome.

## Required interpretation

- Only four model arms were tested: Nemotron Ultra, Nemotron Super, Nemotron Nano and Gemini Flash.
- Gemma free and Gemini Pro received HTTP 429 before a proposal reached a gate. They are `NOT TESTED`, not 0% performers.
- Nemotron Ultra is 1/7 after audit. A historical second accept targeted one module but returned an unchanged/wrong module and is invalid.
- Full OpenROAD PnR/PPA was run once for the final combined accepted candidate. No individual model-arm PnR numbers exist. The model comparison therefore reports proposal/gate performance; the PPA figures report final combined design performance.
- `clk1` and `clk_s8` retain small violations. `clk2` through `clk5` report no paths. Four timed clocks regress in slack while remaining closed.
- EQY has 36/54 proved and zero counterexamples; 18 modules remain unresolved. The accepted pipeline changes latency by four cycles, so ordinary cycle equivalence is not claimed.
- Five targeted deeper EQY retries produced zero new proofs. The original 36/54 result remains unchanged.

## Evidence hashes

- `a9e1efd18ea38445296c8f909d18bcf10e282cb5b230fd08542c377703bd3e65`  `artifacts/bakeoff_all_20260911/bakeoff_all.json`
- `480837ae078dcde5fbf43084951157abc83baf222d8aeabd1cc71bdca80bec26`  `artifacts/submission_20260911/ppa.json`
- `706ef23975b817ca06fe157c35c7882291a383e84d99ee072343efb4c70eef5c`  `artifacts/eqy/report.json`
- `a93b764002ae83142083d344429e8a92b77b5a5bee2643bc2020ffc4f919cfce`  `artifacts/final_candidate/toplevel_equiv.json`
- `f4cb2725075bc25d2d4d1b068939a7266933501acc785dc5979250e164639b44`  `artifacts/loop/history.jsonl`
- `92303f15a690a30e3b892e3824cce530822f4bb8e5562f58b70efbc8028fa691`  `artifacts/submission_20260911/synth.json`
- `105c8f887a13fba52c0ea7d1f3669ebfddfc73a538b47e4d7e9f2b73514618c9`  `artifacts/eqy/retry_summary_20260911.json`
