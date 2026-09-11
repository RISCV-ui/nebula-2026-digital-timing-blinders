# EQY hierarchical equivalence report

## 36/54 proved, 0 counterexamples

- **PROVED_EQUIVALENT:** 36
- **TIMEOUT:** 10
- **UNPROVEN:** 7
- **tool error:** 1
- **NOT_EQUIVALENT:** 0
- **sweep runtime:** 3637.3 s

`TIMEOUT`, `UNPROVEN`, and tool errors are incomplete checks. They are not proofs and they are not counterexamples.

## Reset-constrained supplement

**45/54 modules now have formal evidence:** 36 unrestricted proofs plus 9 bounded proofs at depth 5 under the declared reset contract.

This does not relabel the unrestricted result. Synthesis removed unreachable state encodings in these modules, so the supplemental proof asserts every reset in the initial formal step and compares outputs after every clock domain has observed reset.

Every supplemental proof has a negative control that inverts one output; all negative controls produced a counterexample.

`axi_lite_dma_config`, `axi_lite_gpio`, `axi_lite_timer`, `axi_lite_uart`, `branch_predictor`, `dma_controller`, `instruction_fetch_stage`, `read_buffer_d_cache`, `uart_controller`

## Why incomplete parents cost more

The sweep is compositional. A child is boxed identically on the RTL and netlist sides only after that child has proved equivalent. If a child is unproven, it is deliberately left expanded in every parent, so the parent solver must carry that child's state and logic. This preserves soundness at the cost of runtime and is why incomplete leaf proofs can propagate upward as parent timeouts.

## Modules without a proof

| module | result | seconds | proved children boxed |
|---|---|---:|---|
| `multiplier_pipelined` | TIMEOUT after 180s | 417.1 | none |
| `axi_interconnect_2m_8s` | UNPROVEN (882 cells) at depth 5 | 19.7 | `arbiter` |
| `execution_stage` | TIMEOUT after 180s | 402.6 | `alu`, `data_clipper` |
| `fp4_dot_unit` | TIMEOUT after 180s | 217.1 | `fp4_mul`, `fp8_adder` |
| `l1_d_cache_8kb` | TIMEOUT after 180s | 180.2 | `id_memory_256x64_wrap`, `tag_memory_92x64_wrap` |
| `l1_i_cache_8kb` | TIMEOUT after 180s | 180.1 | `id_memory_256x64_wrap`, `tag_memory_92x64_wrap` |
| `axi_lite_dot` | TIMEOUT after 180s | 194.2 | none |
| `processor_top` | TIMEOUT after 180s | 180.2 | `alu_src_a_mux`, `alu_src_b_mux`, `branch_comprator`, `data_extender`, `data_forwarding_unit`, `hazard_detection_unit`, `instruction_decode_stage`, `memory_stage`, `pipeline_reg_ex_mem`, `pipeline_reg_id_ex`, `pipeline_reg_if_id`, `pipeline_reg_mem_wb`, `write_back_stage` |
| `soc_top` | YOSYS_ERROR: ERROR: Assert `count_id(wire->name) == 0' failed in /work/_builds/darwin-arm64/yosys/yosys/kernel/rtlil.cc:2888. | 45.3 | `axi_lite_master`, `clk_div_mux`, `clk_gate`, `dmem`, `interrupt_control_unit`, `l1_cache_axi_master`, `mem_axi_slave` |

## Intermediate counterexample diagnostics

Partitioned passes can report a counterexample that the merged pass does not reproduce. These signals are retained for debugging but are never promoted to a final `NOT_EQUIVALENT` verdict.

| module | claiming pass(es) | final result |
|---|---|---|
| `dma_controller` | `partitioned`, `merged` | UNPROVEN (166 cells) at depth 5 |
| `multiplier_pipelined` | `merged` | TIMEOUT after 180s |
| `read_buffer_d_cache` | `partitioned` | UNPROVEN (2 cells) at depth 5 |
| `uart_controller` | `partitioned` | UNPROVEN (1 cells) at depth 5 |
| `fp4_dot_unit` | `partitioned` | TIMEOUT after 180s |

## Evidence integrity

- JSON SHA-256: `1e2c46397d5e267a1e9a9253a5b72429fe04ca0723c2ef6327287e832d5a4d54`
- log SHA-256: `ca592518e2bf4f042b738b1db3641c5d0a5f7deb7efe2d2486cf83c9c14f483a`
- reset supplement SHA-256: `556ad49bfeb1dfac2d4fb8c52e9c1441092b81ed6838d5d90ef2c45cded0de8a`
