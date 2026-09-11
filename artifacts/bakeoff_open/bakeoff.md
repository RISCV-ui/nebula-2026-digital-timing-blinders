| model | proposals | accepted | 1st try | accept rate | wall s | died at |
|---|---|---|---|---|---|---|
| `openrouter:nemotron` | 5 | 0 | 0 | 0.0 | 974.5 | propose 2, validate 2, g1 1 |
| `openrouter:nemotron-ultra` | 7 | 2 | 1 | 0.286 | 2582.3 | validate 3, g1 2 |
| `openrouter:nemotron-nano` | 5 | 0 | 0 | 0.0 | 1707.6 | propose 2, validate 2, g1 1 |
| `openrouter:gemma-free` | 1 | 0 | 0 | 0.0 | 179.3 | backend 1 |

Frozen input RTL: `bench/rtl` (never written to).

| model | optimised RTL | files changed | files added |
|---|---|---|---|
| `openrouter:nemotron` | `artifacts/bakeoff_open/openrouter_nemotron/rtl` | -- | -- |
| `openrouter:nemotron-ultra` | `artifacts/bakeoff_open/openrouter_nemotron-ultra/rtl` | `fp8_adder.v` | -- |
| `openrouter:nemotron-nano` | `artifacts/bakeoff_open/openrouter_nemotron-nano/rtl` | -- | -- |
| `openrouter:gemma-free` | `artifacts/bakeoff_open/openrouter_gemma-free/rtl` | -- | -- |
