`timescale 1ns / 1ps 
 
module axi_lite_dot(clk_1,rst_1, clk_2, rst_2, 
                     
                     s1_ar_addr, s1_ar_valid, s1_ar_ready, 
                     s1_aw_addr, s1_aw_valid, s1_aw_ready, 
                     s1_dr_data, s1_dr_valid, s1_dr_ready,s1_dr_resp,
                     s1_dw_data, s1_dw_valid, s1_dw_ready,s1_dw_strb, 
                     s1_b_ready, s1_b_valid,  s1_b_resp 
 
    ); 
     
 input clk_1,rst_1 , clk_2, rst_2;

//// raed addr  
input  wire [31:0] s1_ar_addr; 
input  wire        s1_ar_valid; 
output             s1_ar_ready; 
 
 
//// write addr  
input  wire [31:0] s1_aw_addr; 
input  wire        s1_aw_valid; 
output wire        s1_aw_ready; 
 
///// read data 
output   [31:0] s1_dr_data; 
output          s1_dr_valid; 
output   [1:0]  s1_dr_resp ; 
input           s1_dr_ready; 

 
////  write data  
input  wire [31:0] s1_dw_data; 
input  wire        s1_dw_valid; 
output wire        s1_dw_ready; 
input wire [3:0]   s1_dw_strb;    // Byte write enable 

 
/// buffer 
input          s1_b_ready; 
output   reg       s1_b_valid; 
output   [1:0]  s1_b_resp; 
 
 
 //// wire
wire        full_r_axi_1;
wire        fifo_empty_1;
wire [31:0] fifo_write_data_axi_1;
wire [31:0] fifo_data_read_1;
wire        write_en_axi_1;
wire        r_en_1;


wire        full_r_axi_2;
wire        fifo_empty_2;
wire [31:0] fifo_write_data_axi_2;
wire [31:0] fifo_data_read_2;
wire        write_en_axi_2;
wire        r_en_2;


wire        fifo_full;
wire        empty_r_axi;
wire [31:0] fifo_data_write;
wire [31:0] fifo_read_data_axi;
wire        w_en;
wire        read_en_axi;

//// dot unit
wire [31:0] va;
wire [31:0] vb;
wire [31:0]  dot_out;

/////  peripheral 

 ///// regs
 reg [31:0]addr_r_w,data_reg, addr_out_read;
 reg addr_r_comp,addr_w_comp ,data_w_comp ;
 

 
/////////// 

asynchronous_fifo_gen #( .width(32),.logofdepth(4))fifo_timer_w1
                         (clk_1,rst_1,
                          clk_2,rst_2,
                          fifo_write_data_axi_1,write_en_axi_1,
                          fifo_data_read_1,r_en_1,
                          full_r_axi_1, fifo_empty_1
                          );
asynchronous_fifo_gen #( .width(32),.logofdepth(4))fifo_timer_w2
                         (clk_1,rst_1,
                          clk_2,rst_2,
                          fifo_write_data_axi_2,write_en_axi_2,
                          fifo_data_read_2,r_en_2,
                          full_r_axi_2, fifo_empty_2
                          );

asynchronous_fifo_gen  #( .width(32),.logofdepth(4))fifo_timer_r
                         (clk_2,rst_2,
                          clk_1,rst_1,                         
                          fifo_data_write,w_en,
                          fifo_read_data_axi,read_en_axi,
                          fifo_full, empty_r_axi
                          ); 
  
/////// peripheral dot 
fp4_dot_unit    fp4_dot_0(clk_2, rst_2, va ,vb , dot_out  );

////
assign fifo_data_write = dot_out;
assign va =  fifo_data_read_1;
assign vb =  fifo_data_read_2;
assign r_en_1 = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);
assign r_en_2 = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);
assign w_en   = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);

/////////////
              
assign write_en_axi_1        = (addr_r_w[3:0] == 4'd0 && addr_w_comp && data_w_comp && !full_r_axi_1 );
assign write_en_axi_2        = (addr_r_w[3:0] == 4'd4 && addr_w_comp && data_w_comp && !full_r_axi_2 );

assign fifo_write_data_axi_1 =  (addr_r_w[3:0] == 4'd0 )?data_reg: 32'd0;                    
assign fifo_write_data_axi_2 =  (addr_r_w[3:0] == 4'd4 )?data_reg: 32'd0; 
// (duplicate assign of s1_aw_ready removed; identical driver kept below
//  in the write section, with s1_dw_ready and s1_b_resp)



//// read
assign s1_ar_ready  = !addr_r_comp;   
assign s1_dr_data   =  ( addr_out_read[3:0] == 4'd8)?fifo_read_data_axi: 32'd0 ; 
assign s1_dr_valid  = !empty_r_axi && addr_r_comp  &&(addr_out_read[3:0] == 4'h8);
assign s1_dr_resp   = 2'd0 ;
assign read_en_axi = s1_dr_valid && s1_dr_ready;


//// write 
assign s1_aw_ready = !addr_w_comp && ((s1_aw_addr[3:0] == 4'h0 && !full_r_axi_1) ||(s1_aw_addr[3:0] == 4'h4 && !full_r_axi_2));
assign s1_dw_ready = addr_w_comp && !data_w_comp &&((addr_r_w[3:0] == 4'h0 && !full_r_axi_1) || (addr_r_w[3:0] == 4'h4 && !full_r_axi_2));
assign s1_b_resp   = 2'b00;
/////write



///// read 
always@(posedge clk_1 )
begin                          
     if(rst_1)
     begin
          addr_r_w <= 32'd0;
          addr_r_comp <= 1'd0;
          addr_w_comp <= 1'b0;
          data_w_comp <= 1'b0;
          s1_b_valid <= 1'b0; 
          data_reg   <= 32'd0; 
          addr_out_read <= 32'd0;
          
 
     end
     else
     begin  //// read addr
           if(s1_ar_valid && s1_ar_ready)
           begin
               addr_r_comp <= 1'b1;
               addr_out_read <= s1_ar_addr;
               
           end
          //// read clear 
           else if(s1_dr_valid && s1_dr_ready)
           begin
               addr_r_comp <= 1'b0;
           end
           
           
            //// write addr
           if((s1_aw_valid && s1_aw_ready))
           begin
                addr_r_w    <= s1_aw_addr;
                addr_w_comp <= 1'b1;
           end
           
           //// write data 
           if((s1_dw_valid && s1_dw_ready))
           begin
                 data_reg   <= s1_dw_data; 
                 data_w_comp <= 1'b1;
           end
           
           
           if(data_w_comp && addr_w_comp && !s1_b_valid )
           begin
                data_w_comp <= 1'b0;
                addr_w_comp <= 1'b0;
                data_reg   <=  32'd0;  
                s1_b_valid <= 1'b1;   
           end
           
           else if(s1_b_valid && s1_b_ready)
           begin
                 s1_b_valid <= 1'b0;   
           end
     
     
     end
 
end  
 
                          
                          
                          
                          

      

// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     s1_dw_strb, addr_r_w[31:4], addr_out_read[31:4],
                     1'b0};

endmodule 
