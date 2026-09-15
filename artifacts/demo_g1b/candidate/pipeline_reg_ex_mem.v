`timescale 1ns / 1ps

module pipeline_reg_ex_mem(clk,rst,en_ex_mem,
                           alu_out_in,
                           rs2_for_mem_in,
                           dmem_en_in,dmem_wr_in,alu_dmem_sel_in,
                           wen_reg_file_in,
                           rd_reg_out_in,
                           extend_wb_in,
                           inst_complete_id_in,
                           mul_done_in,
                           mul_busy_in,
                           branch_result_in,
                           
                           alu_out_out,
                           rs2_for_mem_out,
                           dmem_en_out,dmem_wr_out,alu_dmem_sel_out,
                           wen_reg_file_out,
                           rd_reg_out_out,
                           extend_wb_out,
                           inst_complete_id_out,
                           mul_done_out,
                           mul_busy_out,
                           branch_result_out
                            );


input wire clk,rst;

// Hold enable, same polarity as the other pipeline registers in this design:
// 1 = hold current value (stall), 0 = load the input. Needed so a data-memory
// access that has not yet returned keeps its request asserted on the bus
// instead of being shifted out from under the memory stage.
input wire en_ex_mem;

input wire [31:0]alu_out_in;
input wire[31:0]rs2_for_mem_in;
input wire dmem_en_in,dmem_wr_in,alu_dmem_sel_in;        
input wire wen_reg_file_in;                        
input wire [4:0] rd_reg_out_in;                    
input wire [2:0]extend_wb_in;                      
input wire inst_complete_id_in;
//input wire [6:0]opcode_in;
input wire mul_done_in,mul_busy_in;
input wire branch_result_in;


output reg [31:0]alu_out_out;
output reg [31:0]rs2_for_mem_out;
output reg dmem_en_out,dmem_wr_out,alu_dmem_sel_out;   
output reg wen_reg_file_out;                         
output reg [4:0] rd_reg_out_out;                     
output reg [2:0]extend_wb_out;                       
output reg inst_complete_id_out; 
//output reg [6:0] opcode_out;
output reg mul_done_out,mul_busy_out;
output reg branch_result_out;





 always @(posedge clk) 
 begin
      if (rst)
         begin
         alu_out_out         <=32'd0;
         rs2_for_mem_out     <=32'd0;
         dmem_en_out         <=1'd0;
        dmem_wr_out          <=1'd0;  
        alu_dmem_sel_out     <=1'd0;
        wen_reg_file_out     <=1'd0;                  
        rd_reg_out_out       <=5'd0;                  
        extend_wb_out        <=3'd0;                  
        inst_complete_id_out <=1'd0;  
        mul_done_out         <=1'd0; 
        mul_busy_out         <=1'd0; 
        branch_result_out    <=1'b0;
        end
          
          
      else if (!en_ex_mem)
        begin




                alu_out_out          <=    alu_out_in;
                rs2_for_mem_out      <=    rs2_for_mem_in;
                dmem_en_out          <=    dmem_en_in;       
                dmem_wr_out          <=    dmem_wr_in;       
                alu_dmem_sel_out     <=    alu_dmem_sel_in;  
                wen_reg_file_out     <=    wen_reg_file_in;  
                rd_reg_out_out       <=    rd_reg_out_in;    
                extend_wb_out        <=    extend_wb_in;     
                inst_complete_id_out <=  inst_complete_id_in; 
                mul_done_out         <=  mul_done_in; 
                mul_busy_out         <=   mul_busy_in;
                branch_result_out    <=  branch_result_in;




        end
end
















// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
endmodule
