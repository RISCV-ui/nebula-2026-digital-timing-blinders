| model | proposals | accepted | 1st try | accept rate | wall s | died at |
|---|---|---|---|---|---|---|
| `gemini:gemini-flash` | 3 | 0 | 0 | 0.0 | 397.6 | backend 1, g1 1 |
| `openrouter:nemotron-ultra` | 21 | 1 | 1 | 0.048 | 11310.1 | propose 4, validate 10, g1 4, g1b 1 |
| `anthropic:sonnet-direct` | 13 | 1 | 1 | 0.077 | 1930.3 | propose 8, g1 2, g1b 1 |
| `anthropic:opus-direct` | 13 | 0 | 0 | 0.0 | 2306.8 | propose 9, g1 2, g1b 1 |

| model | tokens in | tokens out | cost USD | USD per accepted fix |
|---|---|---|---|---|
| `gemini:gemini-flash` | 5231 | 2903 | $0.0088 | no accepted fix |
| `openrouter:nemotron-ultra` | 121504 | 369873 | $0.0000 | $0.0000 |
| `anthropic:sonnet-direct` | 107730 | 160195 | $2.6484 | $2.6484 |
| `anthropic:opus-direct` | 106411 | 163986 | $13.5065 | no accepted fix |

Frozen input RTL: `bench/rtl_v2` (never written to).

| model | optimised RTL | files changed | files added |
|---|---|---|---|
| `gemini:gemini-flash` | `artifacts/bakeoff_v2/gemini_gemini-flash/rtl` | -- | -- |
| `openrouter:nemotron-ultra` | `artifacts/bakeoff_v2/openrouter_nemotron-ultra/rtl` | `fp8_adder.v` | -- |
| `anthropic:sonnet-direct` | `artifacts/bakeoff_v2/anthropic_sonnet-direct/rtl` | `fp8_adder.v` | -- |
| `anthropic:opus-direct` | `artifacts/bakeoff_v2/anthropic_opus-direct/rtl` | -- | -- |
