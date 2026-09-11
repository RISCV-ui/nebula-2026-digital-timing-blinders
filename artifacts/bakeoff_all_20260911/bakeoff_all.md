| licence | model | slug | proposals | accepted | 1st try | wall s | died at |
|---|---|---|---|---|---|---|---|
| open-weight | `openrouter:nemotron-ultra` | `nvidia/nemotron-3-ultra-550b-a55b:free` | 7 | 1 | 1 | 2582.3 | validate 3, audit 1, g1 2 |
| open-weight | `openrouter:nemotron` | `nvidia/nemotron-3-super-120b-a12b:free` | 5 | 0 | 0 | 974.5 | propose 2, validate 2, g1 1 |
| open-weight | `openrouter:nemotron-nano` | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` | 5 | 0 | 0 | 1707.6 | propose 2, validate 2, g1 1 |
| open-weight | `openrouter:gemma-free` | `google/gemma-4-31b-it:free` | 1 | _not tested_ | -- | 179.4 | backend 1 |
| free-closed | `gemini:gemini-flash` | `models/gemini-3.5-flash` | 6 | 1 | 1 | 2401.9 | propose 1, g1 4 |
| free-closed | `gemini:gemini-pro` | `models/gemini-3.1-pro-preview` | 1 | _not tested_ | -- | 178.1 | backend 1 |

> **`openrouter:gemma-free`, `gemini:gemini-pro`** hit the provider's rate limit before a single proposal reached a gate. Those rows are an absence of evidence, not evidence of failure, and must be re-run on their own once the quota resets rather than reported as a score of zero.

**Where each model died** is the column to read, not the accept count. A proposal stopped at `validate` never named one of the four allowed transforms; one stopped at `g1` named a real transform and was then formally disproved by a counterexample; `backend` means the provider never answered and the model was not tested at all. Those are three different failures, and a single accept rate makes them look identical.

Frozen input RTL: `bench/rtl`, never written to. Each arm's optimised tree is below.

| model | optimised RTL | files changed |
|---|---|---|
| `openrouter:nemotron-ultra` | `artifacts/bakeoff_open/openrouter_nemotron-ultra/rtl` | `fp8_adder.v` |
| `openrouter:nemotron` | `artifacts/bakeoff_open/openrouter_nemotron/rtl` | -- |
| `openrouter:nemotron-nano` | `artifacts/bakeoff_open/openrouter_nemotron-nano/rtl` | -- |
| `openrouter:gemma-free` | `artifacts/bakeoff_signoff_gemma_free_20260911/openrouter_gemma-free/rtl` | -- |
| `gemini:gemini-flash` | `artifacts/bakeoff/gemini_gemini-flash/rtl` | `axi_lite_dot.v`, `fp4_dot_unit.v`, `fp8_adder.v` |
| `gemini:gemini-pro` | `artifacts/bakeoff/gemini_gemini-pro/rtl` | -- |
