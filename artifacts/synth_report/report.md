# Synthesis comparison

## SYNTHESIS_VALID

Both sides were mapped with the same liberty and re-read by Yosys with hierarchy enabled.

| metric | golden | candidate | change |
|---|---:|---:|---:|
| Mapped cells | 90,193 | 90,798 | 605 (+0.671%) |
| Mapped area (µm²) | 1,413,941.08 | 1,417,519.51 | 3,578.43 (+0.253%) |
| Sequential area (µm²) | 956,377.24 | 958,859.62 | 2,482.38 (+0.260%) |

Golden hierarchy: **56 modules**; candidate hierarchy: **57 modules**.

## Local area by module

Local figures exclude child instances, so each mapped cell is counted once across this table.

| module | golden cells | candidate cells | Δcells | golden area | candidate area | Δarea |
|---|---:|---:|---:|---:|---:|---:|
| `$paramod$72f83d20332db853f52d52010cdb396e42162176\asynchronous_fifo_gen` | 1,038 | 1,041 | +3 | 20,569.73 | 20,512.17 | -57.56 |
| `$paramod$e9b0330b32c707496d2ac0891b99a36ab486e931\asynchronous_fifo_gen` | 1,305 | 1,305 | +0 | 25,951.14 | 25,951.14 | +0.00 |
| `$paramod\fp4_dot_stage\DOT_LAT=s32'00000000000000000000000000000100` | 0 | 18 | +18 | 0.00 | 163.91 | +163.91 |
| `alu` | 989 | 989 | +0 | 5,874.38 | 5,874.38 | +0.00 |
| `alu_src_a_mux` | 66 | 66 | +0 | 530.51 | 530.51 | +0.00 |
| `alu_src_b_mux` | 35 | 35 | +0 | 294.03 | 294.03 | +0.00 |
| `arbiter` | 4 | 4 | +0 | 38.79 | 38.79 | +0.00 |
| `axi_interconnect_2m_8s` | 1,360 | 1,360 | +0 | 13,141.35 | 13,141.35 | +0.00 |
| `axi_lite_dma_config` | 715 | 715 | +0 | 6,013.27 | 6,013.27 | +0.00 |
| `axi_lite_dot` | 283 | 282 | -1 | 2,386.04 | 2,381.03 | -5.00 |
| `axi_lite_gpio` | 226 | 226 | +0 | 1,794.22 | 1,794.22 | +0.00 |
| `axi_lite_master` | 553 | 553 | +0 | 4,782.09 | 4,782.09 | +0.00 |
| `axi_lite_timer` | 226 | 226 | +0 | 1,794.22 | 1,794.22 | +0.00 |
| `axi_lite_uart` | 226 | 226 | +0 | 1,794.22 | 1,794.22 | +0.00 |
| `branch_comp_decoder` | 8 | 8 | +0 | 46.29 | 46.29 | +0.00 |
| `branch_comprator` | 130 | 130 | +0 | 808.28 | 808.28 | +0.00 |
| `branch_predictor` | 4,482 | 4,482 | +0 | 53,443.76 | 53,443.76 | +0.00 |
| `clk_div_mux` | 10 | 10 | +0 | 115.11 | 115.11 | +0.00 |
| `clk_gate` | 1 | 1 | +0 | 6.26 | 6.26 | +0.00 |
| `control_unit` | 74 | 74 | +0 | 462.94 | 462.94 | +0.00 |
| `csr_regfile` | 1,287 | 1,287 | +0 | 10,796.60 | 10,796.60 | +0.00 |
| `data_clipper` | 34 | 34 | +0 | 195.19 | 195.19 | +0.00 |
| `data_extender` | 39 | 39 | +0 | 266.51 | 266.51 | +0.00 |
| `data_forwarding_unit` | 256 | 256 | +0 | 1,921.84 | 1,921.84 | +0.00 |
| `dma_controller` | 1,765 | 1,765 | +0 | 14,546.45 | 14,546.45 | +0.00 |
| `dmem` | 3,312 | 3,312 | +0 | 78,238.79 | 78,238.79 | +0.00 |
| `execution_stage` | 64 | 64 | +0 | 720.69 | 720.69 | +0.00 |
| `fp4_dot_unit` | 0 | 360 | +360 | 0.00 | 4,053.89 | +4,053.89 |
| `fp4_mul` | 32 | 32 | +0 | 207.70 | 207.70 | +0.00 |
| `fp8_adder` | 381 | 390 | +9 | 2,406.06 | 2,374.78 | -31.28 |
| `gpio_controller` | 1,999 | 1,999 | +0 | 18,052.31 | 18,052.31 | +0.00 |
| `hazard_detection_unit` | 88 | 88 | +0 | 599.32 | 599.32 | +0.00 |
| `i_rom_32x256` | 28 | 28 | +0 | 265.25 | 265.25 | +0.00 |
| `id_memory_256x64_wrap` | 3,855 | 3,855 | +0 | 85,308.07 | 85,308.07 | +0.00 |
| `immediate_generator` | 52 | 52 | +0 | 371.61 | 371.61 | +0.00 |
| `instruction_decode_stage` | 1 | 1 | +0 | 6.26 | 6.26 | +0.00 |
| `instruction_fetch_stage` | 483 | 483 | +0 | 4,080.16 | 4,080.16 | +0.00 |
| `interrupt_control_unit` | 27 | 27 | +0 | 282.77 | 282.77 | +0.00 |
| `l1_cache_axi_master` | 2,757 | 2,757 | +0 | 23,007.07 | 23,007.07 | +0.00 |
| `l1_d_cache_8kb` | 4,282 | 4,310 | +28 | 32,263.44 | 32,102.04 | -161.40 |
| `l1_i_cache_8kb` | 3,130 | 3,229 | +99 | 22,562.89 | 22,537.87 | -25.02 |
| `mem_axi_slave` | 609 | 629 | +20 | 4,160.24 | 4,276.60 | +116.36 |
| `memory_stage` | 0 | 0 | +0 | 0.00 | 0.00 | +0.00 |
| `multiplier_pipelined` | 4,418 | 4,418 | +0 | 31,560.27 | 31,560.27 | +0.00 |
| `pipeline_reg_ex_mem` | 240 | 240 | +0 | 2,702.59 | 2,702.59 | +0.00 |
| `pipeline_reg_id_ex` | 688 | 688 | +0 | 7,743.68 | 7,743.68 | +0.00 |
| `pipeline_reg_if_id` | 289 | 289 | +0 | 3,249.37 | 3,249.37 | +0.00 |
| `pipeline_reg_mem_wb` | 150 | 150 | +0 | 1,970.64 | 1,970.64 | +0.00 |
| `processor_top` | 35 | 35 | +0 | 379.11 | 379.11 | +0.00 |
| `read_buffer_d_cache` | 1,162 | 1,162 | +0 | 15,175.80 | 15,175.80 | +0.00 |
| `read_buffer_i_cache` | 1,491 | 1,491 | +0 | 12,095.35 | 12,095.35 | +0.00 |
| `register_file` | 2,561 | 2,561 | +0 | 46,494.59 | 46,494.59 | +0.00 |
| `soc_top` | 1,475 | 1,475 | +0 | 11,771.29 | 11,771.29 | +0.00 |
| `tag_memory_92x64_wrap` | 1,394 | 1,394 | +0 | 30,728.22 | 30,728.22 | +0.00 |
| `timer` | 533 | 533 | +0 | 4,242.82 | 4,242.82 | +0.00 |
| `uart_controller` | 722 | 722 | +0 | 5,920.68 | 5,920.68 | +0.00 |
| `write_back_stage` | 32 | 32 | +0 | 360.35 | 360.35 | +0.00 |

## Evidence integrity

- Golden netlist SHA-256: `1825aa7cde6ac8e8bdb6e2adedbe98ebc8bff87bf9c3c8b8bd1524a3a6afdf4b`
- Candidate netlist SHA-256: `834b6ab7a0ef180c638987f5bcd1a728c53f026cafe4fc35c2adc98f20f9853e`
- Liberty SHA-256: `ec0e1067a35c8bf20b11e58d1e8ac53326067e4dac84a125cc1b917a3518d0d9`
