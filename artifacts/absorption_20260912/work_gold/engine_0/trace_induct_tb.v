`ifndef VERILATOR
module testbench;
  reg [4095:0] vcdfile;
  reg clock;
`else
module testbench(input clock, output reg genclock);
  initial genclock = 1;
`endif
  reg genclock = 1;
  reg [31:0] cycle = 0;
  reg [31:0] PI_s1_ar_addr;
  reg [0:0] PI_s1_aw_valid;
  reg [0:0] PI_rst_2;
  reg [31:0] PI_s1_aw_addr;
  reg [31:0] PI_s1_dw_data;
  reg [0:0] PI_rst_1;
  reg [3:0] PI_s1_dw_strb;
  reg [0:0] PI_clk_2;
  reg [0:0] PI_s1_dr_ready;
  reg [0:0] PI_s1_dw_valid;
  reg [0:0] PI_s1_ar_valid;
  reg [0:0] PI_clk_1;
  reg [0:0] PI_s1_b_ready;
  axi_lite_dot UUT (
    .s1_ar_addr(PI_s1_ar_addr),
    .s1_aw_valid(PI_s1_aw_valid),
    .rst_2(PI_rst_2),
    .s1_aw_addr(PI_s1_aw_addr),
    .s1_dw_data(PI_s1_dw_data),
    .rst_1(PI_rst_1),
    .s1_dw_strb(PI_s1_dw_strb),
    .clk_2(PI_clk_2),
    .s1_dr_ready(PI_s1_dr_ready),
    .s1_dw_valid(PI_s1_dw_valid),
    .s1_ar_valid(PI_s1_ar_valid),
    .clk_1(PI_clk_1),
    .s1_b_ready(PI_s1_b_ready)
  );
`ifndef VERILATOR
  initial begin
    if ($value$plusargs("vcd=%s", vcdfile)) begin
      $dumpfile(vcdfile);
      $dumpvars(0, testbench);
    end
    #5 clock = 0;
    while (genclock) begin
      #5 clock = 0;
      #5 clock = 1;
    end
  end
`endif
  initial begin
`ifndef VERILATOR
    #1;
`endif
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$0/addr_out_read[31:0]#sampled$218  = 32'b11111111111111111111111111111111;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$0/addr_r_comp[0:0]#sampled$228  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$0/addr_r_w[31:0]#sampled$198  = 32'b11111111111111111111111111111111;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$0/addr_w_comp[0:0]#sampled$238  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$0/data_reg[31:0]#sampled$208  = 32'b11111111111111111111111111111111;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$0/data_w_comp[0:0]#sampled$248  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$0/f_p3_pending[0:0]#sampled$178  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$0/s1_b_valid[0:0]#sampled$188  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$assert$axi_lite_dot_gold .\v:251$74_EN#sampled$290  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$assert$axi_lite_dot_gold .\v:267$89_EN#sampled$304  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$logic_or$axi_lite_dot_gold .\v:251$77_Y#sampled$268  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$$logic_or$axi_lite_dot_gold .\v:255$83_Y#sampled$282  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/addr_out_read#sampled$216  = 32'b11111111111111111111111111111111;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/addr_r_comp#sampled$226  = 1'b0;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/addr_r_comp#sampled$310  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/addr_r_w#sampled$196  = 32'b11111111111111111111111111111111;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/addr_w_comp#sampled$236  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/data_reg#sampled$206  = 32'b11111111111111111111111111111111;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/data_w_comp#sampled$246  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/f_p3_pending#sampled$176  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/f_past_valid#sampled$166  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$/s1_b_valid#sampled$186  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:101:sample_data$1'1#sampled$168  = 1'b1;
    // UUT.$auto$clk2fflogic.\cc:87:sample_control_edge$/clk_1#sampled$284  = 1'b1;

    // state 0
    PI_s1_ar_addr = 32'b11111111111111111111111111111111;
    PI_s1_aw_valid = 1'b1;
    PI_rst_2 = 1'b0;
    PI_s1_aw_addr = 32'b11111111111111111111111111111111;
    PI_s1_dw_data = 32'b11111111111111111111111111111111;
    PI_rst_1 = 1'b0;
    PI_s1_dw_strb = 4'b0000;
    PI_clk_2 = 1'b0;
    PI_s1_dr_ready = 1'b1;
    PI_s1_dw_valid = 1'b1;
    PI_s1_ar_valid = 1'b1;
    PI_clk_1 = 1'b1;
    PI_s1_b_ready = 1'b0;
    UUT.fifo_timer_r.free_data = 32'b00000000000000000000000000000000;
    UUT.fifo_timer_r.free_empty = 1'b1;
    UUT.fifo_timer_r.free_full = 1'b0;
    UUT.fifo_timer_w1.free_data = 32'b00000000000000000000000000000000;
    UUT.fifo_timer_w1.free_empty = 1'b0;
    UUT.fifo_timer_w1.free_full = 1'b1;
    UUT.fifo_timer_w2.free_data = 32'b00000000000000000000000000000000;
    UUT.fifo_timer_w2.free_empty = 1'b0;
    UUT.fifo_timer_w2.free_full = 1'b1;
    UUT.fp4_dot_0.free_dot = 32'b00000000000000000000000000000000;
  end
  always @(posedge clock) begin
    // state 1
    if (cycle == 0) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 2
    if (cycle == 1) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 3
    if (cycle == 2) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 4
    if (cycle == 3) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 5
    if (cycle == 4) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 6
    if (cycle == 5) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 7
    if (cycle == 6) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 8
    if (cycle == 7) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 9
    if (cycle == 8) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 10
    if (cycle == 9) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 11
    if (cycle == 10) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 12
    if (cycle == 11) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 13
    if (cycle == 12) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 14
    if (cycle == 13) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 15
    if (cycle == 14) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 16
    if (cycle == 15) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 17
    if (cycle == 16) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 18
    if (cycle == 17) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 19
    if (cycle == 18) begin
      PI_s1_ar_addr <= 32'b11111111111111111111111111111111;
      PI_s1_aw_valid <= 1'b1;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b11111111111111111111111111111111;
      PI_s1_dw_data <= 32'b11111111111111111111111111111111;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b1;
      PI_s1_dw_valid <= 1'b1;
      PI_s1_ar_valid <= 1'b1;
      PI_clk_1 <= 1'b0;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b1;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b1;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b1;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    // state 20
    if (cycle == 19) begin
      PI_s1_ar_addr <= 32'b00000000000000000000000000000000;
      PI_s1_aw_valid <= 1'b0;
      PI_rst_2 <= 1'b0;
      PI_s1_aw_addr <= 32'b00000000000000000000000000000000;
      PI_s1_dw_data <= 32'b00000000000000000000000000000000;
      PI_rst_1 <= 1'b0;
      PI_s1_dw_strb <= 4'b0000;
      PI_clk_2 <= 1'b0;
      PI_s1_dr_ready <= 1'b0;
      PI_s1_dw_valid <= 1'b0;
      PI_s1_ar_valid <= 1'b0;
      PI_clk_1 <= 1'b1;
      PI_s1_b_ready <= 1'b0;
      UUT.fifo_timer_r.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_r.free_empty <= 1'b0;
      UUT.fifo_timer_r.free_full <= 1'b0;
      UUT.fifo_timer_w1.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w1.free_empty <= 1'b0;
      UUT.fifo_timer_w1.free_full <= 1'b0;
      UUT.fifo_timer_w2.free_data <= 32'b00000000000000000000000000000000;
      UUT.fifo_timer_w2.free_empty <= 1'b0;
      UUT.fifo_timer_w2.free_full <= 1'b0;
      UUT.fp4_dot_0.free_dot <= 32'b00000000000000000000000000000000;
    end

    genclock <= cycle < 20;
    cycle <= cycle + 1;
  end
endmodule
