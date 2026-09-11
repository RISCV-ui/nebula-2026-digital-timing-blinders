# EQY hierarchical equivalence report

## 36/54 proved, 0 counterexamples

- **PROVED_EQUIVALENT:** 36
- **TIMEOUT:** 10
- **UNPROVEN:** 7
- **tool error:** 1
- **NOT_EQUIVALENT:** 0
- **sweep runtime:** 3637.3 s

`TIMEOUT`, `UNPROVEN`, and tool errors are incomplete checks. They are not proofs and they are not counterexamples.

## Why incomplete parents cost more

The sweep is compositional. A child is boxed identically on the RTL and netlist sides only after that child has proved equivalent. If a child is unproven, it is deliberately left expanded in every parent, so the parent solver must carry that child's state and logic. This preserves soundness at the cost of runtime and is why incomplete leaf proofs can propagate upward as parent timeouts.

## Modules without a proof

| module | result | seconds | proved children boxed |
|---|---|---:|---|
| `axi_lite_dma_config` | UNPROVEN (234 cells) at depth 5 | 37.2 | none |
| `branch_predictor` | TIMEOUT after 180s | 200.2 | none |
| `dma_controller` | UNPROVEN (166 cells) at depth 5 | 46.8 | none |
| `multiplier_pipelined` | TIMEOUT after 180s | 417.1 | none |
| `read_buffer_d_cache` | UNPROVEN (2 cells) at depth 5 | 26.2 | none |
| `uart_controller` | UNPROVEN (1 cells) at depth 5 | 31.4 | none |
| `axi_interconnect_2m_8s` | UNPROVEN (882 cells) at depth 5 | 19.7 | `arbiter` |
| `axi_lite_gpio` | TIMEOUT after 180s | 286.4 | `gpio_controller` |
| `axi_lite_timer` | UNPROVEN (22 cells) at depth 5 | 229.5 | `timer` |
| `axi_lite_uart` | UNPROVEN (18 cells) at depth 5 | 177.4 | none |
| `execution_stage` | TIMEOUT after 180s | 402.6 | `alu`, `data_clipper` |
| `fp4_dot_unit` | TIMEOUT after 180s | 217.1 | `fp4_mul`, `fp8_adder` |
| `l1_d_cache_8kb` | TIMEOUT after 180s | 180.2 | `id_memory_256x64_wrap`, `tag_memory_92x64_wrap` |
| `l1_i_cache_8kb` | TIMEOUT after 180s | 180.1 | `id_memory_256x64_wrap`, `tag_memory_92x64_wrap` |
| `axi_lite_dot` | TIMEOUT after 180s | 194.2 | none |
| `instruction_fetch_stage` | TIMEOUT after 180s | 180.1 | `i_rom_32x256`, `read_buffer_i_cache` |
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
