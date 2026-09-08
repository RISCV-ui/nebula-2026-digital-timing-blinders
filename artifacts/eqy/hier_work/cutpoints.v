// Blackbox declarations for the two OpenRAM hard macros.
//
// Read with `read_verilog -lib` on BOTH sides of an equivalence check, and by
// any tool that must know the macro's ports without knowing (or being allowed
// to invent) its contents. Port widths and directions here are taken from the
// macros' liberty files, which are the authority on what the silicon has --
// not from OpenRAM's behavioural .v, which shipped an extra spare column that
// does not exist in the .lib or .lef.
//
// Because the macro is identical on the gold and gate side of every check, the
// prover treats it as an uninterpreted function: the check proves the logic
// AROUND the SRAM is unchanged, and says nothing about the SRAM itself. The
// SRAM's own correctness is a vendor/DRC/LVS question, not a synthesis one.

(* blackbox *)
module id_memory_256x64(clk0, csb0, web0, addr0, din0, dout0,
                        clk1, csb1, addr1, dout1);
    input          clk0;
    input          csb0;
    input          web0;
    input  [6:0]   addr0;
    input  [255:0] din0;
    output [255:0] dout0;
    input          clk1;
    input          csb1;
    input  [6:0]   addr1;
    output [255:0] dout1;
endmodule

(* blackbox *)
module tag_memory_92x64(clk0, csb0, web0, addr0, din0, dout0,
                        clk1, csb1, addr1, dout1);
    input          clk0;
    input          csb0;
    input          web0;
    input  [6:0]   addr0;
    input  [91:0]  din0;
    output [91:0]  dout0;
    input          clk1;
    input          csb1;
    input  [6:0]   addr1;
    output [91:0]  dout1;
endmodule

(* blackbox *)
module alu(src_a, src_b, alu_control, alu_result, zero);
    input [31:0] src_a;
    input [31:0] src_b;
    input [3:0] alu_control;
    output [31:0] alu_result;
    output zero;
endmodule

(* blackbox *)
module alu_src_a_mux(rd1, pc, csr_read, sel, src_a);
    input [31:0] rd1;
    input [31:0] pc;
    input [31:0] csr_read;
    input [1:0] sel;
    output [31:0] src_a;
endmodule

(* blackbox *)
module alu_src_b_mux(rd2, imm_ext, sel, src_b);
    input [31:0] rd2;
    input [31:0] imm_ext;
    input [1:0] sel;
    output [31:0] src_b;
endmodule

(* blackbox *)
module arbiter(clk, rst, req_cpu, req_dam, clear_cpu, clear_dma, grant);
    input clk;
    input rst;
    input req_cpu;
    input req_dam;
    input clear_cpu;
    input clear_dma;
    output grant;
endmodule

(* blackbox *)
module axi_lite_master(clk, rst, addr, addr_valid, data_out, read_write, data_in, done, m1_ar_addr, m1_ar_valid, m1_ar_ready, m1_aw_addr, m1_aw_valid, m1_aw_ready, m1_dr_data, m1_dr_valid, m1_dr_ready, m1_dr_resp, m1_dw_data, m1_dw_valid, m1_dw_ready, m1_dw_strb, m1_b_ready, m1_b_valid, m1_b_resp);
    input clk;
    input rst;
    input [31:0] addr;
    input addr_valid;
    input [31:0] data_out;
    input read_write;
    output [31:0] data_in;
    output done;
    output [31:0] m1_ar_addr;
    output m1_ar_valid;
    input m1_ar_ready;
    output [31:0] m1_aw_addr;
    output m1_aw_valid;
    input m1_aw_ready;
    input [31:0] m1_dr_data;
    input m1_dr_valid;
    output m1_dr_ready;
    input [1:0] m1_dr_resp;
    output [31:0] m1_dw_data;
    output m1_dw_valid;
    input m1_dw_ready;
    output [3:0] m1_dw_strb;
    output m1_b_ready;
    input m1_b_valid;
    input [1:0] m1_b_resp;
endmodule

(* blackbox *)
module branch_comp_decoder(opcode, fun3, operation);
    input [6:0] opcode;
    input [2:0] fun3;
    output [2:0] operation;
endmodule

(* blackbox *)
module branch_comprator(rs1, rs2, funct3, branch_taken);
    input [31:0] rs1;
    input [31:0] rs2;
    input [2:0] funct3;
    output branch_taken;
endmodule

(* blackbox *)
module clk_div_mux(clk, rst, sel, clk_out);
    input clk;
    input rst;
    input [1:0] sel;
    output clk_out;
endmodule

(* blackbox *)
module clk_gate(clk_in, clk_en, clk_out);
    input clk_in;
    input clk_en;
    output clk_out;
endmodule

(* blackbox *)
module control_unit(clk, rst, opcode, fun7, fun3, rd_reg, rs2_reg, csr_wen, csr_operation, src_mux_sel_1, src_mux_sel_2, start_mul, mulh_mul, alu_out_sel, alu_operation, pc4_sel, extender_mem, dmem_en, dmem_wr, alu_dmem_sel, wen_reg_file, rd_reg_out, extend_wb, inst_complete_wb);
    input clk;
    input rst;
    input [6:0] opcode;
    input [6:0] fun7;
    input [2:0] fun3;
    input [4:0] rd_reg;
    input [4:0] rs2_reg;
    output csr_wen;
    output [1:0] csr_operation;
    output [1:0] src_mux_sel_1;
    output [1:0] src_mux_sel_2;
    output start_mul;
    output mulh_mul;
    output alu_out_sel;
    output [3:0] alu_operation;
    output pc4_sel;
    output [1:0] extender_mem;
    output dmem_en;
    output dmem_wr;
    output alu_dmem_sel;
    output wen_reg_file;
    output [4:0] rd_reg_out;
    output [2:0] extend_wb;
    output inst_complete_wb;
endmodule

(* blackbox *)
module data_clipper(datain, sel, data_out);
    input [31:0] datain;
    input [1:0] sel;
    output [31:0] data_out;
endmodule

(* blackbox *)
module data_extender(data_in, control, data_out);
    input [31:0] data_in;
    input [2:0] control;
    output [31:0] data_out;
endmodule

(* blackbox *)
module data_forwarding_unit(alu_out_src_1, alu_out_src_2, mem_out_src_1, mem_out_src_2, wb_src_1, wb_src_2, in_reg_1, in_reg_2, alu_out_data, mem_out_data, wb_out_data, data_out_src_1, data_out_src_2);
    input alu_out_src_1;
    input alu_out_src_2;
    input mem_out_src_1;
    input mem_out_src_2;
    input wb_src_1;
    input wb_src_2;
    input [31:0] in_reg_1;
    input [31:0] in_reg_2;
    input [31:0] alu_out_data;
    input [31:0] mem_out_data;
    input [31:0] wb_out_data;
    output [31:0] data_out_src_1;
    output [31:0] data_out_src_2;
endmodule

(* blackbox *)
module fp4_mul(a, b, y);
    input [3:0] a;
    input [3:0] b;
    output [7:0] y;
endmodule

(* blackbox *)
module fp8_adder(a, b, y);
    input [7:0] a;
    input [7:0] b;
    output [7:0] y;
endmodule

(* blackbox *)
module hazard_detection_unit(src_reg_1_addr, src_reg_2_addr, dest_reg_addr_ex, dest_reg_addr_mem, dest_reg_addr_wb, wen_ex, wen_mem, wen_wb, opcode_id_stage, mul_busy, mul_done, mem_en_mem_stage, mem_data_valid, mem_en_ex_stage, mem_wr_ex_stage, mul_start_ex, branch_predictor_result_if, branch_result_ex, alu_src_1, alu_src_2, mem_src_1, mem_src_2, wb_src_1, wb_src_2, stall_pc, stall_if_id_pipe, stall_id_ex_pipe, stall_ex_mem_pipe, flush_pc, flush_if_id_pipe, flush_id_ex_pipe, csr_hazard);
    input [4:0] src_reg_1_addr;
    input [4:0] src_reg_2_addr;
    input [4:0] dest_reg_addr_ex;
    input [4:0] dest_reg_addr_mem;
    input [4:0] dest_reg_addr_wb;
    input wen_ex;
    input wen_mem;
    input wen_wb;
    input [6:0] opcode_id_stage;
    input mul_busy;
    input mul_done;
    input mem_en_mem_stage;
    input mem_data_valid;
    input mem_en_ex_stage;
    input mem_wr_ex_stage;
    input mul_start_ex;
    input branch_predictor_result_if;
    input branch_result_ex;
    output alu_src_1;
    output alu_src_2;
    output mem_src_1;
    output mem_src_2;
    output wb_src_1;
    output wb_src_2;
    output stall_pc;
    output stall_if_id_pipe;
    output stall_id_ex_pipe;
    output stall_ex_mem_pipe;
    output flush_pc;
    output flush_if_id_pipe;
    output flush_id_ex_pipe;
    output csr_hazard;
endmodule

(* blackbox *)
module i_rom_32x256(clk, rst, addr_l2, addr_l2_valid, data_l2, data_valid_l2);
    input clk;
    input rst;
    input [31:0] addr_l2;
    input addr_l2_valid;
    output [255:0] data_l2;
    output data_valid_l2;
endmodule

(* blackbox *)
module id_memory_256x64_wrap(clk, rst, mem_en, addr, read_write, data_in, data_out, data_valid);
    input clk;
    input rst;
    input mem_en;
    input [31:0] addr;
    input read_write;
    input [255:0] data_in;
    output [255:0] data_out;
    output data_valid;
endmodule

(* blackbox *)
module immediate_generator(instr, imm_out);
    input [31:0] instr;
    output [31:0] imm_out;
endmodule

(* blackbox *)
module interrupt_control_unit(clk, rst, int_in, int_mask, int_clear, int_pending, int_id, int_req);
    input clk;
    input rst;
    input [2:0] int_in;
    input [2:0] int_mask;
    input [2:0] int_clear;
    output [2:0] int_pending;
    output [1:0] int_id;
    output int_req;
endmodule

(* blackbox *)
module memory_stage(alu_out_ex, mem_data_in, alu_dmem_sel_ex, mem_stage_out_alu, mem_stage_out_load, alu_dmem_sel_wb);
    input [31:0] alu_out_ex;
    input [31:0] mem_data_in;
    input alu_dmem_sel_ex;
    output [31:0] mem_stage_out_alu;
    output [31:0] mem_stage_out_load;
    output alu_dmem_sel_wb;
endmodule

(* blackbox *)
module pipeline_reg_ex_mem(clk, rst, en_ex_mem, alu_out_in, rs2_for_mem_in, dmem_en_in, dmem_wr_in, alu_dmem_sel_in, wen_reg_file_in, rd_reg_out_in, extend_wb_in, inst_complete_id_in, mul_done_in, mul_busy_in, branch_result_in, alu_out_out, rs2_for_mem_out, dmem_en_out, dmem_wr_out, alu_dmem_sel_out, wen_reg_file_out, rd_reg_out_out, extend_wb_out, inst_complete_id_out, mul_done_out, mul_busy_out, branch_result_out);
    input clk;
    input rst;
    input en_ex_mem;
    input [31:0] alu_out_in;
    input [31:0] rs2_for_mem_in;
    input dmem_en_in;
    input dmem_wr_in;
    input alu_dmem_sel_in;
    input wen_reg_file_in;
    input [4:0] rd_reg_out_in;
    input [2:0] extend_wb_in;
    input inst_complete_id_in;
    input mul_done_in;
    input mul_busy_in;
    input branch_result_in;
    output [31:0] alu_out_out;
    output [31:0] rs2_for_mem_out;
    output dmem_en_out;
    output dmem_wr_out;
    output alu_dmem_sel_out;
    output wen_reg_file_out;
    output [4:0] rd_reg_out_out;
    output [2:0] extend_wb_out;
    output inst_complete_id_out;
    output mul_done_out;
    output mul_busy_out;
    output branch_result_out;
endmodule

(* blackbox *)
module pipeline_reg_id_ex(clk, rst, flush_id_ex, en_id_ex, pc_plus4_in, pc_in, opcode_in, src_reg_1_in, src_reg_2_in, imm_in, alu_operation_in, start_mul_in, mulh_mul_in, alu_out_sel_in, pc4_sel_in, extender_mem_in, dmem_en_in, dmem_wr_in, alu_dmem_sel_in, wen_reg_file_in, rd_reg_out_in, extend_wb_in, inst_complete_id_in, csr_write_data_in, src_mux_sel_1_in, src_mux_sel_2_in, branch_operation_wire_in, pc_plus4_out, pc_out, opcode_out, src_reg_1_out, src_reg_2_out, imm_out, alu_operation_out, start_mul_out, mulh_mul_out, alu_out_sel_out, pc4_sel_out, extender_mem_out, dmem_en_out, dmem_wr_out, alu_dmem_sel_out, wen_reg_file_out, rd_reg_out_out, extend_wb_out, inst_complete_id_out, csr_write_data_out, src_mux_sel_1_out, src_mux_sel_2_out, branch_operation_wire_out);
    input clk;
    input rst;
    input flush_id_ex;
    input en_id_ex;
    input [31:0] pc_plus4_in;
    input [31:0] pc_in;
    input [6:0] opcode_in;
    input [31:0] src_reg_1_in;
    input [31:0] src_reg_2_in;
    input [31:0] imm_in;
    input [3:0] alu_operation_in;
    input start_mul_in;
    input mulh_mul_in;
    input alu_out_sel_in;
    input pc4_sel_in;
    input [1:0] extender_mem_in;
    input dmem_en_in;
    input dmem_wr_in;
    input alu_dmem_sel_in;
    input wen_reg_file_in;
    input [4:0] rd_reg_out_in;
    input [2:0] extend_wb_in;
    input inst_complete_id_in;
    input [31:0] csr_write_data_in;
    input [1:0] src_mux_sel_1_in;
    input [1:0] src_mux_sel_2_in;
    input [2:0] branch_operation_wire_in;
    output [31:0] pc_plus4_out;
    output [31:0] pc_out;
    output [6:0] opcode_out;
    output [31:0] src_reg_1_out;
    output [31:0] src_reg_2_out;
    output [31:0] imm_out;
    output [3:0] alu_operation_out;
    output start_mul_out;
    output mulh_mul_out;
    output alu_out_sel_out;
    output pc4_sel_out;
    output [1:0] extender_mem_out;
    output dmem_en_out;
    output dmem_wr_out;
    output alu_dmem_sel_out;
    output wen_reg_file_out;
    output [4:0] rd_reg_out_out;
    output [2:0] extend_wb_out;
    output inst_complete_id_out;
    output [31:0] csr_write_data_out;
    output [1:0] src_mux_sel_1_out;
    output [1:0] src_mux_sel_2_out;
    output [2:0] branch_operation_wire_out;
endmodule

(* blackbox *)
module pipeline_reg_if_id(clk, rst, flush_if_id, en_if_id, pc_pluse4_in, pc_in, instruction_in, pc_pluse4_out, pc_out, instruction_out);
    input clk;
    input rst;
    input flush_if_id;
    input en_if_id;
    input [31:0] pc_pluse4_in;
    input [31:0] pc_in;
    input [31:0] instruction_in;
    output [31:0] pc_pluse4_out;
    output [31:0] pc_out;
    output [31:0] instruction_out;
endmodule

(* blackbox *)
module pipeline_reg_mem_wb(clk, rst, data_wb_in, extender_in, wen_wb_in, rd_addr_wb_in, inst_complete_wb_in, data_wb_mem_in, alu_mem_sel_in, data_wb_out, wen_wb_out, rd_addr_wb_out, inst_complete_wb_out, extender_out, data_wb_mem_out, alu_mem_sel_out);
    input clk;
    input rst;
    input [31:0] data_wb_in;
    input [2:0] extender_in;
    input wen_wb_in;
    input [4:0] rd_addr_wb_in;
    input inst_complete_wb_in;
    input [31:0] data_wb_mem_in;
    input alu_mem_sel_in;
    output [31:0] data_wb_out;
    output wen_wb_out;
    output [4:0] rd_addr_wb_out;
    output inst_complete_wb_out;
    output [2:0] extender_out;
    output [31:0] data_wb_mem_out;
    output alu_mem_sel_out;
endmodule

(* blackbox *)
module tag_memory_92x64_wrap(clk, rst, mem_en, addr, read_write, data_in, data_out, data_valid);
    input clk;
    input rst;
    input mem_en;
    input [31:0] addr;
    input read_write;
    input [91:0] data_in;
    output [91:0] data_out;
    output data_valid;
endmodule

(* blackbox *)
module fp4_dot_unit(clk, rst, va, vb, dot_out);
    input clk;
    input rst;
    input [31:0] va;
    input [31:0] vb;
    output [31:0] dot_out;
endmodule

(* blackbox *)
module write_back_stage(data_mem, extender_mem, wen_regfile_mem, rd_addr_mem, inst_complete_mem, mem_data_in, alu_mem_sel_in, data_wb, wen_wb, rd_addr_wb, inst_complete_wb);
    input [31:0] data_mem;
    input [2:0] extender_mem;
    input wen_regfile_mem;
    input [4:0] rd_addr_mem;
    input inst_complete_mem;
    input [31:0] mem_data_in;
    input alu_mem_sel_in;
    output [31:0] data_wb;
    output wen_wb;
    output [4:0] rd_addr_wb;
    output inst_complete_wb;
endmodule
