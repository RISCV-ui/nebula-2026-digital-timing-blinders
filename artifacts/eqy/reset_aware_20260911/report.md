# Reset-constrained equivalence supplement

**9/9 targeted modules proved at depth 5.**

Combined coverage: **45/54 modules have formal evidence** (36 unrestricted EQY proofs plus 9 reset-constrained bounded proofs).

This does not rewrite the unrestricted EQY result. The supplement declares reset because synthesis removed unreachable state encodings that arbitrary-initial-state induction could not match.

Each row includes a negative control that inverts the named output. PASS means the real comparison proved and the corrupted comparison produced a counterexample.

| Module | Result | Depth | Negative control |
|---|---:|---:|---|
| `uart_controller` | PROVED_RESET_CONSTRAINED | 5 | invert `data_out` |
| `read_buffer_d_cache` | PROVED_RESET_CONSTRAINED | 5 | invert `data_out` |
| `dma_controller` | PROVED_RESET_CONSTRAINED | 5 | invert `data_out` |
| `branch_predictor` | PROVED_RESET_CONSTRAINED | 5 | invert `hit_wire` |
| `axi_lite_uart` | PROVED_RESET_CONSTRAINED | 5 | invert `int_out_uart` |
| `axi_lite_timer` | PROVED_RESET_CONSTRAINED | 5 | invert `int_out_timer` |
| `axi_lite_gpio` | PROVED_RESET_CONSTRAINED | 5 | invert `int_out_gpio` |
| `axi_lite_dma_config` | PROVED_RESET_CONSTRAINED | 5 | invert `s1_ar_ready` |
| `instruction_fetch_stage` | PROVED_RESET_CONSTRAINED | 5 | invert `pc_pluse4_if` |

Full hashes, timings, and return codes are in `report.json`; raw Yosys transcripts are in `logs/`.
