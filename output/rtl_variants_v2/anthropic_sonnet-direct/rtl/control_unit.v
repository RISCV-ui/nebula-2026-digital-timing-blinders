
`timescale 1ns / 1ps

module control_unit(clk,rst,///in 
                    opcode,fun7,fun3,  // input
                    rd_reg , /////   dest reg adddress
                    rs2_reg, /// src reg 2 adddresss 
                    csr_wen,  /// csr write enable 
                    csr_operation, //// csr operation 
                    src_mux_sel_1,src_mux_sel_2,start_mul,mulh_mul,  /// ex stage controlsignal
                    alu_out_sel, //// ex stage control signal 
                    alu_operation,//// ex stagge alu operation 
                    pc4_sel,     /// ex sstage 
                    extender_mem, /// 32 to 16 or 8 
                    dmem_en,dmem_wr,   /// mem stage control signal
                    alu_dmem_sel, ////   mem stge control to select alu out or mem out
                    wen_reg_file,  /// write back control 
                    rd_reg_out,   //// destination reg address  
                    extend_wb ,  ///  to select 1 byte, 2byte , word data 000 is for word 
                    inst_complete_wb // make 1 when instruction completed 
                     );
input  clk,rst;
input [6:0]opcode,fun7;
input [2:0]fun3;
input [4:0]rd_reg;
input [4:0]rs2_reg;

output reg csr_wen;
output reg [1:0]csr_operation;
output reg [1:0] src_mux_sel_1,src_mux_sel_2;
output reg start_mul,mulh_mul;
output reg alu_out_sel;
output reg [3:0]alu_operation;
output reg pc4_sel;
output reg [1:0]extender_mem;
output reg dmem_en,dmem_wr;
output reg alu_dmem_sel;
output reg wen_reg_file; 
output reg [4:0]rd_reg_out;
output reg [2:0]extend_wb; 
output reg inst_complete_wb;              
                     
/////// 
always@(*)

begin


           csr_wen=1'b0; 
           csr_operation=2'b00; 
           src_mux_sel_1 =2'd2;    
           src_mux_sel_2=2'd3;
           alu_operation=4'b0000;     
           start_mul=1'b0;         
           mulh_mul=1'b0;          
           alu_out_sel=1'b0;
           pc4_sel=1'b0;
           extender_mem=2'b00;                
           dmem_en=1'b0;           
           dmem_wr=1'b0;           
           alu_dmem_sel=1'b0;      
           wen_reg_file=1'b0;      
           rd_reg_out=5'd0;  
           extend_wb=3'd0;
           inst_complete_wb=1'b0;
 
     case(opcode)   //////   level 1 start 
          7'b0110011: begin     /////       all r type 
                                  ////      opcode  0110011 add,sub,and,or,xor,sll ,SRL ,sra,slt, sltu,mul , mulh 
                                  
                       case(fun7)     ///// level 2                 
                       7'b0000000,7'b0100000:     
                               begin
                               src_mux_sel_1 =2'd0;
                               src_mux_sel_2=2'd0;
                               start_mul=1'b0;
                               mulh_mul=1'b0;
                               alu_operation={fun7[5],fun3};           
                               alu_out_sel=1'b0;
                               pc4_sel=1'b0;
                               extender_mem=2'b00;  
                               dmem_en=1'b0;
                               dmem_wr=1'b0;               
                               alu_dmem_sel=1'b0;                                                               
                               wen_reg_file=1'b1;
                               rd_reg_out=rd_reg;
                               extend_wb=3'd0; 
                               inst_complete_wb=1'b1;
                               end
                       7'b0000001:  
                              begin
                                   case(fun3)   //// level 3     ///   mul   
                                            3'b000: 
                                                    begin
                                                    src_mux_sel_1 =2'b0;
                                                    src_mux_sel_2=2'b0; 
                                                    start_mul=1'b1;     
                                                    mulh_mul=1'b0; 
                                                    alu_operation={fun7[5],fun3};        
                                                    alu_out_sel=1'b1; 
                                                    pc4_sel=1'b0;
                                                    extender_mem=2'b00;  
                                                    dmem_en=1'b0;       
                                                    dmem_wr=1'b0;       
                                                    alu_dmem_sel=1'b0;  
                                                    wen_reg_file=1'b1;
                                                    rd_reg_out=rd_reg;
                                                    inst_complete_wb=1'b1;
                                                    end  
                                            
                                            3'b001:               /// mulh                 
                                                    begin                       
                                                    src_mux_sel_1 =2'b0;       
                                                    src_mux_sel_2=2'b0;        
                                                    start_mul=1'b1;            
                                                    mulh_mul=1'b1; 
                                                    alu_operation={fun7[5],fun3};               
                                                    alu_out_sel=1'b1;
                                                    pc4_sel=1'b0; 
                                                    extender_mem=2'b00;         
                                                    dmem_en=1'b0;              
                                                    dmem_wr=1'b0;              
                                                    alu_dmem_sel=1'b0;         
                                                    wen_reg_file=1'b1;
                                                    rd_reg_out=rd_reg;
                                                    inst_complete_wb=1'b1;         
                                                    end                         
                                            
                                            default:
                                                    begin
                                                    src_mux_sel_1 =2'd2;   
                                                    src_mux_sel_2=2'd3;    
                                                    start_mul=1'b0;        
                                                    mulh_mul=1'b0; 
                                                    alu_operation=4'b0000;           
                                                    alu_out_sel=1'b0;
                                                    pc4_sel=1'b0; 
                                                    extender_mem=2'b00;     
                                                    dmem_en=1'b0;          
                                                    dmem_wr=1'b0;          
                                                    alu_dmem_sel=1'b0;     
                                                    wen_reg_file=1'b0;
                                                    rd_reg_out=5'd0; 
                                                    extend_wb=3'd0;
                                                    inst_complete_wb=1'b0;    
                                                    end    
                                                                                      
                                   endcase    ///// level 3 end   
                              end        
                               
                               
                         default:
                               begin                                
                               src_mux_sel_1 =2'd2;
                               src_mux_sel_2=2'd3;
                               start_mul=1'b0;
                               mulh_mul=1'b0;  
                               alu_operation=4'b0000;             
                               alu_out_sel=1'b0;
                               pc4_sel=1'b0; 
                               extender_mem=2'b00;
                               dmem_en=1'b0;
                               dmem_wr=1'b0;               
                               alu_dmem_sel=1'b0;                                                               
                               wen_reg_file=1'b0;
                               rd_reg_out=5'b0;
                               extend_wb=3'd0;   
                               inst_complete_wb=1'b0; 
                               end 
                                 
                                 
                                                           
                       endcase    ///// level 2 end   
                       end
                       
            7'b0010011:      // ////   i type  -- alu related 
                       begin
                            src_mux_sel_1 =2'd0;   
                            src_mux_sel_2=2'd1;    
                            start_mul=1'b0;        
                            mulh_mul=1'b0; 
                            // OP-IMM: instruction[30] (fun7[5]) is part of the
                            // immediate for every op except the shifts, where it
                            // is the SRLI/SRAI selector. Feeding it into the ALU
                            // op unconditionally turned ADDI with a negative
                            // immediate into a SUB: addi x31,x31,-16 computed
                            // 0-(-16)=+16. Only the shift forms may use it.
                            alu_operation=(fun3==3'b101 || fun3==3'b001)?
                                            {fun7[5],fun3} : {1'b0,fun3};
                            alu_out_sel=1'b0; 
                            pc4_sel=1'b0;  
                            extender_mem=2'b00;   
                            dmem_en=1'b0;          
                            dmem_wr=1'b0;          
                            alu_dmem_sel=1'b0;     
                            wen_reg_file=1'b1;     
                            rd_reg_out=rd_reg;
                            extend_wb=3'd0;   
                            inst_complete_wb=1'b1;                    
                       
                        end
                       
                       
           7'b0000011: ///    i type   --- load instruction 
                       begin
                            case(fun3)
                            3'b010:  /// LW  rd <-  M[rs1 + immm ]
                                   begin
                                   src_mux_sel_1 =2'd0; 
                                   src_mux_sel_2=2'd1;  
                                   start_mul=1'b0;      
                                   mulh_mul=1'b0; 
                                   alu_operation={4'd0};         
                                   alu_out_sel=1'b0; 
                                   pc4_sel=1'b0;
                                   extender_mem=2'b00;   
                                   dmem_en=1'b1;        
                                   dmem_wr=1'b0;        
                                   alu_dmem_sel=1'b1;   
                                   wen_reg_file=1'b1;   
                                   rd_reg_out=rd_reg;  
                                   extend_wb=3'd0;
                                   inst_complete_wb=1'b1;    
                                   end
                                   
                            3'b001: /// LH   rd <-    M[rs1 + immm ] [15:0] sign extendet to 32 bit 
                                   begin
                                   src_mux_sel_1 =2'd0;       
                                   src_mux_sel_2=2'd1;        
                                   start_mul=1'b0;            
                                   mulh_mul=1'b0; 
                                   alu_operation={4'd0};               
                                   alu_out_sel=1'b0;
                                   pc4_sel=1'b0;
                                   extender_mem=2'b00;          
                                   dmem_en=1'b1;              
                                   dmem_wr=1'b0;              
                                   alu_dmem_sel=1'b1;         
                                   wen_reg_file=1'b1;         
                                   rd_reg_out=rd_reg;
                                   extend_wb=3'd1;    
                                   inst_complete_wb=1'b1;                                        
                                   end     
                                   
                            3'b000: ////  LB rd <- M[rs1 + immm ] [7:0] sign extendet to 32 bit 
                                   begin
                                   src_mux_sel_1 =2'd0;       
                                   src_mux_sel_2=2'd1;        
                                   start_mul=1'b0;            
                                   mulh_mul=1'b0;  
                                   alu_operation={4'd0};              
                                   alu_out_sel=1'b0;
                                   pc4_sel=1'b0; 
                                   extender_mem=2'b00;         
                                   dmem_en=1'b1;              
                                   dmem_wr=1'b0;              
                                   alu_dmem_sel=1'b1;         
                                   wen_reg_file=1'b1;         
                                   rd_reg_out=rd_reg;
                                   extend_wb=3'd2;       
                                   inst_complete_wb=1'b1;                                                        
                                   end        
                          
                          3'b101: ////  LHU rd <- M[rs1 + immm ] [15:0] zero extended extendet to 32 bit 
                                   begin
                                   src_mux_sel_1 =2'd0;       
                                   src_mux_sel_2=2'd1;        
                                   start_mul=1'b0;            
                                   mulh_mul=1'b0; 
                                   alu_operation={4'd0};               
                                   alu_out_sel=1'b0; 
                                   pc4_sel=1'b0;
                                   extender_mem=2'b00;        
                                   dmem_en=1'b1;              
                                   dmem_wr=1'b0;              
                                   alu_dmem_sel=1'b1;         
                                   wen_reg_file=1'b1;         
                                   rd_reg_out=rd_reg;
                                   extend_wb=3'd3;      
                                   inst_complete_wb=1'b1;                                                         
                                   end           
                                    
                         3'b100: ////  LBU rd <- M[rs1 + immm ] [7:0] zer0 extendet to 32 bit 
                                   begin
                                   src_mux_sel_1 =2'd0;       
                                   src_mux_sel_2=2'd1;        
                                   start_mul=1'b0;            
                                   mulh_mul=1'b0;
                                   alu_operation={4'd0};                
                                   alu_out_sel=1'b0;
                                   pc4_sel=1'b0; 
                                   extender_mem=2'b00;           
                                   dmem_en=1'b1;              
                                   dmem_wr=1'b0;              
                                   alu_dmem_sel=1'b1;         
                                   wen_reg_file=1'b1;         
                                   rd_reg_out=rd_reg;
                                   extend_wb=3'd4;       
                                   inst_complete_wb=1'b1;                                                        
                                   end           
                                    
                                    
                      default:  begin
                                   src_mux_sel_1 =2'd2;       
                                   src_mux_sel_2=2'd3;        
                                   start_mul=1'b0;            
                                   mulh_mul=1'b0;
                                   alu_operation=4'b0000;                
                                   alu_out_sel=1'b0;
                                   pc4_sel=1'b0;
                                   extender_mem=2'b00;            
                                   dmem_en=1'b1;              
                                   dmem_wr=1'b0;              
                                   alu_dmem_sel=1'b1;         
                                   wen_reg_file=1'b1;         
                                   rd_reg_out=rd_reg;
                                   extend_wb=3'd4;
                                   inst_complete_wb=1'b0;
                                end            
                           endcase
                       end            
                       
                       
                       
         7'b1100111: ////  jlr PC <- r1 + immm, rd <- pc + 4  
                    begin
                    src_mux_sel_1 =2'd0;       
                    src_mux_sel_2=2'd1;        
                    start_mul=1'b0;            
                    mulh_mul=1'b0;
                    // Forced to ADD. This used to be {fun7[5],fun3}, but a
                    // JALR has no funct7 -- those bits are imm[11:5], so
                    // instr[30] set (any target with imm[10] high) selected
                    // SUB and the jump went to rs1-imm.
                    alu_operation=4'b0000;                
                    alu_out_sel=1'b0;
                    pc4_sel=1'b1;
                    extender_mem=2'b00;            
                    // JALR is not a memory instruction. dmem_en/alu_dmem_sel
                    // were both 1, which (a) issued a spurious data read and
                    // stalled on it, and (b) made write-back take the memory
                    // result instead of pc+4 -- so rd got whatever that read
                    // returned, not the return address. Note the address used
                    // would have been pc+4 anyway, since pc4_sel steers
                    // alu_out_ex, so it was not even the JALR target.
                    dmem_en=1'b0;              
                    dmem_wr=1'b0;              
                    alu_dmem_sel=1'b0;         
                    wen_reg_file=1'b1;         
                    rd_reg_out=rd_reg;
                    extend_wb=3'd0;
                    inst_complete_wb=1'b1;           
                    end 
                    
          7'b0100011 : 
                     begin
                    
                     case(fun3) /// all stype  ---   SW, SH, SB 
                     3'b010:  /// SW  rs2 - > M [rs1 + imm ]
                            begin
                            src_mux_sel_1 =2'd0;       
                            src_mux_sel_2=2'd1;        
                            start_mul=1'b0;            
                            mulh_mul=1'b0;
                            alu_operation=4'b0000;                
                            alu_out_sel=1'b0;
                            pc4_sel=1'b0;
                            extender_mem=2'b00;            
                            dmem_en=1'b1;              
                            dmem_wr=1'b1;              
                            alu_dmem_sel=1'b0;         
                            wen_reg_file=1'b0;         
                            rd_reg_out=rs2_reg;
                            extend_wb=3'd0;
                            inst_complete_wb=1'b1;
                            end  
                                   
                     3'b001 :  ///  SH    rs2[15:0]  -->  M[ rs1+imm]
                             begin
                             src_mux_sel_1 =2'd0;       
                             src_mux_sel_2=2'd1;        
                             start_mul=1'b0;            
                             mulh_mul=1'b0;
                             alu_operation=4'b0000;                
                             alu_out_sel=1'b0;
                             pc4_sel=1'b0;
                             extender_mem=2'b01;            
                             dmem_en=1'b1;              
                             dmem_wr=1'b1;              
                             alu_dmem_sel=1'b0;         
                             // A store writes memory, not a register. This was 1, and rd_reg_out
                             // carries rs2 for a store, so every SH wrote the
                             // load-return path back into its own source register.
                             wen_reg_file=1'b0;         
                             rd_reg_out=rs2_reg;
                             extend_wb=3'd0;
                             inst_complete_wb=1'b1;
                             end    
                    
                    3'b000 :  ///  SB    rs2[7:0]  -->  M[ rs1+imm]
                             begin
                             src_mux_sel_1 =2'd0;       
                             src_mux_sel_2=2'd1;        
                             start_mul=1'b0;            
                             mulh_mul=1'b0;
                             alu_operation=4'b0000;                
                             alu_out_sel=1'b0;
                             pc4_sel=1'b0;
                             extender_mem=2'b10;            
                             dmem_en=1'b1;              
                             dmem_wr=1'b1;              
                             alu_dmem_sel=1'b0;         
                             // A store writes memory, not a register. This was 1, and rd_reg_out
                             // carries rs2 for a store, so every SB wrote the
                             // load-return path back into its own source register.
                             wen_reg_file=1'b0;         
                             rd_reg_out=rs2_reg;
                             extend_wb=3'd0;
                             inst_complete_wb=1'b1;
                             end
                             
                    default: begin
                             src_mux_sel_1 =2'd2;       
                             src_mux_sel_2=2'd3;        
                             start_mul=1'b0;            
                             mulh_mul=1'b0;
                             alu_operation=4'b0000;                
                             alu_out_sel=1'b0;
                             pc4_sel=1'b0;
                             extender_mem=2'b00;            
                             dmem_en=1'b0;              
                             dmem_wr=1'b0;              
                             alu_dmem_sel=1'b0;         
                             wen_reg_file=1'b0;         
                             rd_reg_out=5'b00000;
                             extend_wb=3'd0;
                             inst_complete_wb=1'b0;
                    
                    
                    
                             end         
                  endcase  
                  end              
              7'b1100011: //// all branch instruction 
                         case(fun3) 
                                  
                        3'b000,
                        3'b001,
                        3'b100,
                        3'b101,
                        3'b110,
                        3'b111: //// BEQ,BNE,BLT,BGE,BLTU,BGEU  , 
                        /// if(rs1== rs2), pc=pc+imm ,if(rs1!= rs2),<,>=,<(unsign),>=(unsigned)
                                   begin
                                    src_mux_sel_1 =2'd1;       
                                    src_mux_sel_2=2'd1;        
                                    start_mul=1'b0;            
                                    mulh_mul=1'b0;
                                    alu_operation=4'b0000;                
                                    alu_out_sel=1'b0;
                                    pc4_sel=1'b0;
                                    extender_mem=2'b00;            
                                    dmem_en=1'b0;              
                                    dmem_wr=1'b0;              
                                    alu_dmem_sel=1'b0;         
                                    wen_reg_file=1'b0;         
                                    rd_reg_out=5'b00000;
                                    extend_wb=3'd0;
                                    inst_complete_wb=1'b1;
                                   end    
                           default: //// 
                                   begin
                                   src_mux_sel_1 =2'd2;       
                                    src_mux_sel_2=2'd3;        
                                    start_mul=1'b0;            
                                    mulh_mul=1'b0;
                                    alu_operation=4'b0000;                
                                    alu_out_sel=1'b0;
                                    pc4_sel=1'b0;
                                    extender_mem=2'b00;            
                                    dmem_en=1'b0;              
                                    dmem_wr=1'b0;              
                                    alu_dmem_sel=1'b0;         
                                    wen_reg_file=1'b0;         
                                    rd_reg_out=5'b00000;
                                    extend_wb=3'd0;
                                    inst_complete_wb=1'b0;
                                   end      
  
                          endcase            
                       
                       
              7'b0110111:  //// LUI        rd <-  imm<< 12         
                      begin
                               src_mux_sel_1 =2'd2;       ///  src mux sel 2 --- > 0 src mux sel 1 ---> (imm>12) 
                               src_mux_sel_2=2'd1;        
                               start_mul=1'b0;            
                               mulh_mul=1'b0;
                               // immediate_generator already returns the U-type
                               // immediate pre-shifted ({instr[31:12],12'b0}),
                               // so LUI is 0 + imm, not 0 << imm. The shift-left
                               // op here made src_a (hardwired 0 for sel 2) the
                               // shifted operand, so LUI always wrote 0.
                               alu_operation=4'b0000;    ///---- add: 0 + (imm<<12)
                               alu_out_sel=1'b0;
                               pc4_sel=1'b0;
                               extender_mem=2'b00;            
                               dmem_en=1'b0;              
                               dmem_wr=1'b0;              
                               alu_dmem_sel=1'b0;         
                               wen_reg_file=1'b1;         
                               rd_reg_out=rd_reg;
                               extend_wb=3'd0;
                               // LUI retires like any other ALU op; it was the
                               // only one not counted by the minstret CSR.
                               inst_complete_wb=1'b1;
                              end
                  
                       
                       
               7'b0010111:  ////    AUIPC  rd <- pc + imm<< 12         
                      begin
                               src_mux_sel_1 =2'd1;       ///  
                               src_mux_sel_2=2'd1;        
                               start_mul=1'b0;            
                               mulh_mul=1'b0;
                               alu_operation=4'b0000;    ///--- alu operation               
                               alu_out_sel=1'b0;
                               pc4_sel=1'b0;
                               extender_mem=2'b00;            
                               dmem_en=1'b0;              
                               dmem_wr=1'b0;              
                               alu_dmem_sel=1'b0;         
                               wen_reg_file=1'b1;         
                               rd_reg_out=rd_reg;
                               extend_wb=3'd0;
                               inst_complete_wb=1'b1;
                              end         
                       
                 
                 
              7'b1101111:  ////  JAL   rd <- pc + 4   pc<--- imm  +  pc          
                      begin
                               src_mux_sel_1 =2'd1;       ///  
                               src_mux_sel_2=2'd1;        
                               start_mul=1'b0;            
                               mulh_mul=1'b0;
                               alu_operation=4'b0000;    ///--- alu operation  add              
                               alu_out_sel=1'b0;
                               pc4_sel=1'b1;
                               extender_mem=2'b00;            
                               dmem_en=1'b0;              
                               dmem_wr=1'b0;              
                               alu_dmem_sel=1'b0;         
                               wen_reg_file=1'b1;         
                               rd_reg_out=rd_reg;
                               extend_wb=3'd0;
                               inst_complete_wb=1'b1;
                              end   
                 
                 
                 7'b1110011:
                            begin
                                 case(fun3)
                                          3'b001:   /// csr rw
                                                 begin
                                                 csr_wen=1'b1;
                                                 csr_operation=2'b00; 
                                                 src_mux_sel_1 =2'd3;       ///  
                                                 src_mux_sel_2=2'd3;        
                                                 start_mul=1'b0;            
                                                 mulh_mul=1'b0;
                                                 alu_operation=4'b0000;    ///--- alu operation  add              
                                                 alu_out_sel=1'b0;
                                                 pc4_sel=1'b0;
                                                 extender_mem=2'b00;            
                                                 dmem_en=1'b0;              
                                                 dmem_wr=1'b0;              
                                                 alu_dmem_sel=1'b0;         
                                                 wen_reg_file=1'b1;         
                                                 rd_reg_out=rd_reg;
                                                 extend_wb=3'd0; 
                                                 inst_complete_wb=1'b1;
                                                 end
                            
                                         3'b010:   /// csr rs
                                                 begin
                                                 csr_wen=1'b1;
                                                 csr_operation=2'b01; 
                                                 src_mux_sel_1 =2'd3;       ///  
                                                 src_mux_sel_2=2'd3;        
                                                 start_mul=1'b0;            
                                                 mulh_mul=1'b0;
                                                 alu_operation=4'b0000;    ///--- alu operation  add              
                                                 alu_out_sel=1'b0;
                                                 pc4_sel=1'b0;
                                                 extender_mem=2'b00;            
                                                 dmem_en=1'b0;              
                                                 dmem_wr=1'b0;              
                                                 alu_dmem_sel=1'b0;         
                                                 wen_reg_file=1'b1;         
                                                 rd_reg_out=rd_reg;
                                                 extend_wb=3'd0; 
                                                 inst_complete_wb=1'b1;
                                                 end
                                   
                                        3'b011:
                                               begin
                                                 csr_wen=1'b1;
                                                 csr_operation=2'b10; 
                                                 src_mux_sel_1 =2'd3;       ///  
                                                 src_mux_sel_2=2'd3;        
                                                 start_mul=1'b0;            
                                                 mulh_mul=1'b0;
                                                 alu_operation=4'b0000;    ///--- alu operation  add              
                                                 alu_out_sel=1'b0;
                                                 pc4_sel=1'b0;
                                                 extender_mem=2'b00;            
                                                 dmem_en=1'b0;              
                                                 dmem_wr=1'b0;              
                                                 alu_dmem_sel=1'b0;         
                                                 wen_reg_file=1'b1;         
                                                 rd_reg_out=rd_reg;
                                                 extend_wb=3'd0; 
                                                 inst_complete_wb=1'b1;
                                                 end
                                        
                                        
                                      default:
                                              begin
                                                  csr_wen=1'b0;
                                                 csr_operation=2'b00; 
                                                 src_mux_sel_1 =2'd2;       ///  
                                                 src_mux_sel_2=2'd3;        
                                                 start_mul=1'b0;            
                                                 mulh_mul=1'b0;
                                                 alu_operation=4'b0000;    ///--- alu operation  add              
                                                 alu_out_sel=1'b0;
                                                 pc4_sel=1'b0;
                                                 extender_mem=2'b00;            
                                                 dmem_en=1'b0;              
                                                 dmem_wr=1'b0;              
                                                 alu_dmem_sel=1'b0;         
                                                 wen_reg_file=1'b0;         
                                                 rd_reg_out=5'd0;
                                                 extend_wb=3'd0;
                                                 inst_complete_wb=1'b0;
                                              
                                              end
                                   
                                   
                                   
                               endcase
                        
                        end
                                        
            
            
            
                
                   
                   
          default: begin   
                           csr_wen=1'b0;
                           csr_operation=2'b00;
                           src_mux_sel_1 =2'd2;       ///  
                           src_mux_sel_2=2'd3;        
                           start_mul=1'b0;            
                           mulh_mul=1'b0;
                           alu_operation=4'b0000;    ///             
                           alu_out_sel=1'b0;
                           pc4_sel=1'b0;
                           extender_mem=2'b00;            
                           dmem_en=1'b0;              
                           dmem_wr=1'b0;              
                           alu_dmem_sel=1'b0;         
                           wen_reg_file=1'b0;         
                           rd_reg_out=5'b00000;
                           extend_wb=3'd0;
                           inst_complete_wb=1'b0;
                          end          
                   
                   
                   
                   
                   
                                    
 endcase  //// level 1 

end

                 
                 
                 
                 
                 
                 

// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     clk, rst,
                     1'b0};

endmodule
