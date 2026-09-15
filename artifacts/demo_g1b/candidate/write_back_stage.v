`timescale 1ns / 1ps

module write_back_stage(data_mem,extender_mem,wen_regfile_mem,rd_addr_mem,inst_complete_mem,
                         wen_wb,data_wb,rd_addr_wb,inst_complete_wb,
                         mem_data_in,alu_mem_sel_in
                         );
                         
                         
input [31:0]data_mem; // input data from mem alu stage 
input [2:0] extender_mem; /// control for extender 
input wen_regfile_mem;
input [4:0]rd_addr_mem;
input inst_complete_mem;
input [31:0]mem_data_in;   ///// input from mem stage memory data // load   
input alu_mem_sel_in;

output wire[31:0]data_wb;
output wire wen_wb;
output wire [4:0]rd_addr_wb;
output wire inst_complete_wb;


wire [31:0]data_in;

assign data_in =(alu_mem_sel_in)? mem_data_in:data_mem; 



assign  wen_wb = wen_regfile_mem;
assign rd_addr_wb  = rd_addr_mem;
assign inst_complete_wb = inst_complete_mem;


                         
                         
data_extender  data_ext_wb(data_in,extender_mem,data_wb) ;
                      
                         
endmodule
