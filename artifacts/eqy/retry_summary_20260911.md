# Targeted EQY retry - 11 September 2026

**Verdict: NO_IMPROVEMENT - 36/54 proved, 0 new proofs.**

| module | depth | method | result | seconds |
|---|---:|---|---|---:|
| `read_buffer_d_cache` | 10 | plain yosys miter | UNPROVEN (2 cells) at depth 10 | 29.4 |
| `uart_controller` | 10 | plain yosys miter | UNPROVEN (1 cells) at depth 10 | 9.0 |
| `dma_controller` | 10 | plain yosys miter | UNPROVEN (166 cells) at depth 10 | 32.0 |
| `axi_lite_dma_config` | 10 | plain yosys miter | TIMEOUT after 60s | 60.0 |
| `axi_lite_timer` | 7 | timer child cut-point + plain miter | TIMEOUT after 60s | 60.0 |

Three broader attempts were manually interrupted because the EQY subprocess timeout did not terminate descendant solver processes. No verdict from an interrupted run is counted.

Targeted deeper retries produced zero additional proofs. The defensible result remains 36/54 proved and 0 counterexamples.
