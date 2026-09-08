`timescale 1ns / 1ps


module axi_interconnect_2m_8s(clk,rst,
 /// master 1
    m1_ar_addr, m1_ar_valid,  m1_ar_ready,
    m1_aw_addr, m1_aw_valid,  m1_aw_ready,
    m1_dr_data, m1_dr_valid,  m1_dr_ready,
    m1_dw_data, m1_dw_valid,  m1_dw_ready,
    m1_b_ready      , m1_b_valid,   m1_b_resp,
    
        // master 2 
    m2_ar_addr, m2_ar_valid, m2_ar_ready,
    m2_aw_addr, m2_aw_valid, m2_aw_ready,
    m2_dr_data, m2_dr_valid, m2_dr_ready,
    m2_dw_data, m2_dw_valid, m2_dw_ready,
    m2_b_ready,       m2_b_valid,  m2_b_resp,
           
        /// slave 1 
    
    s1_ar_addr, s1_ar_valid, s1_ar_ready,
    s1_aw_addr, s1_aw_valid, s1_aw_ready,
    s1_dr_data, s1_dr_valid, s1_dr_ready,
    s1_dw_data, s1_dw_valid, s1_dw_ready,
    s1_b_ready,       s1_b_valid,  s1_b_resp,   
    
    
    // slave 2
    s2_ar_addr, s2_ar_valid, s2_ar_ready,
    s2_aw_addr, s2_aw_valid, s2_aw_ready,
    s2_dr_data, s2_dr_valid, s2_dr_ready,
    s2_dw_data, s2_dw_valid, s2_dw_ready,
    s2_b_ready,  s2_b_valid,  s2_b_resp,

    // sla
    s3_ar_addr, s3_ar_valid, s3_ar_ready,
    s3_aw_addr, s3_aw_valid, s3_aw_ready,
    s3_dr_data, s3_dr_valid, s3_dr_ready,
    s3_dw_data, s3_dw_valid, s3_dw_ready,
    s3_b_ready,  s3_b_valid,  s3_b_resp,

    // sl
    s4_ar_addr, s4_ar_valid, s4_ar_ready,
    s4_aw_addr, s4_aw_valid, s4_aw_ready,
    s4_dr_data, s4_dr_valid, s4_dr_ready,
    s4_dw_data, s4_dw_valid, s4_dw_ready,
    s4_b_ready,  s4_b_valid,  s4_b_resp,

    // slav
    s5_ar_addr, s5_ar_valid, s5_ar_ready,
    s5_aw_addr, s5_aw_valid, s5_aw_ready,
    s5_dr_data, s5_dr_valid, s5_dr_ready,
    s5_dw_data, s5_dw_valid, s5_dw_ready,
    s5_b_ready,  s5_b_valid,  s5_b_resp,

    // ala
    s6_ar_addr, s6_ar_valid, s6_ar_ready,
    s6_aw_addr, s6_aw_valid, s6_aw_ready,
    s6_dr_data, s6_dr_valid, s6_dr_ready,
    s6_dw_data, s6_dw_valid, s6_dw_ready,
    s6_b_ready,  s6_b_valid,  s6_b_resp,

    // sla
    s7_ar_addr, s7_ar_valid, s7_ar_ready,
    s7_aw_addr, s7_aw_valid, s7_aw_ready,
    s7_dr_data, s7_dr_valid, s7_dr_ready,
    s7_dw_data, s7_dw_valid, s7_dw_ready,
    s7_b_ready , s7_b_valid,  s7_b_resp,

    // sla
    s8_ar_addr, s8_ar_valid, s8_ar_ready,
    s8_aw_addr, s8_aw_valid, s8_aw_ready,
    s8_dr_data, s8_dr_valid, s8_dr_ready,
    s8_dw_data, s8_dw_valid, s8_dw_ready,
    s8_b_ready,       s8_b_valid,  s8_b_resp

        );
    

input clk,rst;

///// master 1 

input         [31:0] m1_ar_addr;
input                m1_ar_valid;
output reg           m1_ar_ready;

input         [31:0] m1_aw_addr;
input                m1_aw_valid;
output reg           m1_aw_ready;

output reg    [31:0] m1_dr_data;
output reg           m1_dr_valid;
input                m1_dr_ready;

input         [31:0] m1_dw_data;
input                m1_dw_valid;
output reg           m1_dw_ready;

input                m1_b_ready;
output reg           m1_b_valid;
output reg    [1:0]  m1_b_resp;


// master 2

input         [31:0] m2_ar_addr;
input                m2_ar_valid;
output reg           m2_ar_ready;

input         [31:0] m2_aw_addr;
input                m2_aw_valid;
output reg           m2_aw_ready;

output reg    [31:0] m2_dr_data;
output reg           m2_dr_valid;
input                m2_dr_ready;

input         [31:0] m2_dw_data;
input                m2_dw_valid;
output reg           m2_dw_ready;

input                m2_b_ready;
output reg           m2_b_valid;
output reg    [1:0]  m2_b_resp;


// Every forward handshake below is qualified by the owning master's decode.
// The address and data buses may fan out to all eight slaves harmlessly, but
// the valid and ready strobes may not: they were driven from m*_?_valid alone,
// so one write was presented to ALL EIGHT slaves at once and every one of them
// latched it. A store to main memory silently overwrote the timer, the gpio
// and the uart at the same offset, and a read handshake was acknowledged by
// slaves that had never been addressed. Only the decoded slave sees a strobe.

// slave 1
output reg [31:0] s1_ar_addr;
output reg        s1_ar_valid;
input             s1_ar_ready;

output reg [31:0] s1_aw_addr;
output reg        s1_aw_valid;
input             s1_aw_ready;

input      [31:0] s1_dr_data;
input             s1_dr_valid;
output reg        s1_dr_ready;

output reg [31:0] s1_dw_data;
output reg        s1_dw_valid;
input             s1_dw_ready;

output reg        s1_b_ready;
input             s1_b_valid;
input      [1:0]  s1_b_resp;


// slave 2
output reg [31:0] s2_ar_addr;
output reg        s2_ar_valid;
input             s2_ar_ready;

output reg [31:0] s2_aw_addr;
output reg        s2_aw_valid;
input             s2_aw_ready;

input      [31:0] s2_dr_data;
input             s2_dr_valid;
output reg        s2_dr_ready;

output reg [31:0] s2_dw_data;
output reg        s2_dw_valid;
input             s2_dw_ready;

output reg        s2_b_ready;
input             s2_b_valid;
input      [1:0]  s2_b_resp;


// slave 3
output reg [31:0] s3_ar_addr;
output reg        s3_ar_valid;
input             s3_ar_ready;

output reg [31:0] s3_aw_addr;
output reg        s3_aw_valid;
input             s3_aw_ready;

input      [31:0] s3_dr_data;
input             s3_dr_valid;
output reg        s3_dr_ready;

output reg [31:0] s3_dw_data;
output reg        s3_dw_valid;
input             s3_dw_ready;

output reg        s3_b_ready;
input             s3_b_valid;
input      [1:0]  s3_b_resp;


// slave 4
output reg [31:0] s4_ar_addr;
output reg        s4_ar_valid;
input             s4_ar_ready;

output reg [31:0] s4_aw_addr;
output reg        s4_aw_valid;
input             s4_aw_ready;

input      [31:0] s4_dr_data;
input             s4_dr_valid;
output reg        s4_dr_ready;

output reg [31:0] s4_dw_data;
output reg        s4_dw_valid;
input             s4_dw_ready;

output reg        s4_b_ready;
input             s4_b_valid;
input      [1:0]  s4_b_resp;


// slave 5
output reg [31:0] s5_ar_addr;
output reg        s5_ar_valid;
input             s5_ar_ready;

output reg [31:0] s5_aw_addr;
output reg        s5_aw_valid;
input             s5_aw_ready;

input      [31:0] s5_dr_data;
input             s5_dr_valid;
output reg        s5_dr_ready;

output reg [31:0] s5_dw_data;
output reg        s5_dw_valid;
input             s5_dw_ready;

output reg        s5_b_ready;
input             s5_b_valid;
input      [1:0]  s5_b_resp;


// slave 6
output reg [31:0] s6_ar_addr;
output reg        s6_ar_valid;
input             s6_ar_ready;

output reg [31:0] s6_aw_addr;
output reg        s6_aw_valid;
input             s6_aw_ready;

input      [31:0] s6_dr_data;
input             s6_dr_valid;
output reg        s6_dr_ready;

output reg [31:0] s6_dw_data;
output reg        s6_dw_valid;
input             s6_dw_ready;

output reg        s6_b_ready;
input             s6_b_valid;
input      [1:0]  s6_b_resp;


// slave 7
output reg [31:0] s7_ar_addr;
output reg        s7_ar_valid;
input             s7_ar_ready;

output reg [31:0] s7_aw_addr;
output reg        s7_aw_valid;
input             s7_aw_ready;

input      [31:0] s7_dr_data;
input             s7_dr_valid;
output reg        s7_dr_ready;

output reg [31:0] s7_dw_data;
output reg        s7_dw_valid;
input             s7_dw_ready;

output reg        s7_b_ready;
input             s7_b_valid;
input      [1:0]  s7_b_resp;


// slave 8
output reg [31:0] s8_ar_addr;
output reg        s8_ar_valid;
input             s8_ar_ready;

output reg [31:0] s8_aw_addr;
output reg        s8_aw_valid;
input             s8_aw_ready;

input      [31:0] s8_dr_data;
input             s8_dr_valid;
output reg        s8_dr_ready;

output reg [31:0] s8_dw_data;
output reg        s8_dw_valid;
input             s8_dw_ready;

output reg        s8_b_ready;
input             s8_b_valid;
input      [1:0]  s8_b_resp;

 
////////////////////////////    
//// wires
wire [7:0]req_cpu,req_dma,grant,clear_cpu,clear_dma;

////// regs 
reg [3:0]slave_sel_id_m1,slave_sel_id_m2;
reg [27:0]addr_m1,addr_m2;
reg [3:0] slave_sel_reg_m1,slave_sel_reg_m2;



///// assign 
arbiter arbt_1(clk, rst, req_cpu[0], req_dma[0], grant[0], clear_cpu[0], clear_dma[0]);
arbiter arbt_2(clk, rst, req_cpu[1], req_dma[1], grant[1], clear_cpu[1], clear_dma[1]);
arbiter arbt_3(clk, rst, req_cpu[2], req_dma[2], grant[2], clear_cpu[2], clear_dma[2]);
arbiter arbt_4(clk, rst, req_cpu[3], req_dma[3], grant[3], clear_cpu[3], clear_dma[3]);
                                           
arbiter arbt_5(clk, rst, req_cpu[4], req_dma[4], grant[4], clear_cpu[4], clear_dma[4]);
arbiter arbt_6(clk, rst, req_cpu[5], req_dma[5], grant[5], clear_cpu[5], clear_dma[5]);
arbiter arbt_7(clk, rst, req_cpu[6], req_dma[6], grant[6], clear_cpu[6], clear_dma[6]);
arbiter arbt_8(clk, rst, req_cpu[7], req_dma[7], grant[7], clear_cpu[7], clear_dma[7]);

wire [3:0] sel_m1;
wire [3:0] sel_m2;

assign sel_m1 = (m1_ar_valid || m1_aw_valid) ? slave_sel_id_m1 : slave_sel_reg_m1;
assign sel_m2 = (m2_ar_valid || m2_aw_valid) ? slave_sel_id_m2 : slave_sel_reg_m2;

// A decoder output is only a request when that master actually has a
// transaction. Both decoders fall through to their default slave for the
// zero address they see while idle, so req_cpu[7] used to be stuck at 1 --
// and the slave-8 arbiter grants the DMA only when the CPU is not asking, so
// the DMA could never win main memory at all.
//
// The qualifier has to cover the whole transaction, not just the address
// phase: a master drops ar_valid as soon as the address is accepted and then
// waits for read data. Dropping the request there would hand the slave to the
// other master mid-transaction and switch the data mux out from under it, so
// an outstanding-transaction flag holds the request up to the response.

reg  m1_busy, m2_busy;
wire m1_start, m2_start;
wire m1_end,   m2_end;

assign m1_start = (m1_ar_valid || m1_aw_valid) && !m1_busy;
assign m1_end   = (m1_dr_valid && m1_dr_ready) || (m1_b_valid && m1_b_ready);
assign m2_start = (m2_ar_valid || m2_aw_valid) && !m2_busy;
assign m2_end   = (m2_dr_valid && m2_dr_ready) || (m2_b_valid && m2_b_ready);

always@(posedge clk)
begin
     if(rst)          m1_busy <= 1'b0;
     else if(m1_end)  m1_busy <= 1'b0;
     else if(m1_start)m1_busy <= 1'b1;

     if(rst)          m2_busy <= 1'b0;
     else if(m2_end)  m2_busy <= 1'b0;
     else if(m2_start)m2_busy <= 1'b1;
end

wire m1_pending, m2_pending;
assign m1_pending = m1_ar_valid || m1_aw_valid || m1_busy;
assign m2_pending = m2_ar_valid || m2_aw_valid || m2_busy;

assign req_cpu[0] = m1_pending && (sel_m1 == 4'd1);
assign req_cpu[1] = m1_pending && (sel_m1 == 4'd2);
assign req_cpu[2] = m1_pending && (sel_m1 == 4'd3);
assign req_cpu[3] = m1_pending && (sel_m1 == 4'd4);
assign req_cpu[4] = m1_pending && (sel_m1 == 4'd5);
assign req_cpu[5] = m1_pending && (sel_m1 == 4'd6);
assign req_cpu[6] = m1_pending && (sel_m1 == 4'd7);
assign req_cpu[7] = m1_pending && (sel_m1 == 4'd8);

assign req_dma[0] = m2_pending && (sel_m2 == 4'd1);
assign req_dma[1] = m2_pending && (sel_m2 == 4'd2);
assign req_dma[2] = m2_pending && (sel_m2 == 4'd3);
assign req_dma[3] = m2_pending && (sel_m2 == 4'd4);
assign req_dma[4] = m2_pending && (sel_m2 == 4'd5);
assign req_dma[5] = m2_pending && (sel_m2 == 4'd6);
assign req_dma[6] = m2_pending && (sel_m2 == 4'd7);
assign req_dma[7] = m2_pending && (sel_m2 == 4'd8);


assign clear_cpu[0] = (slave_sel_reg_m1 == 4'd1) ? (m1_dr_valid | m1_b_valid) : 1'b0;
assign clear_dma[0] = (slave_sel_reg_m2 == 4'd1) ? (m2_dr_valid | m2_b_valid) : 1'b0;

assign clear_cpu[1] = (slave_sel_reg_m1 == 4'd2) ? (m1_dr_valid | m1_b_valid) : 1'b0;
assign clear_dma[1] = (slave_sel_reg_m2 == 4'd2) ? (m2_dr_valid | m2_b_valid) : 1'b0;

assign clear_cpu[2] = (slave_sel_reg_m1 == 4'd3) ? (m1_dr_valid | m1_b_valid) : 1'b0;
assign clear_dma[2] = (slave_sel_reg_m2 == 4'd3) ? (m2_dr_valid | m2_b_valid) : 1'b0;

assign clear_cpu[3] = (slave_sel_reg_m1 == 4'd4) ? (m1_dr_valid | m1_b_valid) : 1'b0;
assign clear_dma[3] = (slave_sel_reg_m2 == 4'd4) ? (m2_dr_valid | m2_b_valid) : 1'b0;

assign clear_cpu[4] = (slave_sel_reg_m1 == 4'd5) ? (m1_dr_valid | m1_b_valid) : 1'b0;
assign clear_dma[4] = (slave_sel_reg_m2 == 4'd5) ? (m2_dr_valid | m2_b_valid) : 1'b0;

assign clear_cpu[5] = (slave_sel_reg_m1 == 4'd6) ? (m1_dr_valid | m1_b_valid) : 1'b0;
assign clear_dma[5] = (slave_sel_reg_m2 == 4'd6) ? (m2_dr_valid | m2_b_valid) : 1'b0;

assign clear_cpu[6] = (slave_sel_reg_m1 == 4'd7) ? (m1_dr_valid | m1_b_valid) : 1'b0;
assign clear_dma[6] = (slave_sel_reg_m2 == 4'd7) ? (m2_dr_valid | m2_b_valid) : 1'b0;

assign clear_cpu[7] = (slave_sel_reg_m1 == 4'd8) ? (m1_dr_valid | m1_b_valid) : 1'b0;
assign clear_dma[7] = (slave_sel_reg_m2 == 4'd8) ? (m2_dr_valid | m2_b_valid) : 1'b0;



//// seqv   
always@(*)
begin
addr_m1 = 28'd0;
addr_m2 = 28'd0;



//// master 1 addr 
     if(m1_ar_valid == 1'b1) 
     begin
          addr_m1 = m1_ar_addr[31:4];
     end
     
     else if(m1_aw_valid == 1'b1) 
     begin
          addr_m1 = m1_aw_addr[31:4];
     end
//// master 2 addr     
     if(m2_ar_valid == 1'b1) 
     begin
          addr_m2 = m2_ar_addr[31:4];   // was m1_ar_addr: DMA reads decoded off the CPU address
     end
     
     else if(m2_aw_valid == 1'b1) 
     begin
          addr_m2 = m2_aw_addr[31:4];
     end
     
     

end

always@(posedge clk)
begin


     if(rst)
            slave_sel_reg_m1 <= 4'd0;
     else if(m1_ar_valid == 1'b1 || m1_aw_valid == 1'b1)
            slave_sel_reg_m1 <= slave_sel_id_m1; 
    
     if(rst)
            slave_sel_reg_m2 <= 4'd0;
     else if(m2_ar_valid == 1'b1 || m2_aw_valid == 1'b1)
            slave_sel_reg_m2 <= slave_sel_id_m2; 

end






always@(*)
begin

////// decoder 1          
          case(addr_m1)
          
          28'hf000_000:  slave_sel_id_m1 = 4'd1; //// timer 0 , 4 ,  8 , c 
          
          28'hf000_001,
          28'hf000_002,
          28'hf000_003:  slave_sel_id_m1 = 4'd2; //// gpio 10 - 38 
          
          28'hf000_004,
          28'hf000_005: slave_sel_id_m1 = 4'd3; //// dam 40 - 54 
          
          28'hf000_006,
          28'hf000_007,
          28'hf000_008: slave_sel_id_m1 = 4'd4; /// uart 60 - 70 
                                      
          28'hf000_f00: slave_sel_id_m1 = 4'd5;  //// dot accelerator 0 - c 
          
//          28'hf000_0: slave_sel_id_m1 = 4'd6;  //// for future
//          28'hf000_0: slave_sel_id_m1 = 4'd7;
//          28'hf000_0: slave_sel_id_m1 = 4'd8;
                          
         default : slave_sel_id_m1 = 4'd8;    //// d cache remaining from above              
                     
     endcase
     
   
     
     
///// decoder 2      
               
          case(addr_m2)                                                   
                                                                                   
          28'hf000_000:  slave_sel_id_m2 = 4'd1; //// timer 0 , 4 ,  8 , c         
                                                                                   
          28'hf000_001,                                                            
          28'hf000_002,                                                            
          28'hf000_003:  slave_sel_id_m2 = 4'd2; //// gpio 10 - 38                 
                                                                                   
          28'hf000_004,                                                            
          28'hf000_005: slave_sel_id_m2 = 4'd3; //// dam 40 - 54                   
                                                                                   
          28'hf000_006,                                                            
          28'hf000_007,                                                            
          28'hf000_008: slave_sel_id_m2 = 4'd4; /// uart 60 - 70                   
                                                                                   
          28'hf000_f00: slave_sel_id_m2 = 4'd5;  //// dot accelerator 0 - c        
                                                                                   
//          28'hf000_0: slave_sel_id_m2 = 4'd6;  //// for future                   
//          28'hf000_0: slave_sel_id_m2 = 4'd7;                                    
//          28'hf000_0: slave_sel_id_m2 = 4'd8;                                    
                                                                                   
         // 4'd8, matching decoder 1. This was 4'd7, an unused slave port, so
         // every DMA access to main memory (anything outside device space)
         // was decoded to a port nothing answers: the engine issued its first
         // read address and waited on ar_ready for ever.
         default : slave_sel_id_m2 = 4'd8;    //// main memory, as for master 1

                     
     endcase
     
    



end





always@(*)
begin 

// default values

s1_ar_addr   = 32'd0;
s1_ar_valid  = 1'b0;
s1_aw_addr   = 32'd0;
s1_aw_valid  = 1'b0;
s1_dw_data   = 32'd0;
s1_dw_valid  = 1'b0;
s1_dr_ready  = 1'b0;
s1_b_ready   = 1'b0;

s2_ar_addr   = 32'd0;
s2_ar_valid  = 1'b0;
s2_aw_addr   = 32'd0;
s2_aw_valid  = 1'b0;
s2_dw_data   = 32'd0;
s2_dw_valid  = 1'b0;
s2_dr_ready  = 1'b0;
s2_b_ready   = 1'b0;

s3_ar_addr   = 32'd0;
s3_ar_valid  = 1'b0;
s3_aw_addr   = 32'd0;
s3_aw_valid  = 1'b0;
s3_dw_data   = 32'd0;
s3_dw_valid  = 1'b0;
s3_dr_ready  = 1'b0;
s3_b_ready   = 1'b0;

s4_ar_addr   = 32'd0;
s4_ar_valid  = 1'b0;
s4_aw_addr   = 32'd0;
s4_aw_valid  = 1'b0;
s4_dw_data   = 32'd0;
s4_dw_valid  = 1'b0;
s4_dr_ready  = 1'b0;
s4_b_ready   = 1'b0;

s5_ar_addr   = 32'd0;
s5_ar_valid  = 1'b0;
s5_aw_addr   = 32'd0;
s5_aw_valid  = 1'b0;
s5_dw_data   = 32'd0;
s5_dw_valid  = 1'b0;
s5_dr_ready  = 1'b0;
s5_b_ready   = 1'b0;

s6_ar_addr   = 32'd0;
s6_ar_valid  = 1'b0;
s6_aw_addr   = 32'd0;
s6_aw_valid  = 1'b0;
s6_dw_data   = 32'd0;
s6_dw_valid  = 1'b0;
s6_dr_ready  = 1'b0;
s6_b_ready   = 1'b0;

s7_ar_addr   = 32'd0;
s7_ar_valid  = 1'b0;
s7_aw_addr   = 32'd0;
s7_aw_valid  = 1'b0;
s7_dw_data   = 32'd0;
s7_dw_valid  = 1'b0;
s7_dr_ready  = 1'b0;
s7_b_ready   = 1'b0;

s8_ar_addr   = 32'd0;
s8_ar_valid  = 1'b0;
s8_aw_addr   = 32'd0;
s8_aw_valid  = 1'b0;
s8_dw_data   = 32'd0;
s8_dw_valid  = 1'b0;
s8_dr_ready  = 1'b0;
s8_b_ready   = 1'b0;


// master out

m1_ar_ready  = 1'b0;
m1_aw_ready  = 1'b0;
m1_dw_ready  = 1'b0;
m1_dr_data   = 32'd0;
m1_dr_valid  = 1'b0;
m1_b_resp    = 2'd0;
m1_b_valid   = 1'b0;

m2_ar_ready  = 1'b0;
m2_aw_ready  = 1'b0;
m2_dw_ready  = 1'b0;
m2_dr_data   = 32'd0;
m2_dr_valid  = 1'b0;
m2_b_resp    = 2'd0;
m2_b_valid   = 1'b0;

// slave 1 
s1_ar_addr    = (grant[0] == 0)?m1_ar_addr: m2_ar_addr ;
s1_ar_valid = (grant[0] == 0) ? (m1_ar_valid && (sel_m1 == 4'd1)) : (m2_ar_valid && (sel_m2 == 4'd1)) ;

s1_aw_addr  = (grant[0] == 0) ? m1_aw_addr   :  m2_aw_addr ;
s1_aw_valid = (grant[0] == 0) ? (m1_aw_valid && (sel_m1 == 4'd1)) : (m2_aw_valid && (sel_m2 == 4'd1)) ;

s1_dw_data  = (grant[0] == 0) ?  m1_dw_data  : m2_dw_data  ;
s1_dw_valid = (grant[0] == 0) ? (m1_dw_valid && (sel_m1 == 4'd1)) : (m2_dw_valid && (sel_m2 == 4'd1)) ;

s1_dr_ready = (grant[0] == 0) ? (m1_dr_ready && (sel_m1 == 4'd1)) : (m2_dr_ready && (sel_m2 == 4'd1)) ;

s1_b_ready = (grant[0] == 0) ? (m1_b_ready && (sel_m1 == 4'd1)) : (m2_b_ready && (sel_m2 == 4'd1)) ;

// slave 2
s2_ar_addr    = (grant[1] == 0)?m1_ar_addr: m2_ar_addr ;
s2_ar_valid = (grant[1] == 0) ? (m1_ar_valid && (sel_m1 == 4'd2)) : (m2_ar_valid && (sel_m2 == 4'd2)) ;

s2_aw_addr    = (grant[1] == 0)?m1_aw_addr: m2_aw_addr ;
s2_aw_valid = (grant[1] == 0) ? (m1_aw_valid && (sel_m1 == 4'd2)) : (m2_aw_valid && (sel_m2 == 4'd2)) ;

s2_dw_data    = (grant[1] == 0)?m1_dw_data: m2_dw_data ;
s2_dw_valid = (grant[1] == 0) ? (m1_dw_valid && (sel_m1 == 4'd2)) : (m2_dw_valid && (sel_m2 == 4'd2)) ;

s2_dr_ready = (grant[1] == 0) ? (m1_dr_ready && (sel_m1 == 4'd2)) : (m2_dr_ready && (sel_m2 == 4'd2)) ;
s2_b_ready = (grant[1] == 0) ? (m1_b_ready && (sel_m1 == 4'd2)) : (m2_b_ready && (sel_m2 == 4'd2)) ;


// slave 3
s3_ar_addr    = (grant[2] == 0)?m1_ar_addr: m2_ar_addr ;
s3_ar_valid = (grant[2] == 0) ? (m1_ar_valid && (sel_m1 == 4'd3)) : (m2_ar_valid && (sel_m2 == 4'd3)) ;

s3_aw_addr    = (grant[2] == 0)?m1_aw_addr: m2_aw_addr ;
s3_aw_valid = (grant[2] == 0) ? (m1_aw_valid && (sel_m1 == 4'd3)) : (m2_aw_valid && (sel_m2 == 4'd3)) ;

s3_dw_data    = (grant[2] == 0)?m1_dw_data: m2_dw_data ;
s3_dw_valid = (grant[2] == 0) ? (m1_dw_valid && (sel_m1 == 4'd3)) : (m2_dw_valid && (sel_m2 == 4'd3)) ;

s3_dr_ready = (grant[2] == 0) ? (m1_dr_ready && (sel_m1 == 4'd3)) : (m2_dr_ready && (sel_m2 == 4'd3)) ;
s3_b_ready = (grant[2] == 0) ? (m1_b_ready && (sel_m1 == 4'd3)) : (m2_b_ready && (sel_m2 == 4'd3)) ;


// slave 4
s4_ar_addr    = (grant[3] == 0)?m1_ar_addr: m2_ar_addr ;
s4_ar_valid = (grant[3] == 0) ? (m1_ar_valid && (sel_m1 == 4'd4)) : (m2_ar_valid && (sel_m2 == 4'd4)) ;

s4_aw_addr    = (grant[3] == 0)?m1_aw_addr: m2_aw_addr ;
s4_aw_valid = (grant[3] == 0) ? (m1_aw_valid && (sel_m1 == 4'd4)) : (m2_aw_valid && (sel_m2 == 4'd4)) ;

s4_dw_data    = (grant[3] == 0)?m1_dw_data: m2_dw_data ;
s4_dw_valid = (grant[3] == 0) ? (m1_dw_valid && (sel_m1 == 4'd4)) : (m2_dw_valid && (sel_m2 == 4'd4)) ;

s4_dr_ready = (grant[3] == 0) ? (m1_dr_ready && (sel_m1 == 4'd4)) : (m2_dr_ready && (sel_m2 == 4'd4)) ;
s4_b_ready = (grant[3] == 0) ? (m1_b_ready && (sel_m1 == 4'd4)) : (m2_b_ready && (sel_m2 == 4'd4)) ;


// slave 5
s5_ar_addr    = (grant[4] == 0)?m1_ar_addr: m2_ar_addr ;
s5_ar_valid = (grant[4] == 0) ? (m1_ar_valid && (sel_m1 == 4'd5)) : (m2_ar_valid && (sel_m2 == 4'd5)) ;

s5_aw_addr    = (grant[4] == 0)?m1_aw_addr: m2_aw_addr ;
s5_aw_valid = (grant[4] == 0) ? (m1_aw_valid && (sel_m1 == 4'd5)) : (m2_aw_valid && (sel_m2 == 4'd5)) ;

s5_dw_data    = (grant[4] == 0)?m1_dw_data: m2_dw_data ;
s5_dw_valid = (grant[4] == 0) ? (m1_dw_valid && (sel_m1 == 4'd5)) : (m2_dw_valid && (sel_m2 == 4'd5)) ;

s5_dr_ready = (grant[4] == 0) ? (m1_dr_ready && (sel_m1 == 4'd5)) : (m2_dr_ready && (sel_m2 == 4'd5)) ;
s5_b_ready = (grant[4] == 0) ? (m1_b_ready && (sel_m1 == 4'd5)) : (m2_b_ready && (sel_m2 == 4'd5)) ;


// slave 6
s6_ar_addr    = (grant[5] == 0)?m1_ar_addr: m2_ar_addr ;
s6_ar_valid = (grant[5] == 0) ? (m1_ar_valid && (sel_m1 == 4'd6)) : (m2_ar_valid && (sel_m2 == 4'd6)) ;

s6_aw_addr    = (grant[5] == 0)?m1_aw_addr: m2_aw_addr ;
s6_aw_valid = (grant[5] == 0) ? (m1_aw_valid && (sel_m1 == 4'd6)) : (m2_aw_valid && (sel_m2 == 4'd6)) ;

s6_dw_data    = (grant[5] == 0)?m1_dw_data: m2_dw_data ;
s6_dw_valid = (grant[5] == 0) ? (m1_dw_valid && (sel_m1 == 4'd6)) : (m2_dw_valid && (sel_m2 == 4'd6)) ;

s6_dr_ready = (grant[5] == 0) ? (m1_dr_ready && (sel_m1 == 4'd6)) : (m2_dr_ready && (sel_m2 == 4'd6)) ;
s6_b_ready = (grant[5] == 0) ? (m1_b_ready && (sel_m1 == 4'd6)) : (m2_b_ready && (sel_m2 == 4'd6)) ;


// slave 7
s7_ar_addr    = (grant[6] == 0)?m1_ar_addr: m2_ar_addr ;
s7_ar_valid = (grant[6] == 0) ? (m1_ar_valid && (sel_m1 == 4'd7)) : (m2_ar_valid && (sel_m2 == 4'd7)) ;

s7_aw_addr    = (grant[6] == 0)?m1_aw_addr: m2_aw_addr ;
s7_aw_valid = (grant[6] == 0) ? (m1_aw_valid && (sel_m1 == 4'd7)) : (m2_aw_valid && (sel_m2 == 4'd7)) ;

s7_dw_data    = (grant[6] == 0)?m1_dw_data: m2_dw_data ;
s7_dw_valid = (grant[6] == 0) ? (m1_dw_valid && (sel_m1 == 4'd7)) : (m2_dw_valid && (sel_m2 == 4'd7)) ;

s7_dr_ready = (grant[6] == 0) ? (m1_dr_ready && (sel_m1 == 4'd7)) : (m2_dr_ready && (sel_m2 == 4'd7)) ;
s7_b_ready = (grant[6] == 0) ? (m1_b_ready && (sel_m1 == 4'd7)) : (m2_b_ready && (sel_m2 == 4'd7)) ;


// slave 8
s8_ar_addr    = (grant[7] == 0)?m1_ar_addr: m2_ar_addr ;
s8_ar_valid = (grant[7] == 0) ? (m1_ar_valid && (sel_m1 == 4'd8)) : (m2_ar_valid && (sel_m2 == 4'd8)) ;

s8_aw_addr    = (grant[7] == 0)?m1_aw_addr: m2_aw_addr ;
s8_aw_valid = (grant[7] == 0) ? (m1_aw_valid && (sel_m1 == 4'd8)) : (m2_aw_valid && (sel_m2 == 4'd8)) ;

s8_dw_data    = (grant[7] == 0)?m1_dw_data: m2_dw_data ;
s8_dw_valid = (grant[7] == 0) ? (m1_dw_valid && (sel_m1 == 4'd8)) : (m2_dw_valid && (sel_m2 == 4'd8)) ;

s8_dr_ready = (grant[7] == 0) ? (m1_dr_ready && (sel_m1 == 4'd8)) : (m2_dr_ready && (sel_m2 == 4'd8)) ;
s8_b_ready = (grant[7] == 0) ? (m1_b_ready && (sel_m1 == 4'd8)) : (m2_b_ready && (sel_m2 == 4'd8)) ;


// Response routing select.
//
// The forward path (s*_ar_valid, s*_aw_addr, ...) is muxed combinationally
// from the address being presented, but the return path below was muxed from
// slave_sel_reg_*, which only updates on the NEXT clock edge. So in the cycle
// a master first presents an address, the slave already saw ar_valid and
// asserted ar_ready, while the master's own ar_ready was still driven from
// the stale (reset: 0, no case match) selection and read 0. The slave latched
// the request and went busy; the master never saw the handshake and held
// ar_valid forever. Deadlock on the very first bus transaction.
//
// The registered select is still needed for the data phase, after the address
// valid has dropped. So: use the live decode while an address is being
// presented, the registered one afterwards.


////// master  1 inpt 
     case(sel_m1)
      
      4'd1: 
      begin    ///  adder read 
              
            m1_ar_ready   = (grant[0] == 0)? s1_ar_ready:1'b0 ;            
            //// addra write
            
            m1_aw_ready = (grant[0] == 0)?s1_aw_ready :1'b0 ;
            
            /// data write 
            
            m1_dw_ready =  (grant[0] == 0) ?s1_dw_ready :1'b0;
            
            // date read 
            m1_dr_data  =   (grant[0] == 0) ?s1_dr_data :32'd0 ;
            m1_dr_valid  =  (grant[0] == 0) ? s1_dr_valid :1'b0;                        
            
            /// response 
            
            m1_b_resp  =  (grant[0] == 0) ? s1_b_resp :2'd0;
            m1_b_valid =  (grant[0] == 0) ?s1_b_valid :1'b0 ;  
                                                                        
                                
      end
      4'd2:
      begin
            m1_ar_ready = (grant[1] == 0) ? s2_ar_ready : 1'b0;
            m1_aw_ready = (grant[1] == 0) ? s2_aw_ready : 1'b0;
            m1_dw_ready = (grant[1] == 0) ? s2_dw_ready : 1'b0;
     
            m1_dr_data  = (grant[1] == 0) ? s2_dr_data  : 32'd0;
            m1_dr_valid = (grant[1] == 0) ? s2_dr_valid : 1'b0;
     
            m1_b_resp   = (grant[1] == 0) ? s2_b_resp   : 2'd0;
            m1_b_valid  = (grant[1] == 0) ? s2_b_valid  : 1'b0;
      end
      
      
      4'd3:
      begin
            m1_ar_ready = (grant[2] == 0) ? s3_ar_ready : 1'b0;
            m1_aw_ready = (grant[2] == 0) ? s3_aw_ready : 1'b0;
            m1_dw_ready = (grant[2] == 0) ? s3_dw_ready : 1'b0;
         
            m1_dr_data  = (grant[2] == 0) ? s3_dr_data  : 32'd0;
            m1_dr_valid = (grant[2] == 0) ? s3_dr_valid : 1'b0;
         
            m1_b_resp   = (grant[2] == 0) ? s3_b_resp   : 2'd0;
            m1_b_valid  = (grant[2] == 0) ? s3_b_valid  : 1'b0;
      end
      
      
      4'd4:
      begin
            m1_ar_ready = (grant[3] == 0) ? s4_ar_ready : 1'b0;
            m1_aw_ready = (grant[3] == 0) ? s4_aw_ready : 1'b0;
            m1_dw_ready = (grant[3] == 0) ? s4_dw_ready : 1'b0;
        
            m1_dr_data  = (grant[3] == 0) ? s4_dr_data  : 32'd0;
            m1_dr_valid = (grant[3] == 0) ? s4_dr_valid : 1'b0;
        
            m1_b_resp   = (grant[3] == 0) ? s4_b_resp   : 2'd0;
            m1_b_valid  = (grant[3] == 0) ? s4_b_valid  : 1'b0;
      end
      
      
      4'd5:
      begin
            m1_ar_ready = (grant[4] == 0) ? s5_ar_ready : 1'b0;
            m1_aw_ready = (grant[4] == 0) ? s5_aw_ready : 1'b0;
            m1_dw_ready = (grant[4] == 0) ? s5_dw_ready : 1'b0;
          
            m1_dr_data  = (grant[4] == 0) ? s5_dr_data  : 32'd0;
            m1_dr_valid = (grant[4] == 0) ? s5_dr_valid : 1'b0;
          
            m1_b_resp   = (grant[4] == 0) ? s5_b_resp   : 2'd0;
            m1_b_valid  = (grant[4] == 0) ? s5_b_valid  : 1'b0;
      end
      
      
      4'd6:
      begin
            m1_ar_ready = (grant[5] == 0) ? s6_ar_ready : 1'b0;
            m1_aw_ready = (grant[5] == 0) ? s6_aw_ready : 1'b0;
            m1_dw_ready = (grant[5] == 0) ? s6_dw_ready : 1'b0;
        
            m1_dr_data  = (grant[5] == 0) ? s6_dr_data  : 32'd0;
            m1_dr_valid = (grant[5] == 0) ? s6_dr_valid : 1'b0;
        
            m1_b_resp   = (grant[5] == 0) ? s6_b_resp   : 2'd0;
            m1_b_valid  = (grant[5] == 0) ? s6_b_valid  : 1'b0;
      end
      
      
      4'd7:
      begin
            m1_ar_ready = (grant[6] == 0) ? s7_ar_ready : 1'b0;
            m1_aw_ready = (grant[6] == 0) ? s7_aw_ready : 1'b0;
            m1_dw_ready = (grant[6] == 0) ? s7_dw_ready : 1'b0;
        
            m1_dr_data  = (grant[6] == 0) ? s7_dr_data  : 32'd0;
            m1_dr_valid = (grant[6] == 0) ? s7_dr_valid : 1'b0;
        
            m1_b_resp   = (grant[6] == 0) ? s7_b_resp   : 2'd0;
            m1_b_valid  = (grant[6] == 0) ? s7_b_valid  : 1'b0;
      end
      
      
      4'd8:
      begin
            m1_ar_ready = (grant[7] == 0) ? s8_ar_ready : 1'b0;
            m1_aw_ready = (grant[7] == 0) ? s8_aw_ready : 1'b0;
            m1_dw_ready = (grant[7] == 0) ? s8_dw_ready : 1'b0;
        
            m1_dr_data  = (grant[7] == 0) ? s8_dr_data  : 32'd0;
            m1_dr_valid = (grant[7] == 0) ? s8_dr_valid : 1'b0;
        
            m1_b_resp   = (grant[7] == 0) ? s8_b_resp   : 2'd0;
            m1_b_valid  = (grant[7] == 0) ? s8_b_valid  : 1'b0;
      end
      
      default: begin
               end
 
     endcase
 
////////  master 2 in 
       case(sel_m2)
         
         4'd1: 
         begin
               m2_ar_ready = (grant[0] == 1) ? s1_ar_ready : 1'b0;
               m2_aw_ready = (grant[0] == 1) ? s1_aw_ready : 1'b0;
               m2_dw_ready = (grant[0] == 1) ? s1_dw_ready : 1'b0;
       
               m2_dr_data  = (grant[0] == 1) ? s1_dr_data  : 32'd0;
               m2_dr_valid = (grant[0] == 1) ? s1_dr_valid : 1'b0;
       
               m2_b_resp   = (grant[0] == 1) ? s1_b_resp   : 2'd0;
               m2_b_valid  = (grant[0] == 1) ? s1_b_valid  : 1'b0;
         end
       
       
         4'd2:
         begin
               m2_ar_ready = (grant[1] == 1) ? s2_ar_ready : 1'b0;
               m2_aw_ready = (grant[1] == 1) ? s2_aw_ready : 1'b0;
               m2_dw_ready = (grant[1] == 1) ? s2_dw_ready : 1'b0;
       
               m2_dr_data  = (grant[1] == 1) ? s2_dr_data  : 32'd0;
               m2_dr_valid = (grant[1] == 1) ? s2_dr_valid : 1'b0;
       
               m2_b_resp   = (grant[1] == 1) ? s2_b_resp   : 2'd0;
               m2_b_valid  = (grant[1] == 1) ? s2_b_valid  : 1'b0;
         end
       
       
         4'd3:
         begin
               m2_ar_ready = (grant[2] == 1) ? s3_ar_ready : 1'b0;
               m2_aw_ready = (grant[2] == 1) ? s3_aw_ready : 1'b0;
               m2_dw_ready = (grant[2] == 1) ? s3_dw_ready : 1'b0;
       
               m2_dr_data  = (grant[2] == 1) ? s3_dr_data  : 32'd0;
               m2_dr_valid = (grant[2] == 1) ? s3_dr_valid : 1'b0;
       
               m2_b_resp   = (grant[2] == 1) ? s3_b_resp   : 2'd0;
               m2_b_valid  = (grant[2] == 1) ? s3_b_valid  : 1'b0;
         end
       
       
         4'd4:
         begin
               m2_ar_ready = (grant[3] == 1) ? s4_ar_ready : 1'b0;
               m2_aw_ready = (grant[3] == 1) ? s4_aw_ready : 1'b0;
               m2_dw_ready = (grant[3] == 1) ? s4_dw_ready : 1'b0;
       
               m2_dr_data  = (grant[3] == 1) ? s4_dr_data  : 32'd0;
               m2_dr_valid = (grant[3] == 1) ? s4_dr_valid : 1'b0;
       
               m2_b_resp   = (grant[3] == 1) ? s4_b_resp   : 2'd0;
               m2_b_valid  = (grant[3] == 1) ? s4_b_valid  : 1'b0;
         end
       
       
         4'd5:
         begin
               m2_ar_ready = (grant[4] == 1) ? s5_ar_ready : 1'b0;
               m2_aw_ready = (grant[4] == 1) ? s5_aw_ready : 1'b0;
               m2_dw_ready = (grant[4] == 1) ? s5_dw_ready : 1'b0;
       
               m2_dr_data  = (grant[4] == 1) ? s5_dr_data  : 32'd0;
               m2_dr_valid = (grant[4] == 1) ? s5_dr_valid : 1'b0;
       
               m2_b_resp   = (grant[4] == 1) ? s5_b_resp   : 2'd0;
               m2_b_valid  = (grant[4] == 1) ? s5_b_valid  : 1'b0;
         end
       
       
         4'd6:
         begin
               m2_ar_ready = (grant[5] == 1) ? s6_ar_ready : 1'b0;
               m2_aw_ready = (grant[5] == 1) ? s6_aw_ready : 1'b0;
               m2_dw_ready = (grant[5] == 1) ? s6_dw_ready : 1'b0;
       
               m2_dr_data  = (grant[5] == 1) ? s6_dr_data  : 32'd0;
               m2_dr_valid = (grant[5] == 1) ? s6_dr_valid : 1'b0;
       
               m2_b_resp   = (grant[5] == 1) ? s6_b_resp   : 2'd0;
               m2_b_valid  = (grant[5] == 1) ? s6_b_valid  : 1'b0;
         end
       
       
         4'd7:
         begin
               m2_ar_ready = (grant[6] == 1) ? s7_ar_ready : 1'b0;
               m2_aw_ready = (grant[6] == 1) ? s7_aw_ready : 1'b0;
               m2_dw_ready = (grant[6] == 1) ? s7_dw_ready : 1'b0;
       
               m2_dr_data  = (grant[6] == 1) ? s7_dr_data  : 32'd0;
               m2_dr_valid = (grant[6] == 1) ? s7_dr_valid : 1'b0;
       
               m2_b_resp   = (grant[6] == 1) ? s7_b_resp   : 2'd0;
               m2_b_valid  = (grant[6] == 1) ? s7_b_valid  : 1'b0;
         end
       
       
         4'd8:
         begin
               m2_ar_ready = (grant[7] == 1) ? s8_ar_ready : 1'b0;
               m2_aw_ready = (grant[7] == 1) ? s8_aw_ready : 1'b0;
               m2_dw_ready = (grant[7] == 1) ? s8_dw_ready : 1'b0;
       
               m2_dr_data  = (grant[7] == 1) ? s8_dr_data  : 32'd0;
               m2_dr_valid = (grant[7] == 1) ? s8_dr_valid : 1'b0;
       
               m2_b_resp   = (grant[7] == 1) ? s8_b_resp   : 2'd0;
               m2_b_valid  = (grant[7] == 1) ? s8_b_valid  : 1'b0;
         end
        
        
        default: begin
                 end
       endcase

 


end
    
endmodule
