`timescale 1ns / 1ps



module pipeline_reg_mem_wb(clk,rst,
                            data_wb_in,
                            extender_in,
                            wen_wb_in,
                            rd_addr_wb_in,
                            inst_complete_wb_in,
                            data_wb_mem_in,
                            alu_mem_sel_in,
                            
                            data_wb_out,
                            extender_out,
                            wen_wb_out,
                            rd_addr_wb_out,
                            inst_complete_wb_out,
                            data_wb_mem_out,
                            alu_mem_sel_out
    );
    
input clk,rst;
input [31:0] data_wb_in;
input [2:0]extender_in;
input wen_wb_in;
input [4:0]rd_addr_wb_in;
input inst_complete_wb_in;
input [31:0]data_wb_mem_in;
input alu_mem_sel_in;


output reg [31:0] data_wb_out;
output reg wen_wb_out;
output reg [4:0]rd_addr_wb_out;
output reg  inst_complete_wb_out;
output reg [2:0]extender_out;
output reg [31:0] data_wb_mem_out;  
output reg  alu_mem_sel_out;   
    
    
    
    
    
// data_wb_mem_out used to be a wire assigned straight from data_wb_mem_in, so
// the load data skipped this register while its select, destination and write
// enable went through it. Write-back therefore committed the bus data from the
// cycle AFTER the load was in MEM. It only ever looked right because the old
// core-private dmem had a registered read port that happened to line the two up;
// with the load coming from the d-cache read buffer (combinational hit data) it
// wrote back the next access's word. It is a flop now, like everything else here.
    
    
    
    
always @(posedge clk)
 begin
        data_wb_out  <= 32'd0;
        wen_wb_out   <= 1'd0;
        rd_addr_wb_out <= 5'd0;
        inst_complete_wb_out <= 1'd0;
        extender_out         <= 3'd0;
        alu_mem_sel_out <= 1'b0;
        data_wb_mem_out <= 32'd0;
 
 
 
 
 
        if (rst) 
        begin    
        data_wb_out  <= 32'd0;
        wen_wb_out   <= 1'd0;
        rd_addr_wb_out <= 5'd0;
        inst_complete_wb_out <= 1'd0;
        extender_out         <= 3'd0;
        alu_mem_sel_out <= 1'b0; 
        data_wb_mem_out <= 32'd0;
        
        end
        
        else
        begin
        data_wb_out  <= data_wb_in ;
        wen_wb_out   <= wen_wb_in;
        rd_addr_wb_out <= rd_addr_wb_in;
        inst_complete_wb_out <= inst_complete_wb_in; 
        extender_out         <= extender_in;
        alu_mem_sel_out <= alu_mem_sel_in;
        data_wb_mem_out <= data_wb_mem_in;
        
        end
        
end

        
endmodule
