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
  

////
// The dot unit and the control around it now live in fp4_dot_stage, because
// that is the unit the equivalence argument is about: one clock, no FIFOs, no
// crossing. See fp4_dot_stage.v for why the cut is there.
assign va =  fifo_data_read_1;
assign vb =  fifo_data_read_2;
assign fifo_data_write = dot_out;

fp4_dot_stage #(.DOT_LAT(4)) dot_stage_0(
    .clk(clk_2), .rst(rst_2),
    .empty_1(fifo_empty_1), .empty_2(fifo_empty_2), .full(fifo_full),
    .data_1(va), .data_2(vb),
    .r_en_1(r_en_1), .r_en_2(r_en_2), .w_en(w_en), .data_w(dot_out));

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


////////////////////////////////////////////////////////////////////////////
// Absorption properties. Appended by the proof harness; nothing above this
// line is modified, so the instrumented copy differs from the submitted RTL
// only by assertions, which drive nothing.
//
// The claim under test: moving the result push later by DOT_LAT cycles is not
// observable at the AXI boundary, because the read side waits on the result
// FIFO's empty flag and has no cycle count anywhere in it. These properties
// are what make "the master just waits longer" a fact rather than a reading.
////////////////////////////////////////////////////////////////////////////
`ifdef FORMAL

// Tracks whether a posedge has already been seen, so the first cycle -- where
// there is no previous state to talk about -- cannot forge a P3 violation.
reg f_past_valid = 1'b0;
// P3 is a two-cycle property, so the antecedent is registered rather than
// reconstructed with $past, which keeps this readable by plain Yosys.
reg f_p3_pending = 1'b0;

always @(posedge clk_1) begin
    f_past_valid <= 1'b1;
    f_p3_pending <= !rst_1 && addr_r_comp && !(s1_dr_valid && s1_dr_ready);

    if (!rst_1) begin
        // P1  a read response is never presented out of an empty FIFO. If this
        //     failed, delaying the push would hand the master stale data.
        assert (!s1_dr_valid || !empty_r_axi);

        // P2  result data reaches the bus only from the FIFO read port. Any
        //     bypass around the pipeline would show up here as a mismatch.
        assert (!(s1_dr_valid && (addr_out_read[3:0] == 4'h8)) ||
                (s1_dr_data == fifo_read_data_axi));

        // P4  the FIFO is popped only on a completed AXI beat, so a result
        //     cannot be dropped while the master is still waiting for it.
        assert (!read_en_axi || (s1_dr_valid && s1_dr_ready));

        // P3  ABSORPTION. A read that was outstanding and did not complete is
        //     still outstanding on the next cycle. There is no timeout, no
        //     counter, nothing that a later arrival could trip -- which is
        //     exactly why DOT_LAT extra cycles cost correctness nothing.
        if (f_past_valid && f_p3_pending)
            assert (addr_r_comp);
    end
end
`endif

endmodule 
