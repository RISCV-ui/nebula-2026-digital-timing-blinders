`timescale 1ns / 1ps

// AXI-lite slave wrapper around uart_controller, structurally identical to
// axi_lite_timer / axi_lite_gpio: the AXI side runs on clk_1 and the
// peripheral on clk_2, with a pair of asynchronous FIFOs doing the clock
// domain crossing in each direction.
 
module axi_lite_uart(clk_1,rst_1, clk_2, rst_2, int_out_uart, uart_rx, uart_tx,
                     
                     s1_ar_addr, s1_ar_valid, s1_ar_ready, 
                     s1_aw_addr, s1_aw_valid, s1_aw_ready, 
                     s1_dr_data, s1_dr_valid, s1_dr_ready,s1_dr_resp,
                     s1_dw_data, s1_dw_valid, s1_dw_ready,s1_dw_strb, 
                     s1_b_ready, s1_b_valid,  s1_b_resp 
 
    ); 
     
 input clk_1,rst_1 , clk_2, rst_2;
 output int_out_uart;
 input  uart_rx;
 output uart_tx;
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
wire full_r_axi, empty_r_axi ;
wire [31:0]fifo_read_data_axi,fifo_data_write;
wire write_en_axi, read_en_axi;
wire r_en, w_en, fifo_empty, fifo_full;
wire [40:0]fifo_write_data_axi ,fifo_data_read;

/////  peripheral 
wire read_write,addr_valid;
wire [31:0]data_out,data_in ,addr ;


 ///// regs
 reg [31:0]addr_r_w,data_reg;
 reg addr_r_comp,addr_w_comp ,data_w_comp ;
 

 
/////////// 

asynchronous_fifo_gen #( .width(41),.logofdepth(4))fifo_uart_w
                         (clk_1,rst_1,
                          clk_2,rst_2,
                          fifo_write_data_axi,write_en_axi,
                          fifo_data_read,r_en,
                          full_r_axi, fifo_empty
                          );


asynchronous_fifo_gen  #( .width(32),.logofdepth(4))fifo_uart_r
                         (clk_2,rst_2,
                          clk_1,rst_1,                         
                          fifo_data_write,w_en,
                          fifo_read_data_axi,read_en_axi,
                          fifo_full, empty_r_axi
                          ); 
  
/////// peripheral uart
uart_controller  uart_0(clk_2,rst_2,addr,addr_valid,read_write,data_in,data_out,
                        uart_rx,uart_tx,int_out_uart); 

assign addr       = {24'b0, fifo_data_read[39:32]};
assign addr_valid = !fifo_empty;
assign read_write = fifo_data_read[40];
assign data_in    = fifo_data_read[31:0];
assign r_en       = !fifo_empty;

assign w_en       = !fifo_full && addr_valid && !read_write;
assign fifo_data_write  =  data_out;
assign read_en_axi      =  s1_dr_valid && s1_dr_ready;

/////////////
              
// One command FIFO carries both directions, and the read-address handshake
// wins the mux below. If a read address were accepted in the same cycle a
// write completed, the write's command would be replaced by the read's while
// b_valid still went back -- a silently dropped write. It cannot happen with
// the masters in this SoC: axi_lite_master is single-outstanding (read_active /
// write_active) and the interconnect arbiter gives a slave to one master at a
// time, so a slave port never sees an AR handshake concurrent with a write
// completion. Revisit if either master is ever pipelined.
assign write_en_axi        = (addr_w_comp && data_w_comp || (s1_ar_valid && s1_ar_ready));
assign fifo_write_data_axi = (s1_ar_valid && s1_ar_ready) ?{1'b0, s1_ar_addr[7:0], 32'd0} : 
                                                        {1'b1, addr_r_w[7:0], data_reg};                     

//// read
assign s1_ar_ready  = !full_r_axi ;  
assign s1_dr_data   = fifo_read_data_axi ; 
assign s1_dr_valid  = !empty_r_axi && addr_r_comp ;
assign s1_dr_resp   = 2'd0 ;


//// write 
assign s1_aw_ready = !full_r_axi   ; 
assign s1_dw_ready = !full_r_axi && addr_w_comp; 
assign s1_b_resp   = 2'd0;    




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
 
     end
     else
     begin  //// read addr
           if(s1_ar_valid && s1_ar_ready)
           begin
               addr_r_comp <= 1'b1;
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
                     s1_ar_addr[31:8], s1_dw_strb, addr_r_w[31:8],
                     1'b0};

endmodule 
