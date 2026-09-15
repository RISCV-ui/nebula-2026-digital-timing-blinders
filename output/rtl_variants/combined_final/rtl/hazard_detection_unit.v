`timescale 1ns / 1ps

// Forwarding and interlock control for the 5-stage pipeline.
//
// This was rewritten to fix four real defects in the original:
//
//  1. The stall outputs were driven twice -- once by the multiplier block
//     and again by the opcode case below it, whose default branch reset
//     them to 0. Any opcode not listed in the case silently cancelled an
//     in-flight multiply stall.
//  2. mul_busy was declared, connected, and never read; the stall condition
//     used a start pulse instead, so it did not cover the whole latency.
//  3. Forwarding was only decoded for R-type, I-type ALU and branch. Stores
//     and JALR fell through to the default branch, which cleared every
//     forwarding select -- so a store of a just-computed value wrote stale
//     register data to memory.
//  4. The load-use interlock keyed off the *decode* stage opcode being a
//     load, which is the wrong instruction: the hazard is a load already in
//     EX whose destination the decoding instruction needs. It also only
//     checked rs1, missing every rs2 dependency.
//
// A fifth change: the memory-wait interlock (mem_data_valid /
// stall_ex_mem_pipe) is new, and exists because the core's data memory moved
// out onto the bus behind the d-cache. See the block near the stall outputs.
//
// The interlock now keys off the EX-stage memory controls (mem_en_ex_stage
// with mem_wr_ex_stage low = a load in EX), which is why those two ports
// were added.
//
// Naming note: the opcode port is the DECODE stage opcode -- it always was,
// processor_top passes opcode_id -- and is named that way now.

module hazard_detection_unit(src_reg_1_addr,src_reg_2_addr,    /// in
                              dest_reg_addr_ex,dest_reg_addr_mem,dest_reg_addr_wb, // in
                              opcode_id_stage, //// in
                              mul_start_ex,
                              mul_busy,mul_done, /// in
                              mem_en_mem_stage,   /// in  from mem stage
                              mem_data_valid,     /// in  from the d-cache read buffer
                              mem_en_ex_stage,mem_wr_ex_stage, /// in from ex stage
                              branch_predictor_result_if,
                              branch_result_ex,

                              wen_ex,wen_mem,wen_wb, /// in  does that stage actually write a register
                              alu_src_1,alu_src_2,   /// out
                              mem_src_1,mem_src_2,
                              wb_src_1,wb_src_2,
                              stall_pc,
                              stall_if_id_pipe,
                              stall_id_ex_pipe,
                              stall_ex_mem_pipe,
                              flush_pc,
                              flush_if_id_pipe,
                              flush_id_ex_pipe,
                              csr_hazard

                               );


input [4:0] src_reg_1_addr,src_reg_2_addr;
input [4:0] dest_reg_addr_ex,dest_reg_addr_mem;
input [4:0] dest_reg_addr_wb;
// A non-zero destination register number is not on its own proof that a stage
// will write it: stores carry rs2 in rd_reg_out and CSR/branch slots leave
// stale values there. Forwarding matched on the register number alone, so a
// store sitting in WB forwarded its ADDRESS into the next instruction that read
// the same register -- lw x9,4(x2) took x2 from a store to x2 and computed the
// wrong address. Every forward is now qualified by the producer's own write
// enable.
input wen_ex,wen_mem,wen_wb;
input [6:0] opcode_id_stage;
input  mul_busy,mul_done;
input mem_en_mem_stage;
input mem_data_valid;
input mem_en_ex_stage,mem_wr_ex_stage;
input mul_start_ex;
input branch_predictor_result_if;
input branch_result_ex;


output alu_src_1,alu_src_2;
output mem_src_1,mem_src_2;
output wb_src_1,wb_src_2;
output stall_pc;
output stall_if_id_pipe;
output stall_id_ex_pipe;
output stall_ex_mem_pipe;
output flush_pc;
output flush_if_id_pipe;
output flush_id_ex_pipe;

// A CSR instruction takes its rs1 operand straight out of the register file in
// the DECODE stage, and the csr_regfile it writes also lives there. None of
// the forwarding paths above can reach it -- they all land in EX. So a CSR
// write whose operand was produced by any of the three instructions in front
// of it read a stale (at reset, x) register. csrrw mtvec,x5 right after
// addi x5,x0,handler wrote x into mtvec, and the first interrupt vectored the
// core to an unknown address.
//
// This tells the decode stage to hold its csr write off while that operand is
// still in flight; the interlock below stalls until it has landed.
output csr_hazard;


//// opcodes

parameter op_rtype  = 7'b0110011;
parameter op_itype  = 7'b0010011;
parameter op_load   = 7'b0000011;
parameter op_store  = 7'b0100011;
parameter op_branch = 7'b1100011;
parameter op_jalr   = 7'b1100111;
parameter op_system = 7'b1110011;


//// which source registers the decoding instruction actually reads.
//// Everything else (JAL, LUI, AUIPC) reads neither, so it must not
//// forward: a stale rd match would otherwise steer a bogus operand in.

wire reads_rs1;
wire reads_rs2;

assign reads_rs1 = (opcode_id_stage == op_rtype)  ||
                   (opcode_id_stage == op_itype)  ||
                   (opcode_id_stage == op_load)   ||
                   (opcode_id_stage == op_store)  ||
                   (opcode_id_stage == op_branch) ||
                   (opcode_id_stage == op_jalr)   ||
                   (opcode_id_stage == op_system);

assign reads_rs2 = (opcode_id_stage == op_rtype)  ||
                   (opcode_id_stage == op_store)  ||
                   (opcode_id_stage == op_branch);


//// forwarding, priority EX > MEM > WB: the youngest producer holds the
//// value the consumer wants. x0 is never forwarded, it is hardwired to 0.

wire hit_ex_1, hit_mem_1, hit_wb_1;
wire hit_ex_2, hit_mem_2, hit_wb_2;

// A load sitting in EX has produced an ADDRESS, not a value -- there is
// nothing yet to forward from that stage. Every EX forward is therefore
// qualified by !load_in_ex, and the consumer picks the value up from MEM one
// cycle later instead. Without this, sw x3,4(x2) directly after lw x3,0(x2)
// forwarded the load's address and stored 0x40.
wire load_in_ex;
assign load_in_ex = mem_en_ex_stage && !mem_wr_ex_stage && (dest_reg_addr_ex != 5'd0);

assign hit_ex_1  = reads_rs1 && wen_ex && !load_in_ex  && (src_reg_1_addr == dest_reg_addr_ex)  && (dest_reg_addr_ex  != 5'd0);
assign hit_mem_1 = reads_rs1 && wen_mem && (src_reg_1_addr == dest_reg_addr_mem) && (dest_reg_addr_mem != 5'd0);
assign hit_wb_1  = reads_rs1 && wen_wb  && (src_reg_1_addr == dest_reg_addr_wb)  && (dest_reg_addr_wb  != 5'd0);

assign hit_ex_2  = reads_rs2 && wen_ex && !load_in_ex  && (src_reg_2_addr == dest_reg_addr_ex)  && (dest_reg_addr_ex  != 5'd0);
assign hit_mem_2 = reads_rs2 && wen_mem && (src_reg_2_addr == dest_reg_addr_mem) && (dest_reg_addr_mem != 5'd0);
assign hit_wb_2  = reads_rs2 && wen_wb  && (src_reg_2_addr == dest_reg_addr_wb)  && (dest_reg_addr_wb  != 5'd0);

assign alu_src_1 = hit_ex_1;
assign mem_src_1 = hit_mem_1 && !hit_ex_1;
assign wb_src_1  = hit_wb_1  && !hit_ex_1 && !hit_mem_1;

assign alu_src_2 = hit_ex_2;
assign mem_src_2 = hit_mem_2 && !hit_ex_2;
assign wb_src_2  = hit_wb_2  && !hit_ex_2 && !hit_mem_2;


//// load-use interlock
////
//// A load in EX has not read memory yet, so its result cannot be forwarded
//// from EX. Hold decode for one cycle; by then the load is in MEM and the
//// MEM forwarding path above covers it.

wire load_use;

// The !mem_en_mem_stage term that used to be here cancelled the bubble
// whenever ANY memory access occupied the MEM stage -- an unrelated store
// stalling on the bus was enough. The consumer then went straight past the
// load in EX with a stale operand. The interlock depends only on the load in
// EX and the register the decoding instruction reads.
assign load_use = load_in_ex &&
                  ((reads_rs1 && (src_reg_1_addr == dest_reg_addr_ex)) ||
                   (reads_rs2 && (src_reg_2_addr == dest_reg_addr_ex)));


//// multiplier interlock
////
//// mul_busy covers the whole pipelined latency; the start term catches the
//// launch cycle, before busy has come up.

wire mul_stall;

assign mul_stall = mul_busy || (mul_start_ex && !mul_done);


//// memory-wait interlock
////
//// The data memory is no longer inside the core -- an access goes out over
//// the master port to the d-cache read buffer, which answers with
//// mem_data_valid. The whole front of the pipeline holds until it does, and
//// EX/MEM holds too, so the request stays asserted on the bus rather than
//// being shifted out from under the memory stage while it is still in
//// flight. This is the only stall that reaches EX/MEM: a load-use or
//// multiply bubble has to be allowed to drain through it.

wire mem_stall;

assign mem_stall = mem_en_mem_stage && !mem_data_valid;


// A load-use hazard is resolved with a BUBBLE, not by holding ID/EX. Holding
// ID/EX leaves the load itself sitting in EX, which keeps load_in_ex asserted
// and re-issues the same load every cycle -- the pipeline never moved again.
// Flushing ID/EX lets the load walk on into MEM (where the MEM forwarding path
// picks it up) while PC and IF/ID hold, so the consumer re-decodes behind it.
//
// The bubble is suppressed while mem_stall is active: EX/MEM is frozen then,
// so the load cannot advance and flushing ID/EX would simply delete it.

// CSR read-after-write interlock. Resolved as a bubble, exactly like
// load_use: PC and IF/ID hold while ID/EX is flushed, so the producer walks on
// through WB and the CSR instruction re-decodes behind it with the register
// file finally holding the right value.
wire csr_use;

assign csr_use = (opcode_id_stage == op_system) && (src_reg_1_addr != 5'd0) &&
                 ((wen_ex  && (src_reg_1_addr == dest_reg_addr_ex))  ||
                  (wen_mem && (src_reg_1_addr == dest_reg_addr_mem)) ||
                  (wen_wb  && (src_reg_1_addr == dest_reg_addr_wb)));

assign csr_hazard = csr_use;

assign stall_pc          = load_use || csr_use || mul_stall || mem_stall;
assign stall_if_id_pipe  = load_use || csr_use || mul_stall || mem_stall;
assign stall_id_ex_pipe  = mul_stall || mem_stall;
assign stall_ex_mem_pipe = mem_stall;


//// branch misprediction: squash the instructions fetched down the wrong path.
////
//// This is resolved off the EX-stage branch result. processor_top used to pass
//// the MEM-stage copy, so the flush arrived a cycle after the fetch stage had
//// already redirected, and the wrong-path instruction in between committed --
//// a taken beq still executed the instruction it was branching over.
////
//// flush_pc is kept as an output for the fetch/redirect bookkeeping but no
//// longer gates the pc enable; see processor_top.

assign flush_pc         = branch_result_ex ^ branch_predictor_result_if;
assign flush_if_id_pipe = branch_result_ex ^ branch_predictor_result_if;
assign flush_id_ex_pipe = (branch_result_ex ^ branch_predictor_result_if) ||
                          (load_use && !mem_stall);

endmodule
