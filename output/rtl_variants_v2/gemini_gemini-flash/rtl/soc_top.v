`timescale 1ns / 1ps

// Nebula digital-track benchmark top level.
//
// Five independent asynchronous master clock domains enter here and nothing
// else does; every other signal the SoC needs is generated internally, so
// the design is self-contained and synthesises without an external
// testbench harness driving pins.
//
//   clk1  core domain    processor, AXI-lite interconnect, DMA, main memory
//   clk2  GPIO domain    slave s2
//   clk3  dot-product    slave s5
//   clk4  timer domain   slave s1
//   clk5  UART domain    slave s4
//
// Each peripheral domain passes through a clk_gate (software-controlled
// enable) and a clk_div_mux (1/2/4/8 divider), so every master clock has at
// least one generated clock derived from it, and every peripheral sits
// across a clock domain crossing from the core.

module soc_top(
    clk1,clk2,clk3,clk4,clk5,
    rst,
    soc_obs
    );


input clk1,clk2,clk3,clk4,clk5;
input rst;

// Observation port.
//
// The five clocks and the reset are the only functional pins; everything
// else the SoC needs it generates internally. That leaves the design with
// nothing observable, and synthesis is entitled to delete all of it -- a
// top level with no outputs optimises down to nothing, which is exactly
// what happened before this port existed (91 cells instead of ~120k).
//
// soc_obs exists purely so the logic has somewhere to be observed from. It
// is a registered fold of the major internal buses, one per subsystem, so
// every block stays in the cone of a real output without adding a pin
// interface back to the top.
output reg [31:0] soc_obs;


//// internally generated replacements for what used to be top-level pins.
//// The SoC drives its own GPIO pads, loops the UART back on itself, and
//// carries its own main memory, so the benchmark is closed at the top.

wire [31:0] gpio_en;
wire [31:0] gpio_write;
wire [31:0] gpio_read;

wire        int_out_timer;
wire        int_out_gpio;
wire        int_out_uart;

wire        trap_in_id;
wire        mret_in_id;

wire        uart_rx;
wire        uart_tx;

wire        mem_en;
wire        mem_read_write;
wire [31:0] mem_addr;
wire [31:0] mem_data_out;
wire [31:0] mem_data_in;
wire        mem_hit;

//// d-cache path
wire [31:0] dc_addr_l1;
wire        dc_addr_valid_l1;
wire        dc_read_write_l1;
wire [255:0]dc_data_out_l1;
wire [255:0]dc_data_in_l1;
wire        dc_data_valid_l1;

wire [31:0] dc_addr_l2;
wire        dc_addr_l2_valid;
wire        dc_read_write_l2;
wire [255:0]dc_data_out_l2_write;
wire [255:0]dc_data_in_l2;
wire        dc_data_valid_l2;

wire        data_valid_d_rb;
wire        hit_d_rb;
wire [31:0] rb_data_out;
wire        rb_data_valid;

wire [2:0]  int_pending;
wire [1:0]  int_id;

reg [31:0]clk_config_reg,clk_en_reg ;


wire [31:0] pc_if_id_pipe_debug;
wire [31:0] alu_out_mem_stage_debug;
wire [31:0] wb_data_debug;
wire [4:0]  wb_addr_debug;

wire        addr_valid_m_axi;
wire        read_write_axi;
wire [31:0] addr_m_axi;
wire [31:0] data_out_m_axi;
wire [31:0] data_in_m_axi;


// d-cache side of master port 1 (see the MMIO mux further down)
wire [31:0] c1_ar_addr, c1_aw_addr, c1_dw_data;
wire        c1_ar_valid, c1_aw_valid, c1_dr_ready, c1_dw_valid, c1_b_ready;
wire        c1_ar_ready, c1_aw_ready, c1_dr_valid, c1_dw_ready, c1_b_valid;

wire [31:0] m1_ar_addr;
wire        m1_ar_valid;
wire        m1_ar_ready;

wire [31:0] m1_aw_addr;
wire        m1_aw_valid;
wire        m1_aw_ready;

wire [31:0] m1_dr_data;
wire        m1_dr_valid;
wire        m1_dr_ready;

wire [31:0] m1_dw_data;
wire        m1_dw_valid;
wire        m1_dw_ready;

wire        m1_b_ready;
wire        m1_b_valid;
wire [1:0]  m1_b_resp;


wire [31:0] m2_ar_addr;
wire        m2_ar_valid;
wire        m2_ar_ready;

wire [31:0] m2_aw_addr;
wire        m2_aw_valid;
wire        m2_aw_ready;

wire [31:0] m2_dr_data;
wire        m2_dr_valid;
wire        m2_dr_ready;

wire [31:0] m2_dw_data;
wire        m2_dw_valid;
wire        m2_dw_ready;

wire        m2_b_ready;
wire        m2_b_valid;
wire [1:0]  m2_b_resp;


wire [31:0] s1_ar_addr;
wire        s1_ar_valid;
wire        s1_ar_ready;

wire [31:0] s1_aw_addr;
wire        s1_aw_valid;
wire        s1_aw_ready;

wire [31:0] s1_dr_data;
wire        s1_dr_valid;
wire        s1_dr_ready;
wire [1:0]  s1_dr_resp_local;

wire [31:0] s1_dw_data;
wire        s1_dw_valid;
wire        s1_dw_ready;

wire        s1_b_ready;
wire        s1_b_valid;
wire [1:0]  s1_b_resp;


wire [31:0] s2_ar_addr;
wire        s2_ar_valid;
wire        s2_ar_ready;

wire [31:0] s2_aw_addr;
wire        s2_aw_valid;
wire        s2_aw_ready;

wire [31:0] s2_dr_data;
wire        s2_dr_valid;
wire        s2_dr_ready;
wire [1:0]  s2_dr_resp_local;

wire [31:0] s2_dw_data;
wire        s2_dw_valid;
wire        s2_dw_ready;

wire        s2_b_ready;
wire        s2_b_valid;
wire [1:0]  s2_b_resp;


wire [31:0] s3_ar_addr;
wire        s3_ar_valid;
wire        s3_ar_ready;

wire [31:0] s3_aw_addr;
wire        s3_aw_valid;
wire        s3_aw_ready;

wire [31:0] s3_dr_data;
wire        s3_dr_valid;
wire        s3_dr_ready;
wire [1:0]  s3_dr_resp_local;

wire [31:0] s3_dw_data;
wire        s3_dw_valid;
wire        s3_dw_ready;

wire        s3_b_ready;
wire        s3_b_valid;
wire [1:0]  s3_b_resp;


wire [31:0] s4_ar_addr;
wire        s4_ar_valid;
wire        s4_ar_ready;

wire [31:0] s4_aw_addr;
wire        s4_aw_valid;
wire        s4_aw_ready;

wire [31:0] s4_dr_data;
wire        s4_dr_valid;
wire        s4_dr_ready;
wire [1:0]  s4_dr_resp_local;

wire [31:0] s4_dw_data;
wire        s4_dw_valid;
wire        s4_dw_ready;

wire        s4_b_ready;
wire        s4_b_valid;
wire [1:0]  s4_b_resp;


wire [31:0] s5_ar_addr;
wire        s5_ar_valid;
wire        s5_ar_ready;

wire [31:0] s5_aw_addr;
wire        s5_aw_valid;
wire        s5_aw_ready;

wire [31:0] s5_dr_data;
wire        s5_dr_valid;
wire        s5_dr_ready;
wire [1:0]  s5_dr_resp_local;

wire [31:0] s5_dw_data;
wire        s5_dw_valid;
wire        s5_dw_ready;

wire        s5_b_ready;
wire        s5_b_valid;
wire [1:0]  s5_b_resp;


wire [31:0] s6_ar_addr;
wire        s6_ar_valid;
wire        s6_ar_ready;

wire [31:0] s6_aw_addr;
wire        s6_aw_valid;
wire        s6_aw_ready;

wire [31:0] s6_dr_data;
wire        s6_dr_valid;
wire        s6_dr_ready;

wire [31:0] s6_dw_data;
wire        s6_dw_valid;
wire        s6_dw_ready;

wire        s6_b_ready;
wire        s6_b_valid;
wire [1:0]  s6_b_resp;


wire [31:0] s7_ar_addr;
wire        s7_ar_valid;
wire        s7_ar_ready;

wire [31:0] s7_aw_addr;
wire        s7_aw_valid;
wire        s7_aw_ready;

wire [31:0] s7_dr_data;
wire        s7_dr_valid;
wire        s7_dr_ready;

wire [31:0] s7_dw_data;
wire        s7_dw_valid;
wire        s7_dw_ready;

wire        s7_b_ready;
wire        s7_b_valid;
wire [1:0]  s7_b_resp;


wire [31:0] s8_ar_addr;
wire        s8_ar_valid;
wire        s8_ar_ready;

wire [31:0] s8_aw_addr;
wire        s8_aw_valid;
wire        s8_aw_ready;

wire [31:0] s8_dr_data;
wire        s8_dr_valid;
wire        s8_dr_ready;
wire        s8_dr_last;

wire [31:0] s8_dw_data;
wire        s8_dw_valid;
wire        s8_dw_ready;

wire        s8_b_ready;
wire        s8_b_valid;
wire [1:0]  s8_b_resp;


wire clk_s1,clk_s2,clk_s3,clk_s4,clk_s5,clk_s8;
wire clk_s1_gate,clk_s2_gate,clk_s4_gate,clk_s5_gate;


processor_top processor_0(
    clk1,
    rst,
    trap_in_id,
    mret_in_id,
    pc_if_id_pipe_debug,
    alu_out_mem_stage_debug,
    wb_data_debug,
    wb_addr_debug,
    addr_valid_m_axi,
    read_write_axi,
    addr_m_axi,
    data_out_m_axi,
    data_in_m_axi,
    data_valid_d_rb
);


// Processor data side now goes through the cache hierarchy instead of
// straight onto the bus:
//
//   processor_top -> read_buffer_d_cache -> l1_d_cache_8kb
//                 -> l1_cache_axi_master -> master port m1 -> interconnect
//
// The read buffer serves word accesses that hit its held block; a miss with
// a dirty block writes that block back into the L1 first. The L1 in turn
// talks to main memory as an AXI-lite master, 8 beats per 256-bit block.

// The CPU is byte-addressed; the cache hierarchy below is word-addressed
// (read_buffer_d_cache splits addr into a 29-bit tag + 3-bit word offset, and
// l1_d_cache_8kb's addr[2:0] indexes the eight words of a 256-bit block).
// Handing it the raw byte address made every consecutive word land four blocks
// apart and put addr[1:0] -- always 0 -- into the offset, so only word 0 of a
// block was ever reachable. l1_cache_axi_master converts back to a byte
// address on the AXI side.
// ---------------------------------------------------------------------------
// Uncached MMIO path.
//
// Every CPU data access used to be handed to the d-cache, peripheral accesses
// included. That is wrong in both directions: a write to a control register
// only dirtied a cache line and never reached the peripheral, and a read
// missed and pulled an eight-beat BLOCK through the peripheral's address
// space, returning whichever register happened to sit at word 0 of it. The
// timer never started, the DMA never started, and the values the CPU read
// back were the cache's own copies.
//
// So the address is decoded first. 0xf000_xxxx is device space and goes
// straight out on AXI through its own master, never through the cache; the two
// clock-control registers inside that space live in this file and are answered
// here without a bus transaction at all (they decode to no slave, so sending
// them to the interconnect would land them in main memory). Everything else is
// cacheable and goes to the read buffer as before.
//
// The CPU is single-outstanding -- it holds addr_valid_m_axi and stalls until
// data_valid comes back -- so the cache master and the MMIO master can never
// both have a transaction in flight, and the m1 port below is a plain mux
// rather than an arbiter.

wire is_dev;      // 0xf000_0000 .. 0xf000_ffff: peripheral space
wire is_clkcfg;   // 0xf000_fff0 / 0xf000_fff4: local clock control
wire is_mmio;     // device space that actually goes out on the bus

assign is_dev    = (addr_m_axi[31:16] == 16'hf000);
assign is_clkcfg = is_dev && (addr_m_axi[15:4] == 12'hfff);
assign is_mmio   = is_dev && !is_clkcfg;

// A clock-control access completes in one cycle, the cycle after it is seen.
reg  clkcfg_done;
always@(posedge clk1)
begin
     if(rst) clkcfg_done <= 1'b0;
     else    clkcfg_done <= addr_valid_m_axi && is_clkcfg && !clkcfg_done;
end

wire [31:0] clkcfg_rdata;
assign clkcfg_rdata = addr_m_axi[2] ? clk_config_reg : clk_en_reg;

wire [31:0] dc_cpu_addr;
assign dc_cpu_addr = {2'b00, addr_m_axi[31:2]};

read_buffer_d_cache d_read_buffer_0(
    clk1,
    rst,

    dc_cpu_addr,
    addr_valid_m_axi && !is_dev,
    read_write_axi,
    data_out_m_axi,
    rb_data_out,
    rb_data_valid,
    hit_d_rb,

    dc_addr_l1,
    dc_addr_valid_l1,
    dc_read_write_l1,
    dc_data_out_l1,
    dc_data_in_l1,
    dc_data_valid_l1
);


l1_d_cache_8kb d_cache_0(
    clk1,
    rst,

    dc_addr_l1,
    dc_addr_valid_l1,
    dc_read_write_l1,
    dc_data_in_l1,
    dc_data_out_l1,
    dc_data_valid_l1,

    dc_addr_l2,
    dc_addr_l2_valid,
    dc_read_write_l2,
    dc_data_out_l2_write,
    dc_data_in_l2,
    dc_data_valid_l2
);


l1_cache_axi_master d_cache_axi_0(
    clk1,
    rst,

    dc_addr_l2,
    dc_addr_l2_valid,
    dc_read_write_l2,
    dc_data_out_l2_write,
    dc_data_in_l2,
    dc_data_valid_l2,

    c1_ar_addr,
    c1_ar_valid,
    c1_ar_ready,

    c1_aw_addr,
    c1_aw_valid,
    c1_aw_ready,

    m1_dr_data,
    c1_dr_valid,
    c1_dr_ready,

    c1_dw_data,
    c1_dw_valid,
    c1_dw_ready,

    c1_b_ready,
    c1_b_valid,
    m1_b_resp
);


//// ---------------------------------------------------------------------
//// MMIO master, and the mux that shares master port 1 with the d-cache.
////
//// mmio_sel is a pure address decode, not qualified by addr_valid, so it
//// stays stable for the whole of a transaction: the CPU holds addr_m_axi
//// until the access completes. Only one of the two masters can be active at
//// a time (see the note above), so a mux is enough -- no arbitration.

wire [31:0] p1_ar_addr, p1_aw_addr, p1_dw_data;
wire        p1_ar_valid, p1_aw_valid, p1_dr_ready, p1_dw_valid, p1_b_ready;
wire [3:0]  p1_dw_strb;
wire [31:0] mmio_rdata;
wire        mmio_done;

wire mmio_sel;
assign mmio_sel = is_mmio;

// axi_lite_master launches on a RISING edge of its addr_valid, but the CPU
// holds addr_valid_m_axi high from one memory instruction straight into the
// next -- a store followed by a load never gave it an edge, and the load hung
// the pipeline for ever. mmio_busy turns the CPU's level request into exactly
// one pulse per access: raised when the request is issued, dropped when the
// master reports done, and a new request is held off for the done cycle
// itself so the completing access cannot re-issue itself.
reg  mmio_busy;
wire mmio_req;

assign mmio_req = addr_valid_m_axi && is_mmio && !mmio_busy && !mmio_done;

always@(posedge clk1)
begin
     if(rst)           mmio_busy <= 1'b0;
     else if(mmio_done)mmio_busy <= 1'b0;
     else if(mmio_req) mmio_busy <= 1'b1;
end

axi_lite_master mmio_master_0(
    clk1,
    rst,

    addr_m_axi,
    mmio_req,
    data_out_m_axi,
    read_write_axi,
    mmio_rdata,
    mmio_done,

    p1_ar_addr, p1_ar_valid, m1_ar_ready &  mmio_sel,
    p1_aw_addr, p1_aw_valid, m1_aw_ready &  mmio_sel,
    m1_dr_data, m1_dr_valid &  mmio_sel, p1_dr_ready, 2'b00,
    p1_dw_data, p1_dw_valid, m1_dw_ready &  mmio_sel, p1_dw_strb,
    p1_b_ready, m1_b_valid  &  mmio_sel, m1_b_resp
);

assign c1_ar_ready = m1_ar_ready & ~mmio_sel;
assign c1_aw_ready = m1_aw_ready & ~mmio_sel;
assign c1_dr_valid = m1_dr_valid & ~mmio_sel;
assign c1_dw_ready = m1_dw_ready & ~mmio_sel;
assign c1_b_valid  = m1_b_valid  & ~mmio_sel;

assign m1_ar_addr  = mmio_sel ? p1_ar_addr  : c1_ar_addr;
assign m1_ar_valid = mmio_sel ? p1_ar_valid : c1_ar_valid;
assign m1_aw_addr  = mmio_sel ? p1_aw_addr  : c1_aw_addr;
assign m1_aw_valid = mmio_sel ? p1_aw_valid : c1_aw_valid;
assign m1_dr_ready = mmio_sel ? p1_dr_ready : c1_dr_ready;
assign m1_dw_data  = mmio_sel ? p1_dw_data  : c1_dw_data;
assign m1_dw_valid = mmio_sel ? p1_dw_valid : c1_dw_valid;
assign m1_b_ready  = mmio_sel ? p1_b_ready  : c1_b_ready;


//// What the CPU sees coming back: the peripheral bus, the local clock
//// registers, or the cache -- whichever one the address was routed to.
assign data_in_m_axi   = is_clkcfg ? clkcfg_rdata :
                         is_mmio   ? mmio_rdata   : rb_data_out;
assign data_valid_d_rb = is_clkcfg ? clkcfg_done  :
                         is_mmio   ? mmio_done    : rb_data_valid;


axi_interconnect_2m_8s interconnect_0(
    clk1,
    rst,

    m1_ar_addr,
    m1_ar_valid,
    m1_ar_ready,

    m1_aw_addr,
    m1_aw_valid,
    m1_aw_ready,

    m1_dr_data,
    m1_dr_valid,
    m1_dr_ready,

    m1_dw_data,
    m1_dw_valid,
    m1_dw_ready,

    m1_b_ready,
    m1_b_valid,
    m1_b_resp,


    m2_ar_addr,
    m2_ar_valid,
    m2_ar_ready,

    m2_aw_addr,
    m2_aw_valid,
    m2_aw_ready,

    m2_dr_data,
    m2_dr_valid,
    m2_dr_ready,

    m2_dw_data,
    m2_dw_valid,
    m2_dw_ready,

    m2_b_ready,
    m2_b_valid,
    m2_b_resp,


    s1_ar_addr,
    s1_ar_valid,
    s1_ar_ready,

    s1_aw_addr,
    s1_aw_valid,
    s1_aw_ready,

    s1_dr_data,
    s1_dr_valid,
    s1_dr_ready,

    s1_dw_data,
    s1_dw_valid,
    s1_dw_ready,

    s1_b_ready,
    s1_b_valid,
    s1_b_resp,


    s2_ar_addr,
    s2_ar_valid,
    s2_ar_ready,

    s2_aw_addr,
    s2_aw_valid,
    s2_aw_ready,

    s2_dr_data,
    s2_dr_valid,
    s2_dr_ready,

    s2_dw_data,
    s2_dw_valid,
    s2_dw_ready,

    s2_b_ready,
    s2_b_valid,
    s2_b_resp,


    s3_ar_addr,
    s3_ar_valid,
    s3_ar_ready,

    s3_aw_addr,
    s3_aw_valid,
    s3_aw_ready,

    s3_dr_data,
    s3_dr_valid,
    s3_dr_ready,

    s3_dw_data,
    s3_dw_valid,
    s3_dw_ready,

    s3_b_ready,
    s3_b_valid,
    s3_b_resp,


    s4_ar_addr,
    s4_ar_valid,
    s4_ar_ready,

    s4_aw_addr,
    s4_aw_valid,
    s4_aw_ready,

    s4_dr_data,
    s4_dr_valid,
    s4_dr_ready,

    s4_dw_data,
    s4_dw_valid,
    s4_dw_ready,

    s4_b_ready,
    s4_b_valid,
    s4_b_resp,


    s5_ar_addr,
    s5_ar_valid,
    s5_ar_ready,

    s5_aw_addr,
    s5_aw_valid,
    s5_aw_ready,

    s5_dr_data,
    s5_dr_valid,
    s5_dr_ready,

    s5_dw_data,
    s5_dw_valid,
    s5_dw_ready,

    s5_b_ready,
    s5_b_valid,
    s5_b_resp,


    s6_ar_addr,
    s6_ar_valid,
    s6_ar_ready,

    s6_aw_addr,
    s6_aw_valid,
    s6_aw_ready,

    s6_dr_data,
    s6_dr_valid,
    s6_dr_ready,

    s6_dw_data,
    s6_dw_valid,
    s6_dw_ready,

    s6_b_ready,
    s6_b_valid,
    s6_b_resp,


    s7_ar_addr,
    s7_ar_valid,
    s7_ar_ready,

    s7_aw_addr,
    s7_aw_valid,
    s7_aw_ready,

    s7_dr_data,
    s7_dr_valid,
    s7_dr_ready,

    s7_dw_data,
    s7_dw_valid,
    s7_dw_ready,

    s7_b_ready,
    s7_b_valid,
    s7_b_resp,


    s8_ar_addr,
    s8_ar_valid,
    s8_ar_ready,

    s8_aw_addr,
    s8_aw_valid,
    s8_aw_ready,

    s8_dr_data,
    s8_dr_valid,
    s8_dr_ready,

    s8_dw_data,
    s8_dw_valid,
    s8_dw_ready,

    s8_b_ready,
    s8_b_valid,
    s8_b_resp
);



axi_lite_timer timer_0(
    clk1,
    rst,
    clk_s1,
    rst,
    int_out_timer,

    s1_ar_addr,
    s1_ar_valid,
    s1_ar_ready,

    s1_aw_addr,
    s1_aw_valid,
    s1_aw_ready,

    s1_dr_data,
    s1_dr_valid,
    s1_dr_ready,
    s1_dr_resp_local,

    s1_dw_data,
    s1_dw_valid,
    s1_dw_ready,
    4'b1111,

    s1_b_ready,
    s1_b_valid,
    s1_b_resp
);



axi_lite_gpio gpio_0(
    clk1,
    rst,
    clk_s2,
    rst,

    int_out_gpio,
    gpio_en,
    gpio_write,
    gpio_read,

    s2_ar_addr,
    s2_ar_valid,
    s2_ar_ready,

    s2_aw_addr,
    s2_aw_valid,
    s2_aw_ready,

    s2_dr_data,
    s2_dr_valid,
    s2_dr_ready,
    s2_dr_resp_local,

    s2_dw_data,
    s2_dw_valid,
    s2_dw_ready,
    4'b1111,

    s2_b_ready,
    s2_b_valid,
    s2_b_resp
);



axi_lite_dma_config dma_config_0(
    clk1,
    rst,

    clk_s3,
    rst,

    s3_ar_addr,
    s3_ar_valid,
    s3_ar_ready,

    s3_aw_addr,
    s3_aw_valid,
    s3_aw_ready,

    s3_dr_data,
    s3_dr_valid,
    s3_dr_ready,
    s3_dr_resp_local,

    s3_dw_data,
    s3_dw_valid,
    s3_dw_ready,
    4'b1111,

    s3_b_ready,
    s3_b_valid,
    s3_b_resp,

    m2_ar_addr,
    m2_ar_valid,
    m2_ar_ready,

    m2_aw_addr,
    m2_aw_valid,
    m2_aw_ready,

    m2_dr_data,
    m2_dr_valid,
    m2_dr_ready,

    m2_dw_data,
    m2_dw_valid,
    m2_dw_ready,

    m2_b_ready,
    m2_b_valid,
    m2_b_resp
);



axi_lite_dot dot_0(
    clk1,
    rst,

    clk_s5,
    rst,

    s5_ar_addr,
    s5_ar_valid,
    s5_ar_ready,

    s5_aw_addr,
    s5_aw_valid,
    s5_aw_ready,

    s5_dr_data,
    s5_dr_valid,
    s5_dr_ready,
    s5_dr_resp_local,

    s5_dw_data,
    s5_dw_valid,
    s5_dw_ready,
    4'b1111,

    s5_b_ready,
    s5_b_valid,
    s5_b_resp
);



mem_axi_slave memory_axi_0(
    clk_s8,
    rst,

    mem_en,
    mem_read_write,
    mem_addr,
    mem_data_out,
    mem_data_in,
    mem_hit,

    s8_ar_addr,
    s8_ar_valid,
    s8_ar_ready,
    8'd0,
    3'b010,
    2'b01,

    s8_aw_addr,
    s8_aw_valid,
    s8_aw_ready,
    8'd0,
    3'b010,
    2'b01,

    s8_dr_data,
    s8_dr_valid,
    s8_dr_ready,
    s8_dr_last,

    s8_dw_data,
    s8_dw_valid,
    s8_dw_ready,
    4'b1111,
    1'b1,

    s8_b_ready,
    s8_b_valid,
    s8_b_resp
);



axi_lite_uart uart_0(
    clk1,
    rst,

    clk_s4,
    rst,

    int_out_uart,
    uart_rx,
    uart_tx,

    s4_ar_addr,
    s4_ar_valid,
    s4_ar_ready,

    s4_aw_addr,
    s4_aw_valid,
    s4_aw_ready,

    s4_dr_data,
    s4_dr_valid,
    s4_dr_ready,
    s4_dr_resp_local,

    s4_dw_data,
    s4_dw_valid,
    s4_dw_ready,
    4'b1111,

    s4_b_ready,
    s4_b_valid,
    s4_b_resp
);


assign s6_ar_ready = 1'b0;
assign s6_aw_ready = 1'b0;
assign s6_dr_data  = 32'd0;
assign s6_dr_valid = 1'b0;
assign s6_dw_ready = 1'b0;
assign s6_b_valid  = 1'b0;
assign s6_b_resp   = 2'b00;


assign s7_ar_ready = 1'b0;
assign s7_aw_ready = 1'b0;
assign s7_dr_data  = 32'd0;
assign s7_dr_valid = 1'b0;
assign s7_dw_ready = 1'b0;
assign s7_b_valid  = 1'b0;
assign s7_b_resp   = 2'b00;



always@(posedge clk1)
begin
     if(rst)
     begin
          // Clocks come up RUNNING and software gates them off; they must not
          // reset to 0. The main memory sits behind memory_clk_gate, so a
          // zero reset value left clk_s8 dead, mem_axi_slave never completed,
          // and the first load through the d-cache hung the core forever.
          // Bits [5:0] are the six clock enables; [10:8] is the interrupt
          // mask, which stays masked at reset as usual.
          clk_en_reg <=  32'h0000_003f;
          clk_config_reg <= 32'd0;
     end

     else if(addr_valid_m_axi && read_write_axi)
     begin
      case(addr_m_axi)
         ///  clk_en_reg:     [5] uart | [4] mem | [3] dma | [2] dot | [1] gpio | [0] timer
         32'hf000_fff0: clk_en_reg <=  data_out_m_axi;
         ///  clk_config_reg: [7:6] uart | [5:4] dot | [3:2] gpio | [1:0] timer
         32'hf000_fff4: clk_config_reg <=  data_out_m_axi;
         default: ;  // not a clock control register
      endcase
     end

end

/// timer -- domain 4
clk_gate    timer_clk_gate(clk4,clk_en_reg[0],clk_s1_gate);
clk_div_mux timer_clk_div(clk_s1_gate,rst,clk_config_reg[1:0],clk_s1);

//// gpio -- domain 2
clk_gate    gpio_clk_gate(clk2,clk_en_reg[1],clk_s2_gate);
clk_div_mux gpio_clk_div(clk_s2_gate,rst,clk_config_reg[3:2],clk_s2);

///  dot -- domain 3
clk_gate    dot_clk_gate(clk3,clk_en_reg[2],clk_s5_gate);
clk_div_mux dot_clk_div(clk_s5_gate,rst,clk_config_reg[5:4],clk_s5);

//// uart -- domain 5
clk_gate    uart_clk_gate(clk5,clk_en_reg[5],clk_s4_gate);
clk_div_mux uart_clk_div(clk_s4_gate,rst,clk_config_reg[7:6],clk_s4);

/// dma gate -- core domain
clk_gate dma_clk_gate(clk1,clk_en_reg[3],clk_s3);

//// mem gate -- core domain
clk_gate memory_clk_gate(clk1,clk_en_reg[4],clk_s8);


//// Pad and serial loopbacks. A GPIO pin reads back what the SoC drives on
//// it while its output enable is set, and the UART transmit line feeds its
//// own receiver, so both peripherals exercise their full datapath with no
//// top-level pins.
assign gpio_read = gpio_write & gpio_en;
assign uart_rx   = uart_tx;

//// Peripheral interrupts are collected by the interrupt controller, which
//// also carries the CDC synchronisers -- timer, GPIO and UART each run on
//// their own asynchronous clock. Its request becomes the core's trap input.
//// mret is tied off: nothing in this benchmark returns from a trap, and the
//// CSR file already treats it as a level input.
interrupt_control_unit int_ctrl_0(
    clk1,
    rst,
    {int_out_uart, int_out_gpio, int_out_timer},
    clk_en_reg[10:8],      //// per-source interrupt enable
    3'b000,                //// no software acknowledge path yet
    int_pending,
    int_id,
    trap_in_id
);

assign mret_in_id = 1'b0;


//// On-chip main memory behind the AXI slave. mem_axi_slave raises mem_en
//// until hit comes back, and the array has one cycle of read latency, so
//// hit is just mem_en delayed by a cycle.
reg mem_hit_r;
always@(posedge clk_s8)
begin
     if(rst) mem_hit_r <= 1'b0;
     else    mem_hit_r <= mem_en && !mem_hit_r;
end
assign mem_hit = mem_hit_r;

dmem main_memory_0(
    clk_s8,
    mem_en & mem_read_write,
    mem_addr,
    mem_data_in,
    mem_data_out
);




always@(posedge clk1)
begin
     if(rst) soc_obs <= 32'd0;
     else    soc_obs <= pc_if_id_pipe_debug ^ alu_out_mem_stage_debug ^
                        wb_data_debug ^ {27'd0, wb_addr_debug} ^
                        gpio_write ^ gpio_en ^
                        mem_addr ^ mem_data_in ^
                        dc_addr_l1 ^ dc_addr_l2 ^
                        dc_data_out_l1[31:0] ^ dc_data_out_l2_write[31:0] ^
                        s1_dr_data ^ s2_dr_data ^ s3_dr_data ^
                        s4_dr_data ^ s5_dr_data ^ s8_dr_data ^
                        m1_ar_addr ^ m1_aw_addr ^ m1_dw_data ^
                        m2_ar_addr ^ m2_aw_addr ^ m2_dw_data ^
                        {24'd0, uart_tx, trap_in_id, int_pending, int_id, mem_hit};
end


// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     // The interconnect has no write-strobe port -- it is
                     // word-granular -- so the MMIO master's strobes go nowhere.
                     p1_dw_strb,
                     clk_config_reg[31:8], clk_en_reg[31:11], clk_en_reg[7:6],
                     hit_d_rb,
                     s1_dr_resp_local, s2_dr_resp_local, s3_dr_resp_local, s4_dr_resp_local,
                     s5_dr_resp_local, s6_ar_addr, s6_ar_valid, s6_aw_addr, s6_aw_valid, s6_dr_ready,
                     s6_dw_data, s6_dw_valid, s6_b_ready, s7_ar_addr, s7_ar_valid, s7_aw_addr,
                     s7_aw_valid, s7_dr_ready, s7_dw_data, s7_dw_valid, s7_b_ready, s8_dr_last,
                     1'b0};

endmodule
