`timescale 1ns / 1ps


module mem_axi_slave(clk,rst,
                     mem_en,read_write,addr,data_out,data_in,hit,
                     s1_ar_addr, s1_ar_valid, s1_ar_ready,s1_ar_len,s1_ar_size,s1_ar_burst,
                     s1_aw_addr, s1_aw_valid, s1_aw_ready,s1_aw_len,s1_aw_size,s1_aw_burst,
                     s1_dr_data, s1_dr_valid, s1_dr_ready,s1_dr_last,
                     s1_dw_data, s1_dw_valid, s1_dw_ready,s1_dw_strb,s1_dw_last,
                     s1_b_ready, s1_b_valid,  s1_b_resp

    );
    
input        clk;
input        rst;    

output          mem_en;
output          read_write;

output  [31:0] addr;
input   [31:0] data_out;
output  [31:0] data_in;  
input hit;  
    
//// raed addr 
input  wire [31:0] s1_ar_addr;
input  wire        s1_ar_valid;
output              s1_ar_ready;
input wire [7:0]    s1_ar_len;     // Number of transfers - 1
input wire [2:0]    s1_ar_size;    // Bytes per transfer = 2^SIZE
input wire [1:0]    s1_ar_burst;   // FIXED / INCR / WRAP

//// write addr 
input  wire [31:0] s1_aw_addr;
input  wire        s1_aw_valid;
output wire        s1_aw_ready;
input wire [7:0] s1_aw_len;     // Number of transfers - 1
input wire [2:0] s1_aw_size;    // Bytes per transfer = 2^SIZE
input wire [1:0] s1_aw_burst;   // FIXED / INCR / WRAP

///// read data
output   [31:0] s1_dr_data;
output          s1_dr_valid;
input           s1_dr_ready;
output          s1_dr_last; 

////  write data 
input  wire [31:0] s1_dw_data;
input  wire        s1_dw_valid;
output wire        s1_dw_ready;
input wire [3:0]   s1_dw_strb;    // Byte write enable
input wire          s1_dw_last;    // Last write-data transfer

/// buffer
input          s1_b_ready;
output          s1_b_valid;
output   [1:0]  s1_b_resp;
    
    
/////// 

reg [2:0]  burst_size;
reg [7:0]  beat_len;
reg [1:0]  burst_type;

reg [31:0] addr_reg;
reg        burst_active_r,burst_active_w;
reg [7:0]  count_len;
reg b_valid_reg;



assign addr          = addr_reg ;
assign mem_en        =( burst_active_r && !hit) ||( burst_active_w && !hit && s1_dw_valid );
assign read_write    =  (burst_active_w );

//// read
assign s1_dr_data    = (burst_active_r && hit)? data_out:32'd0;
assign s1_dr_valid   = burst_active_r && hit;
assign s1_dr_last    = burst_active_r &&(beat_len == count_len );
assign s1_ar_ready  = ~(burst_active_r | burst_active_w);

/// write 
assign s1_aw_ready = ~(burst_active_r | burst_active_w| b_valid_reg) ;
assign s1_dw_ready =   burst_active_w && hit;
// Gated on s1_dw_valid only, NOT on s1_dw_ready. s1_dw_ready is
// burst_active_w && hit, while mem_en is burst_active_w && !hit && s1_dw_valid
// -- the two are mutually exclusive by construction, so in the one cycle the
// memory was enabled this drove 0, and in the cycle it drove the real data the
// memory was no longer enabled. Every write that went out over AXI to main
// memory stored zero.
assign data_in     =  (burst_active_w && s1_dw_valid)?{ s1_dw_data[31:24]& {8{s1_dw_strb[3]}}, 
                                                                       s1_dw_data[23:16]& {8{s1_dw_strb[2]}},
                                                                       s1_dw_data[15:8]& {8{s1_dw_strb[1]}},
                                                                       s1_dw_data[7:0]& {8{s1_dw_strb[0]}}}: 32'd0;

/// buffer 
assign s1_b_resp  =  (b_valid_reg )? 2'd1:2'd0;
assign s1_b_valid =  b_valid_reg ;



////

always @(posedge clk ) 
begin

////// read 

      if(rst)
      begin
           burst_size <= 3'd0;
           beat_len <=  8'd0;
           burst_type <= 2'd0;
           
           addr_reg  <= 32'd0;
           burst_active_r <= 1'd0;
           burst_active_w <= 1'b0;
           
           count_len   <= 8'd0;
           b_valid_reg <= 1'b0;
           
         
            
      end
      
      else 
      begin
           
            
            if( s1_ar_valid && s1_ar_ready  )
            begin
                 burst_size <=  s1_ar_size;
                 beat_len  <=  s1_ar_len;  
                 burst_type <=  s1_ar_burst;
            
                 addr_reg  <= s1_ar_addr;  
                 burst_active_r <= 1'b1;
                 burst_active_w <= 1'b0;
                 count_len <= 8'd0; 
                 
            end
            
            else if( s1_aw_valid && s1_aw_ready  )
            begin
                 burst_size <=  s1_aw_size;
                 beat_len  <=  s1_aw_len;  
                 burst_type <=  s1_aw_burst;
            
                 addr_reg  <= s1_aw_addr;  
                 burst_active_r <= 1'b0;
                 burst_active_w <= 1'b1;
                 b_valid_reg    <= 1'b0;
                 count_len <= 8'd0; 
                
            end
            
                     if(burst_active_r  )
                     begin
                                                                                            
                           if(s1_dr_ready && s1_dr_valid )
                           begin
                          
                               if(beat_len == count_len )
                               begin
                                     burst_active_r <= 1'b0;
                                     addr_reg <=   32'd0;
                                     count_len <= 8'd0;
                     
                                    
                               end
                               else 
                               begin 
                                     if(burst_type == 2'b00)addr_reg <= addr_reg;
                                     else if(burst_type == 2'b01)addr_reg <= addr_reg + (1<<burst_size);
//                                   else if(s1_ar_burst == 2'b10)addr_reg <= addr_reg + (1<<s1_ar_size);                                              
                                     count_len   <= count_len  + 1 ;
                                     burst_active_r <= 1'b1;                      
                               end                                               
                          end                                        
                   end
          
          
                   if(burst_active_w)
                   begin
                          
                          
                   
                         if(s1_b_valid && s1_b_ready)
                             begin
                                  b_valid_reg    <= 1'b0;
                                  burst_active_w <= 1'b0;
                             end                                         
                                
                   
                   
                        if(s1_dw_ready && s1_dw_valid )
                           begin
                              
                          
                               if(beat_len == count_len )
                               begin
                                    if(s1_dw_last)
                                      begin
                                         
                                          addr_reg       <= 32'd0;
                                          count_len      <= 8'd0;
                                          b_valid_reg    <= 1'b1;
                                                                                    
                                      end
                                    
                                    
                                    
                               end
                               
                               else 
                               begin 
                                     if(burst_type == 2'b00)addr_reg <= addr_reg;
                                     else if(burst_type == 2'b01)addr_reg <= addr_reg + (1<<burst_size);
//                                   else if(s1_ar_burst == 2'b10)addr_reg <= addr_reg + (1<<s1_ar_size);                                              
                                     count_len   <= count_len  + 1 ;
                                     burst_active_w <= 1'b1;                      
                               end                                               
                          end                     
                        
                   end
          
    end      
      
end
    
    
endmodule
