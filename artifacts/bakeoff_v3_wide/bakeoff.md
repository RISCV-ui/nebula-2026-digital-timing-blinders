| model | proposals | accepted | 1st try | accept rate | wall s | died at |
|---|---|---|---|---|---|---|
| `anthropic:sonnet-direct` | 14 | 4 | 4 | 0.286 | 4786.7 | propose 1, validate 3, g1 5 |

| model | tokens in | tokens out | cost USD | USD per accepted fix |
|---|---|---|---|---|
| `anthropic:sonnet-direct` | 98523 | 218949 | $3.5364 | $0.8841 |

Frozen input RTL: `bench/rtl` (never written to).

| model | optimised RTL | files changed | files added |
|---|---|---|---|
| `anthropic:sonnet-direct` | `artifacts/bakeoff_v3_wide/anthropic_sonnet-direct/rtl` | `fp8_adder.v` | -- |
