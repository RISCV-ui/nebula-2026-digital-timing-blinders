`timescale 1ns / 1ps



module execution_stage(clk,rst,pc_plus4_id,pc_id,opcode_id,src_reg_1_id,src_reg_2_id,//// input 
                        rs2_reg_id,data_cliper,           //// input 
                        alu_operation_id,start_mul_id,mulh_mul_id,alu_out_sel_id,pc4_sel_id, // ex stage control 
                        alu_out_ex,branch_result_ex,///output of ex stage
                        opcode_ex,pc_ex,
                        mul_done_ex,mul_busy_ex,
                        rs2_for_mem_ex , 
                        alu_output_forwd /// 
                         );  //// include zero flag here 
                            //// include alu out port for forwarding 
                         
input wire clk,rst;
input wire [31:0]pc_plus4_id;
input wire [31:0]pc_id;
input wire [6:0] opcode_id;
input wire [31:0]src_reg_1_id;
input wire [31:0]src_reg_2_id;
input wire [31:0] rs2_reg_id;
input wire [1:0]data_cliper;
input wire [3:0] alu_operation_id;
input wire start_mul_id, mulh_mul_id;
input wire alu_out_sel_id;
input wire pc4_sel_id;

output wire [31:0] alu_out_ex;  //// for mem stage 
output wire branch_result_ex;
output wire [6:0]opcode_ex;
output wire [31:0]pc_ex;
output wire mul_done_ex,mul_busy_ex;
output wire [31:0]rs2_for_mem_ex;  /// for mem stage 
output wire [31:0]alu_output_forwd;

///// all wire and reg decleretion 

wire [31:0]alu_out_wire;
wire [31:0]mul_out_wire;
wire [31:0]alu_pcp4_wire;



/////

assign opcode_ex = opcode_id;
assign  pc_ex    = pc_id;

///  all modules instantiation 

/// alu 
                  
alu alu_ex(src_reg_1_id,// input 1
           src_reg_2_id,// input  2
           alu_operation_id,/// alu operation select 
           alu_out_wire,
           branch_result_ex
           );                 
                  
/// multiplier 

multiplier_pipelined mul_unit_ex(clk,
                                 rst,
                                 start_mul_id,
                                 src_reg_1_id,
                                 src_reg_2_id,
                                 mulh_mul_id,         
                                 mul_busy_ex,
                                 mul_done_ex,
                                 mul_out_wire

                                 );
                  
//// data clipper 32 to 32 , 16 , 8 bits 

data_clipper data_clip_ex(rs2_reg_id,
                          data_cliper,
                          rs2_for_mem_ex 
                          );





                  
assign alu_pcp4_wire = (alu_out_sel_id)?mul_out_wire:alu_out_wire;
assign alu_out_ex    = (pc4_sel_id)?pc_plus4_id:alu_pcp4_wire;

assign  alu_output_forwd = alu_pcp4_wire ;
                  
                  

                         
endmodule
