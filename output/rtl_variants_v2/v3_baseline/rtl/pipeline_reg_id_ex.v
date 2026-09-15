`timescale 1ns / 1ps


module pipeline_reg_id_ex( clk,rst,flush_id_ex,en_id_ex, 
                           pc_plus4_in ,pc_in,opcode_in, 
                           src_reg_1_in,src_reg_2_in,imm_in,
                           csr_write_data_in,
                           src_mux_sel_1_in,
                           src_mux_sel_2_in,
                           branch_operation_wire_in,
                           alu_operation_in,        
                           start_mul_in,mulh_mul_in,
                           alu_out_sel_in,pc4_sel_in,
                           extender_mem_in,
                           dmem_en_in,dmem_wr_in,alu_dmem_sel_in,
                           wen_reg_file_in,
                           rd_reg_out_in,
                           extend_wb_in,
                           inst_complete_id_in,
                         
                            
                            
                         pc_plus4_out,   
                         pc_out,          
                         opcode_out,      
                         src_reg_1_out,   
                         src_reg_2_out,   
                         imm_out, 
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
    
input wire clk,rst,flush_id_ex,en_id_ex;    
input wire[31:0] pc_plus4_in;                       
input wire[31:0] pc_in;                             
input wire[6:0]  opcode_in;                         
input wire[31:0] src_reg_1_in;                         
input wire[31:0] src_reg_2_in;                         
input wire[31:0] imm_in;                           
input wire[3:0]  alu_operation_in;                 
input wire start_mul_in,mulh_mul_in;                  
input wire alu_out_sel_in,pc4_sel_in;                 
input wire [1:0] extender_mem_in;                  
input wire dmem_en_in,dmem_wr_in,alu_dmem_sel_in;        
input wire wen_reg_file_in;                        
input wire [4:0] rd_reg_out_in;                    
input wire [2:0]extend_wb_in;                      
input wire inst_complete_id_in;                        
input wire [31:0]csr_write_data_in;
input wire [1:0]src_mux_sel_1_in;
input wire [1:0]src_mux_sel_2_in;
input wire [2:0]branch_operation_wire_in;




       
    
output reg [31:0] pc_plus4_out;                              
output reg [31:0] pc_out;                                    
output reg  [6:0]  opcode_out;                             
output reg [31:0] src_reg_1_out;                          
output reg [31:0] src_reg_2_out;                          
output reg [31:0] imm_out;                            
output reg [3:0]  alu_operation_out;                  
output reg start_mul_out,mulh_mul_out;                
output reg alu_out_sel_out,pc4_sel_out;               
output reg [1:0] extender_mem_out;                   
output reg dmem_en_out,dmem_wr_out,alu_dmem_sel_out;   
output reg wen_reg_file_out;                         
output reg [4:0] rd_reg_out_out;                     
output reg [2:0]extend_wb_out;                       
output reg inst_complete_id_out;                     
output reg [31:0]csr_write_data_out;
output reg [1:0]src_mux_sel_1_out;
output reg [1:0]src_mux_sel_2_out;
output reg [2:0]branch_operation_wire_out;

    
    
  
  
always @(posedge clk)
begin

//pc_plus4_out      <= 32'd0;          
//pc_out            <= 32'd0;              
//opcode_out       <= 7'd0;           
//src_reg_1_out     <= 32'd0;          
//src_reg_2_out     <= 32'd0;         
//imm_out       <= 32'd0;         
//alu_operation_out <= 4'd0;       

//start_mul_out      <=1'd0;
//mulh_mul_out       <=1'd0;               
//alu_out_sel_out    <=1'd0;
//pc4_sel_out        <=1'd0;          
//extender_mem_out   <=2'd0;                   
//dmem_en_out        <=1'd0;
//dmem_wr_out        <=1'd0;  
//alu_dmem_sel_out   <=1'd0;
//wen_reg_file_out   <=1'd0;                  
//rd_reg_out_out     <=5'd0;                  
//extend_wb_out      <=3'd0;                  
//inst_complete_id_out <=1'd0;   
//csr_write_data_out   <= 32'd0;     
//src_mux_sel_1_out    <= 2'd0 ;    
//src_mux_sel_2_out    <= 2'd0;     
//branch_operation_wire_out <= 3'd2;

        if (rst)
         begin
         pc_plus4_out      <= 32'd0;          
         pc_out            <= 32'd0;              
          opcode_out       <= 7'd0;           
         src_reg_1_out     <= 32'd0;          
         src_reg_2_out     <= 32'd0;         
         imm_out       <= 32'd0;         
         alu_operation_out <= 4'd0;       
        
        start_mul_out      <=1'd0;
        mulh_mul_out       <=1'd0;               
        alu_out_sel_out    <=1'd0;
        pc4_sel_out        <=1'd0;          
        extender_mem_out   <=2'd0;                   
        dmem_en_out        <=1'd0;
        dmem_wr_out        <=1'd0;  
        alu_dmem_sel_out   <=1'd0;
        wen_reg_file_out   <=1'd0;                  
        rd_reg_out_out     <=5'd0;                  
        extend_wb_out      <=3'd0;                  
        inst_complete_id_out <=1'd0;   
        csr_write_data_out   <= 32'd0;    
        src_mux_sel_1_out    <= 2'd0 ;    
        src_mux_sel_2_out    <= 2'd0;     
        branch_operation_wire_out <= 3'd2;
                       
    
        
  
         end
        
        else if (flush_id_ex)
         begin
                 pc_plus4_out      <= 32'd0;            
                 pc_out            <= 32'd0;            
                  opcode_out       <= 7'd0;             
                 src_reg_1_out     <= 32'd0;            
                 src_reg_2_out     <= 32'd0;            
                 imm_out       <= 32'd0;            
                 alu_operation_out <= 4'd0;             
  
                start_mul_out      <=1'd0;              
                mulh_mul_out       <=1'd0;              
                alu_out_sel_out    <=1'd0;              
                pc4_sel_out        <=1'd0;              
                extender_mem_out   <=2'd0;              
                dmem_en_out        <=1'd0;              
                dmem_wr_out        <=1'd0;              
                alu_dmem_sel_out   <=1'd0;              
                wen_reg_file_out   <=1'd0;              
                rd_reg_out_out     <=5'd0;              
                extend_wb_out      <=3'd0;              
                inst_complete_id_out <=1'd0; 
                csr_write_data_out   <= 32'd0;    
                src_mux_sel_1_out    <= 2'd0 ;    
                src_mux_sel_2_out    <= 2'd0;     
                branch_operation_wire_out <= 3'd2;
                
                
                
                
                           
         
         end
         
         
        else if (!en_id_ex) 
        begin
                 pc_plus4_out      <= pc_plus4_in;     
                 pc_out            <= pc_in;           
                  opcode_out       <=  opcode_in;      
                 src_reg_1_out     <= src_reg_1_in;    
                 src_reg_2_out     <= src_reg_2_in;    
                 imm_out           <= imm_in;      
                 alu_operation_out <= alu_operation_in;
                                                        
                start_mul_out      <=    start_mul_in;    
                mulh_mul_out       <=    mulh_mul_in;      
                alu_out_sel_out    <=    alu_out_sel_in;   
                pc4_sel_out        <=    pc4_sel_in;       
                extender_mem_out   <=    extender_mem_in;  
                dmem_en_out        <=    dmem_en_in;       
                dmem_wr_out        <=    dmem_wr_in;       
                alu_dmem_sel_out   <=    alu_dmem_sel_in;  
                wen_reg_file_out   <=    wen_reg_file_in;  
                rd_reg_out_out     <=    rd_reg_out_in;    
                extend_wb_out      <=    extend_wb_in;     
                inst_complete_id_out <=  inst_complete_id_in;  
                csr_write_data_out   <= csr_write_data_in;    
                src_mux_sel_1_out    <= src_mux_sel_1_in ;    
                src_mux_sel_2_out    <= src_mux_sel_2_in;     
                branch_operation_wire_out <=branch_operation_wire_in;
                
                
                
                         
       
        end
 end
  
  
    
    
endmodule
