`timescale 1ns / 1ps

module processor_top(clk,rst,trap_in_id,mret_in_id,pc_if_id_pipe_debug,alu_out_mem_stage_debug,
                                   wb_data_debug,wb_addr_debug,
                                   addr_valid_m_axi,read_write_axi,
                                   addr_m_axi,data_out_m_axi,   data_in_m_axi,
                                   data_valid_m_axi );
input clk;
input rst;
input trap_in_id;
input mret_in_id;


output [31:0] alu_out_mem_stage_debug;
output [31:0] pc_if_id_pipe_debug; 
output [31:0] wb_data_debug;
output [4:0] wb_addr_debug;

output addr_valid_m_axi,read_write_axi;
output [31:0]addr_m_axi,data_out_m_axi;
input   [31:0]data_in_m_axi;

// Response valid for the data-memory access presented on the master port.
// Driven by the d-cache read buffer at the SoC level. The pipeline holds
// until it asserts.
input data_valid_m_axi;



///// wire decleration

//// if stage  wirzz
wire [6:0]opcode_ex;
wire [31:0] pc_ex;

wire [31:0]pc_pluse4_if,pc_if,instruction_if;
wire  stall_flush_pc;

/////


//// id stage input wires 

wire [31:0]pc_pluse4_out,pc_out,instruction_out;
wire branch_pred_result;

//// id stage output wires

wire [31:0] pc_plus4_id;
wire [31:0] pc_id;
wire [6:0]  opcode_id;
wire [31:0] reg_1_data;
wire [31:0] reg_2_data;
wire [31:0] imm_data;
wire [3:0]  alu_operation;
wire start_mul,mulh_mul;
wire alu_out_sel,pc4_sel;
wire [1:0] extender_mem;
wire dmem_en,dmem_wr,alu_dmem_sel;
wire wen_reg_file;
wire [4:0] rd_reg_out;
wire [2:0]extend_wb;
wire inst_complete_id;
wire branch_result;

wire [1:0]src_mux_sel_1,src_mux_sel_2;
wire [2:0]branch_operation_wire;

//// ex sage 

/// ex input wire 
wire [31:0] pc_plus4_out;                              
wire [31:0] pc_out_w;                                    
wire  [6:0]  opcode_out;                             
wire [31:0] src_reg_1_out;                          
wire [31:0] src_reg_2_out;                          
wire [31:0] imm_id_out;                            
wire [3:0]  alu_operation_out;                  
wire start_mul_out,mulh_mul_out;                
wire alu_out_sel_out,pc4_sel_out;               
wire [1:0] extender_mem_out;                   
wire dmem_en_out,dmem_wr_out,alu_dmem_sel_out;   
wire wen_reg_file_out;                         
wire [4:0] rd_reg_out_out;                     
wire [2:0]extend_wb_out;                       
wire inst_complete_id_out;                     

wire alu_zero;

wire [31:0]csr_write_data_out;    
wire [1:0]src_mux_sel_1_out;    
wire [1:0]src_mux_sel_2_out;     
wire [2:0]branch_operation_wire_out ;


wire [31:0]src_reg_1;
wire [31:0]src_reg_2;


//// ex out signals

wire [31:0] alu_out_ex;  //// for mem stage 
//wire branch_result_ex;
//wire [6:0]opcode_ex;
//wire [31:0]pc_ex;
wire mul_done_ex,mul_busy_ex;
wire [31:0]rs2_for_mem_ex;  /// for mem stage 

wire [31:0]alu_out_mm;
wire [31:0]alu_mul_out_forwd;


//// mem stage 

//  mem in 


wire [31:0] mem_stage_alu_out_mm;
wire [31:0] rs2_cliped_mm;
wire [31:0] mem_stage_load_out_mm;
wire mem_stage_alu_load_sel_mm;
wire dmem_en_mm;
wire dmem_wr_mm;
wire alu_dmem_sel_mm;
wire mul_done_mm;
wire mul_busy_mm;
wire branch_result_out_mm;

 
 



wire wen_reg_file_mm;       
wire [4:0]rd_reg_out_mm;         
wire [2:0]extend_wb_mm;          
wire inst_complete_id_mm;    





   
//// mem out 



/////  wb 

wire [31:0] data_wb_ww;     
//wire [31:0]extender_ww;
wire wen_wb_ww;
wire [4:0]rd_addr_ww;
wire  inst_complete_wb_ww;
wire [2:0]extender_ww;
wire [31:0]data_wb_mem_ww;
wire alu_mem_sel_wb_ww;

//ire [4:0]dest_reg_addr_wb,wb_data_wb,we_regfile_wb,inst_complete_wb;

wire  wen_wb;
wire [31:0]data_wb;
wire [4:0]rd_addr_wb;
wire inst_complete_wb;

//////   
/// pipeline reg en wires 


////  hadard unit wires
///  output 
wire alu_src_1;
wire alu_src_2;
wire mem_src_1;
wire mem_src_2;
wire wb_src_1;
wire wb_src_2;
wire stall_pc;
wire stall_if_id_pipe;
wire stall_id_ex_pipe;
wire stall_ex_mem_pipe;
wire flush_pc;
wire ifetch_stall;
wire flush_if_id_pipe;
wire flush_id_ex_pipe;


/// input to hazard unit 

wire [4:0]src_reg_1_addr;
wire [4:0]src_reg_2_addr;


assign src_reg_1_addr = instruction_out[19:15];
assign src_reg_2_addr = instruction_out[24:20];  







///// ex input src 1 and 2  from forwarding unit 
wire [31:0]data_out_src_1,data_out_src_2;
 

///// csr  
//wire trap_in_id;
//wire mret_in_id;
wire [31:0] trap_cause_in_id;
wire [31:0]mepc_out_id; /// pc return                          
wire [31:0] mtvec_out_id; /// hamdler address                   
wire csr_hazard;  /// rs1 of a decoding CSR instruction is still in flight
wire  mie_out_id; 
wire [31:0]csr_data_id;



assign trap_cause_in_id = 32'd200;









//////  modules instantiation



instruction_fetch_stage  if_stage( clk,rst,stall_flush_pc
                                   ,pc_ex,alu_mul_out_forwd,branch_result,opcode_ex,
                                   pc_pluse4_if,pc_if,instruction_if,
                                   trap_in_id,mret_in_id,
                                   mepc_out_id,mtvec_out_id,
                                   branch_pred_result,
                                   ifetch_stall
                                   
                                   );


pipeline_reg_if_id   pipeline_if_id(clk,rst,flush_if_id_pipe,stall_if_id_pipe,    /// reg control signals
                                   pc_pluse4_if,pc_if,instruction_if, /// in 
                                  pc_pluse4_out, pc_out,instruction_out);



instruction_decode_stage id_stage(clk,rst,pc_pluse4_out,pc_out,instruction_out,rd_addr_wb,data_wb,wen_wb,inst_complete_wb,    /// input to id stage 
                                pc_plus4_id,pc_id,opcode_id,reg_1_data,reg_2_data,imm_data,  /// ex stage data 
                                src_mux_sel_1,src_mux_sel_2,branch_operation_wire,
                                alu_operation,start_mul,mulh_mul,alu_out_sel,pc4_sel,     /// ex stage control signals 
                                extender_mem,dmem_en,dmem_wr,alu_dmem_sel, ///  meem stage control signal 
                                wen_reg_file,rd_reg_out,extend_wb, ///  wb stage control signals 
                                inst_complete_id ,   /// instruction count out from id stage 
                               
                                
                                trap_in_id,   /// to trap from vic                  
                                trap_cause_in_id,  //// cause of trap from vic      
                                mret_in_id,   /// make 1 when trap handling complete      
                                mepc_out_id, /// pc return                          
                                mtvec_out_id, /// hamdler address                   
                                mie_out_id, /// global interrupt enable              
                                csr_data_id,
                                csr_hazard
 
                                  );

// What the MEM stage forwards. This used to be mem_stage_alu_out_mm, the raw
// ALU result -- which for a load is its ADDRESS. The load-use interlock lets a
// load reach MEM before its consumer decodes, and the consumer then took the
// address instead of the loaded value: sw x3,4(x2) right after lw x3,0(x2)
// stored 0x40 (the address) rather than the data. Select the same way the
// write-back stage does one cycle later, and put it through the same extender
// so a forwarded lb/lh is sign extended identically.
wire [31:0] mem_fwd_raw;
wire [31:0] mem_fwd_data;
assign mem_fwd_raw = mem_stage_alu_load_sel_mm ? mem_stage_load_out_mm
                                               : mem_stage_alu_out_mm;
data_extender mem_fwd_ext(mem_fwd_raw, extend_wb_mm, mem_fwd_data);

data_forwarding_unit data_fwd( reg_1_data,reg_2_data,alu_src_1,alu_src_2,mem_src_1,mem_src_2,wb_src_1,wb_src_2, /// imput select
                            alu_mul_out_forwd,mem_fwd_data,data_wb,   /// input data
                            data_out_src_1,data_out_src_2
                            );                                  
                                  


pipeline_reg_id_ex  pipeline_id_ex(clk,rst,flush_id_ex_pipe,stall_id_ex_pipe, 
                           pc_plus4_id ,pc_id,opcode_id,    
                         data_out_src_1,data_out_src_2,imm_data,
                         csr_data_id,
                         src_mux_sel_1,
                         src_mux_sel_2,
                         branch_operation_wire,
                           alu_operation,        
                           start_mul,mulh_mul,
                           alu_out_sel,pc4_sel,
                           extender_mem,
                           dmem_en,dmem_wr,alu_dmem_sel,
                           wen_reg_file,
                           rd_reg_out,
                           extend_wb,
                           inst_complete_id,
                          
                            
                            
                         pc_plus4_out,   
                         pc_out_w,          
                         opcode_out,      
                         src_reg_1_out,   
                         src_reg_2_out,   
                         imm_id_out,  
                         csr_write_data_out,
                         src_mux_sel_1_out,
                         src_mux_sel_2_out,
                         branch_operation_wire_out,   
                         alu_operation_out,
                         start_mul_out,mulh_mul_out,
                         alu_out_sel_out,pc4_sel_out,
                         extender_mem_out,
                         dmem_en_out,dmem_wr_out,alu_dmem_sel_out,
                         wen_reg_file_out,
                         rd_reg_out_out,
                         extend_wb_out,
                         inst_complete_id_out
                        
                          );


//// src mux 1 
alu_src_a_mux  src_mx1(src_reg_1_out,  /// rs1 data
                       pc_out_w,      /// pc 
                       csr_write_data_out, /// csr reg file output data
                       src_mux_sel_1_out, // select line
                       src_reg_1 /// output to ex stage
                       );

/// src mux 2 
alu_src_b_mux  src_mx2(src_reg_2_out,  /// rs2
                       imm_id_out,  /// imm value 
                       src_mux_sel_2_out, /// sel
                       src_reg_2   /// output to alu 
                        );


execution_stage  ex_stage(clk,rst,pc_plus4_out,pc_out_w,opcode_out,src_reg_1,src_reg_2,//// input 
                        src_reg_2_out,extender_mem_out,           //// input 
                        alu_operation_out,start_mul_out,mulh_mul_out,alu_out_sel_out,pc4_sel_out, // ex stage control 
                        alu_out_ex,alu_zero,///output of ex stage
                        opcode_ex,pc_ex,
                        mul_done_ex,mul_busy_ex,
                        rs2_for_mem_ex ,
                        alu_mul_out_forwd  /// 
                         );
                         
///// branch comprator 

branch_comprator branch_comp_id(src_reg_1_out,
                                src_reg_2_out,
                                branch_operation_wire_out,
                                branch_result
                                 );                         
                         
                         



pipeline_reg_ex_mem pipeline_ex_mem(  clk,rst,stall_ex_mem_pipe,
                           alu_out_ex,
                           rs2_for_mem_ex,
                           dmem_en_out,dmem_wr_out,alu_dmem_sel_out,
                           wen_reg_file_out,
                           rd_reg_out_out,
                           extend_wb_out,
                           inst_complete_id_out,
                           mul_done_ex,
                           mul_busy_ex,
                           branch_result,
                           
                           
                           alu_out_mm,
                           rs2_cliped_mm,
                           dmem_en_mm,dmem_wr_mm,alu_dmem_sel_mm,
                           wen_reg_file_mm,
                           rd_reg_out_mm,
                           extend_wb_mm,
                           inst_complete_id_mm,
                            mul_done_mm,
                            mul_busy_mm,
                            branch_result_out_mm
                           
                           
                            );



// AXI master interface out of the memory stage. These outputs were declared
// and wired into axi_lite_master at the SoC level but never driven, leaving
// the core's whole external-memory path dangling. Driven here from the same
// memory-stage signals that address the local dmem, so a data-memory access
// is presented on the AXI master port in the same cycle.
// The request is held asserted until data_valid_m_axi comes back (see
// stall_ex_mem_pipe), and the returned data is what the memory stage hands to
// write-back. This is still a valid/hold handshake rather than a full AXI
// FSM: that FSM lives in l1_cache_axi_master, below the read buffer.
assign addr_m_axi       = alu_out_mm;
assign data_out_m_axi   = rs2_cliped_mm;
assign addr_valid_m_axi = dmem_en_mm;
assign read_write_axi   = dmem_wr_mm;


// Load data comes back over the master port now, not from a core-private
// dmem. While the access is still outstanding the write-back controls are
// forced inactive, so the MEM/WB register latches a bubble instead of
// repeatedly committing whatever happens to be on the bus. On the cycle the
// data is valid the real controls go through and the load commits.

wire wen_reg_file_mm_gated;
wire inst_complete_id_mm_gated;

assign wen_reg_file_mm_gated     = wen_reg_file_mm     && !stall_ex_mem_pipe;
assign inst_complete_id_mm_gated = inst_complete_id_mm && !stall_ex_mem_pipe;

memory_stage mem_stage(alu_out_mm,
                        data_in_m_axi,
                        alu_dmem_sel_mm,
                        mem_stage_alu_out_mm,
                        mem_stage_load_out_mm,
                        mem_stage_alu_load_sel_mm
                    );




pipeline_reg_mem_wb pipeline_mem_wb(clk,rst,
                                    mem_stage_alu_out_mm,
                                    extend_wb_mm,
                                    wen_reg_file_mm_gated,
                                    rd_reg_out_mm,
                                    inst_complete_id_mm_gated,
                                    mem_stage_load_out_mm,
                                    mem_stage_alu_load_sel_mm,
                                    
                            
                                    data_wb_ww,
                                    extender_ww,
                                    wen_wb_ww,
                                    rd_addr_ww,
                                    inst_complete_wb_ww,
                                    data_wb_mem_ww,
                                    alu_mem_sel_wb_ww
                                    );






write_back_stage wb_stage(data_wb_ww,extender_ww,wen_wb_ww,rd_addr_ww,inst_complete_wb_ww,
                         wen_wb,data_wb,rd_addr_wb,inst_complete_wb,
                         data_wb_mem_ww,alu_mem_sel_wb_ww
                         );
                         







hazard_detection_unit  hazard_unit( src_reg_1_addr,src_reg_2_addr,    /// iinput
                              rd_reg_out_out,rd_reg_out_mm,rd_addr_wb, // in
                              opcode_id, //// in
                              start_mul_out,
                              mul_busy_mm,mul_done_mm, /// in 
                              dmem_en_mm,   /// in  from mem stage 
                              data_valid_m_axi, /// in  from the d-cache read buffer
                              dmem_en_out,dmem_wr_out, /// in  from ex stage
                              branch_pred_result,
                              branch_result,
                              wen_reg_file_out,wen_reg_file_mm,wen_wb, /// in  producer write enables
                              
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



// The pc must NOT be frozen on a flush: a flush IS the redirect, and the fetch
// stage can only load the branch target on a cycle where its pc enable is
// released. Or-ing flush_pc in here held the pc exactly when it needed to move,
// so the redirect slipped by a cycle and landed off the back of the branch.
// Only a real stall freezes the pc now.
//
// An instruction-cache miss also freezes the pc, but ONLY the pc: the fetch
// stage presents a bubble for the duration, so the back end keeps draining
// instead of stalling behind the miss. The fetch stage latches any redirect
// that arrives while it is holding the pc for this reason.
assign stall_flush_pc = stall_pc | ifetch_stall;




assign pc_if_id_pipe_debug =  pc_if;
assign wb_data_debug       =  data_wb;
assign wb_addr_debug       =  rd_addr_wb;
assign alu_out_mem_stage_debug = alu_out_ex;


                         
                         
//////////    temp assignment                                                 
//assign pc_en = 1'b0;
//assign en_if_id = 1'b0;
//assign en_id_ex = 1'b0;





// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     alu_zero, mie_out_id,
                     // branch_result_out_mm: the branch outcome pipelined into MEM.
                     // The hazard unit resolves flushes off the EX-stage result now,
                     // so this MEM copy has no consumer left.
                     // flush_pc: the pc must not be frozen on a redirect (see
                     // stall_flush_pc above), so the hazard unit's flush_pc output is
                     // no longer wired into the pc enable.
                     branch_result_out_mm, flush_pc,
                     1'b0};

endmodule
