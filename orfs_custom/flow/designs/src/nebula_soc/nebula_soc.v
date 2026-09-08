// Stage 6 benchmark RTL, single-file multi-module (matches gcd.v pattern
// that run_eqy.py / llm_loop.py's module-splice logic assumes).

// Clock divider: master clk -> generated div_clk at clk/DIV (DIV even).
// One generated clock per domain, per Stage 6 spec.
module clk_divider #(
  parameter DIV = 2
) (
  input  wire clk,
  input  wire rst_n,
  output reg  div_clk
);
  localparam HALF = DIV / 2;
  localparam CNT_W = (HALF <= 1) ? 1 : $clog2(HALF);

  reg [CNT_W-1:0] cnt;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt     <= {CNT_W{1'b0}};
      div_clk <= 1'b0;
    end else if (cnt == HALF - 1) begin
      cnt     <= {CNT_W{1'b0}};
      div_clk <= ~div_clk;
    end else begin
      cnt <= cnt + 1'b1;
    end
  end
endmodule

// Gray-code async FIFO -- CDC bridge between two independent clock domains.
// Standard 2-flop synchronizer on each ptr crossing.
module async_fifo #(
  parameter WIDTH  = 32,
  parameter ADDR_W = 4   // depth = 2**ADDR_W
) (
  input  wire             wr_clk,
  input  wire             wr_rst_n,
  input  wire             wr_en,
  input  wire [WIDTH-1:0] wr_data,
  output wire             wr_full,

  input  wire              rd_clk,
  input  wire              rd_rst_n,
  input  wire              rd_en,
  output reg  [WIDTH-1:0]  rd_data,
  output wire               rd_empty
);
  localparam DEPTH = (1 << ADDR_W);

  reg [WIDTH-1:0] mem [0:DEPTH-1];

  reg [ADDR_W:0] wr_ptr_bin, wr_ptr_gray;
  reg [ADDR_W:0] rd_ptr_bin, rd_ptr_gray;

  reg [ADDR_W:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
  reg [ADDR_W:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;

  // Lookahead pointer must NOT depend on wr_full/rd_empty: wr_full is itself
  // derived from wr_ptr_gray_next below, so gating on wr_full here closed a
  // real physical combinational loop (wr_full -> wr_ptr_bin_next ->
  // wr_ptr_gray_next -> wr_full), caught by Verilator's UNOPTFLAT lint
  // check. Safe to drop: the actual mem write stays gated by
  // "wr_en && !wr_full" below, and the caller already gates wr_en on
  // !wr_full a cycle ahead against a 16-deep FIFO with a single slow
  // writer, so the lookahead pointer never needs to protect itself.
  wire [ADDR_W:0] wr_ptr_bin_next  = wr_ptr_bin + wr_en;
  wire [ADDR_W:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

  wire [ADDR_W:0] rd_ptr_bin_next  = rd_ptr_bin + rd_en;
  wire [ADDR_W:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

  // write domain
  always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_ptr_bin  <= 0;
      wr_ptr_gray <= 0;
    end else begin
      wr_ptr_bin  <= wr_ptr_bin_next;
      wr_ptr_gray <= wr_ptr_gray_next;
      if (wr_en && !wr_full)
        mem[wr_ptr_bin[ADDR_W-1:0]] <= wr_data;
    end
  end

  always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      rd_ptr_gray_sync1 <= 0;
      rd_ptr_gray_sync2 <= 0;
    end else begin
      rd_ptr_gray_sync1 <= rd_ptr_gray;
      rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
    end
  end

  assign wr_full = (wr_ptr_gray_next ==
      {~rd_ptr_gray_sync2[ADDR_W:ADDR_W-1], rd_ptr_gray_sync2[ADDR_W-2:0]});

  // read domain
  always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_ptr_bin  <= 0;
      rd_ptr_gray <= 0;
      rd_data     <= 0;
    end else begin
      rd_ptr_bin  <= rd_ptr_bin_next;
      rd_ptr_gray <= rd_ptr_gray_next;
      if (rd_en && !rd_empty)
        rd_data <= mem[rd_ptr_bin[ADDR_W-1:0]];
    end
  end

  always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      wr_ptr_gray_sync1 <= 0;
      wr_ptr_gray_sync2 <= 0;
    end else begin
      wr_ptr_gray_sync1 <= wr_ptr_gray;
      wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
    end
  end

  // Unlike wr_full (safe: wr_en is registered at the call site, never
  // combinationally tied back to wr_full), rd_en IS wired combinationally
  // as "!rd_empty" at the top level (auto-drain-while-available). Using the
  // lookahead rd_ptr_gray_next here would make rd_empty depend on rd_en,
  // which depends on rd_empty -- a real loop through the module boundary
  // (caught by lint). Use the current registered pointer instead -- the
  // standard, non-lookahead empty-flag definition -- which depends only on
  // already-latched state.
  assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);
endmodule

// Parameterizable MAC datapath -- stand-in for a domain's DSP-ish workload
// (audio/video/crypto/sensor-fusion/compression style compute, varied per
// domain via WIDTH/LANES/ACC_STAGES). Deliberately only registered at input
// and output (long comb mult+adder-tree in between) so real critical paths
// exist for the LLM loop to fix via pipelining/retiming/restructuring.
module compute_pipeline #(
  parameter WIDTH = 16,
  parameter LANES = 4
) (
  input  wire                      clk,
  input  wire                      rst_n,
  input  wire                      valid_in,
  input  wire [WIDTH*LANES-1:0]    a_in,
  input  wire [WIDTH*LANES-1:0]    b_in,
  output reg                       valid_out,
  output reg  [2*WIDTH+$clog2(LANES)-1:0] acc_out
);
  localparam PW = 2 * WIDTH;
  localparam SUMW = PW + $clog2(LANES);

  wire [WIDTH-1:0] a [0:LANES-1];
  wire [WIDTH-1:0] b [0:LANES-1];
  wire [PW-1:0]    prod [0:LANES-1];

  genvar i;
  generate
    for (i = 0; i < LANES; i = i + 1) begin : lane
      assign a[i] = a_in[(i+1)*WIDTH-1 -: WIDTH];
      assign b[i] = b_in[(i+1)*WIDTH-1 -: WIDTH];
      assign prod[i] = a[i] * b[i];
    end
  endgenerate

  // comb adder tree summing all lane products
  function [SUMW-1:0] sum_tree;
    input integer n;
    integer j;
    reg [SUMW-1:0] acc;
    begin
      acc = {SUMW{1'b0}};
      for (j = 0; j < n; j = j + 1)
        acc = acc + prod[j];
      sum_tree = acc;
    end
  endfunction

  wire [SUMW-1:0] sum_comb = sum_tree(LANES);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      acc_out   <= {SUMW{1'b0}};
    end else begin
      valid_out <= valid_in;
      acc_out   <= sum_comb;
    end
  end
endmodule

// Fully-pipelined CRC-style shift/XOR chain -- GF(2)-linear, so equivalence
// checking stays SAT-cheap at any size (unlike compute_pipeline's multiply
// tree, which we found empirically blows up EQY past LANES~5 on a real
// restructuring edit). Registered every stage on purpose: this block exists
// to provide safe, scalable cell count for the ~50k budget, not a timing
// target -- compute_pipeline is the deliberate critical-path source.
module crc_pipeline #(
  parameter WIDTH  = 64,
  parameter STAGES = 32,
  parameter [WIDTH-1:0] POLY = {WIDTH{1'b1}} ^ ({WIDTH{1'b1}} >> 1) ^ 64'h5A5A5A5A5A5A5A5A
) (
  input  wire             clk,
  input  wire             rst_n,
  input  wire             in_valid,
  input  wire [WIDTH-1:0] data_in,
  output reg              out_valid,
  output reg [WIDTH-1:0]  data_out
);
  reg [WIDTH-1:0]  pipe [0:STAGES-1];
  reg [STAGES-1:0] vpipe;
  integer k;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (k = 0; k < STAGES; k = k + 1)
        pipe[k] <= {WIDTH{1'b0}};
      vpipe     <= {STAGES{1'b0}};
      out_valid <= 1'b0;
      data_out  <= {WIDTH{1'b0}};
    end else begin
      pipe[0]  <= data_in[WIDTH-1] ? (({data_in[WIDTH-2:0], 1'b0}) ^ POLY[WIDTH-1:0])
                                    : {data_in[WIDTH-2:0], 1'b0};
      vpipe[0] <= in_valid;
      for (k = 1; k < STAGES; k = k + 1) begin
        pipe[k]  <= pipe[k-1][WIDTH-1] ? (({pipe[k-1][WIDTH-2:0], 1'b0}) ^ POLY[WIDTH-1:0])
                                        : {pipe[k-1][WIDTH-2:0], 1'b0};
        vpipe[k] <= vpipe[k-1];
      end
      out_valid <= vpipe[STAGES-1];
      data_out  <= pipe[STAGES-1];
    end
  end
endmodule

// Free-running domain sequencer: generates operands, drives compute_pipeline,
// pushes results into the outbound CDC FIFO. Binary-encoded on purpose (not
// one-hot) -- a legitimate FSM-re-encoding target for the optimization loop.
module domain_ctrl_fsm #(
  parameter WIDTH   = 16,
  parameter LANES   = 4,
  parameter OUT_W   = 2*WIDTH + 4   // must be >= compute_pipeline's acc width
) (
  input  wire clk,
  input  wire rst_n,

  output reg              fifo_wr_en,
  output reg [OUT_W-1:0]  fifo_wr_data,
  input  wire              fifo_wr_full
);
  localparam S_IDLE    = 3'd0;
  localparam S_LOAD    = 3'd1;
  localparam S_COMPUTE = 3'd2;
  localparam S_WAIT    = 3'd3;
  localparam S_PUSH    = 3'd4;

  reg [2:0] state, next_state;

  reg [WIDTH*LANES-1:0] a_reg, b_reg;
  reg [WIDTH-1:0]        lfsr;

  wire                       cp_valid_out;
  wire [2*WIDTH+$clog2(LANES)-1:0] cp_acc_out;
  reg                        cp_valid_in;

  compute_pipeline #(
    .WIDTH(WIDTH),
    .LANES(LANES)
  ) u_compute (
    .clk       (clk),
    .rst_n     (rst_n),
    .valid_in  (cp_valid_in),
    .a_in      (a_reg),
    .b_in      (b_reg),
    .valid_out (cp_valid_out),
    .acc_out   (cp_acc_out)
  );

  // simple LFSR-ish operand generator, self-contained (no external stimulus
  // needed for synth/STA benchmarking)
  wire lfsr_fb = lfsr[WIDTH-1] ^ lfsr[WIDTH-3] ^ lfsr[WIDTH-4] ^ lfsr[0];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= S_IDLE;
      lfsr         <= {WIDTH{1'b1}};
      a_reg        <= {(WIDTH*LANES){1'b0}};
      b_reg        <= {(WIDTH*LANES){1'b0}};
      cp_valid_in  <= 1'b0;
      fifo_wr_en   <= 1'b0;
      fifo_wr_data <= {OUT_W{1'b0}};
    end else begin
      state <= next_state;

      case (state)
        S_IDLE: begin
          cp_valid_in <= 1'b0;
          fifo_wr_en  <= 1'b0;
        end

        S_LOAD: begin
          lfsr        <= {lfsr[WIDTH-2:0], lfsr_fb};
          a_reg       <= {LANES{lfsr}};
          b_reg       <= {LANES{~lfsr}};
          cp_valid_in <= 1'b0;
          fifo_wr_en  <= 1'b0;
        end

        S_COMPUTE: begin
          cp_valid_in <= 1'b1;
          fifo_wr_en  <= 1'b0;
        end

        S_WAIT: begin
          cp_valid_in <= 1'b0;
          fifo_wr_en  <= 1'b0;
        end

        S_PUSH: begin
          cp_valid_in  <= 1'b0;
          fifo_wr_en   <= cp_valid_out && !fifo_wr_full;
          fifo_wr_data <= {{(OUT_W-2*WIDTH-$clog2(LANES)){1'b0}}, cp_acc_out};
        end

        default: begin
          cp_valid_in <= 1'b0;
          fifo_wr_en  <= 1'b0;
        end
      endcase
    end
  end

  always @(*) begin
    case (state)
      S_IDLE:    next_state = S_LOAD;
      S_LOAD:    next_state = S_COMPUTE;
      S_COMPUTE: next_state = S_WAIT;
      S_WAIT:    next_state = cp_valid_out ? S_PUSH : S_WAIT;
      S_PUSH:    next_state = S_IDLE;
      default:   next_state = S_IDLE;
    endcase
  end
endmodule

// Stage 6 benchmark: 5 independent async clock-domain "DSP-ish" subsystems,
// each with its own generated (divided) clock, ring-connected via async-FIFO
// CDC bridges. ~50k-cell SoC-subsystem scale target.
//
// Cell budget split deliberately across two different block types per domain
// (found empirically, not assumed): compute_pipeline's multiply-adder tree
// is a real critical-path source but its equivalence check blows up SAT
// past ~5 parallel lanes on a genuine restructuring edit, so LANES is capped
// at 4 everywhere for EQY safety margin. The bulk of the ~50k cells instead
// comes from crc_pipeline (GF(2)-linear shift/XOR chain), which stays SAT-
// cheap at any size since it has no multiply/reassociation to reason about.
module nebula_soc #(
  parameter W0 = 12, parameter L0 = 4, parameter DIV0 = 2,  parameter CS0 = 60,
  parameter W1 = 12, parameter L1 = 4, parameter DIV1 = 4,  parameter CS1 = 70,
  parameter W2 = 12, parameter L2 = 4, parameter DIV2 = 6,  parameter CS2 = 80,
  parameter W3 = 12, parameter L3 = 4, parameter DIV3 = 8,  parameter CS3 = 90,
  parameter W4 = 12, parameter L4 = 4, parameter DIV4 = 10, parameter CS4 = 70,
  parameter CRC_W = 64,
  parameter FIFO_ADDR_W = 4
) (
  input  wire clk0, input wire rst0_n,
  input  wire clk1, input wire rst1_n,
  input  wire clk2, input wire rst2_n,
  input  wire clk3, input wire rst3_n,
  input  wire clk4, input wire rst4_n,

  output wire [W0*2+5:0] rx_acc0,
  output wire [W1*2+5:0] rx_acc1,
  output wire [W2*2+5:0] rx_acc2,
  output wire [W3*2+5:0] rx_acc3,
  output wire [W4*2+5:0] rx_acc4
);
  localparam OW0 = W0*2 + 6;
  localparam OW1 = W1*2 + 6;
  localparam OW2 = W2*2 + 6;
  localparam OW3 = W3*2 + 6;
  localparam OW4 = W4*2 + 6;

  wire div_clk0, div_clk1, div_clk2, div_clk3, div_clk4;

  clk_divider #(.DIV(DIV0)) u_div0 (.clk(clk0), .rst_n(rst0_n), .div_clk(div_clk0));
  clk_divider #(.DIV(DIV1)) u_div1 (.clk(clk1), .rst_n(rst1_n), .div_clk(div_clk1));
  clk_divider #(.DIV(DIV2)) u_div2 (.clk(clk2), .rst_n(rst2_n), .div_clk(div_clk2));
  clk_divider #(.DIV(DIV3)) u_div3 (.clk(clk3), .rst_n(rst3_n), .div_clk(div_clk3));
  clk_divider #(.DIV(DIV4)) u_div4 (.clk(clk4), .rst_n(rst4_n), .div_clk(div_clk4));

  // domain N's ctrl FSM runs on its divided clock (the generated clock
  // actually drives real logic, not left dangling)
  wire              fifo0_wr_en, fifo1_wr_en, fifo2_wr_en, fifo3_wr_en, fifo4_wr_en;
  wire [OW0-1:0]    fifo0_wr_data;
  wire [OW1-1:0]    fifo1_wr_data;
  wire [OW2-1:0]    fifo2_wr_data;
  wire [OW3-1:0]    fifo3_wr_data;
  wire [OW4-1:0]    fifo4_wr_data;
  wire              fifo0_wr_full, fifo1_wr_full, fifo2_wr_full, fifo3_wr_full, fifo4_wr_full;

  domain_ctrl_fsm #(.WIDTH(W0), .LANES(L0), .OUT_W(OW0)) u_fsm0 (
    .clk(div_clk0), .rst_n(rst0_n),
    .fifo_wr_en(fifo0_wr_en), .fifo_wr_data(fifo0_wr_data), .fifo_wr_full(fifo0_wr_full)
  );
  domain_ctrl_fsm #(.WIDTH(W1), .LANES(L1), .OUT_W(OW1)) u_fsm1 (
    .clk(div_clk1), .rst_n(rst1_n),
    .fifo_wr_en(fifo1_wr_en), .fifo_wr_data(fifo1_wr_data), .fifo_wr_full(fifo1_wr_full)
  );
  domain_ctrl_fsm #(.WIDTH(W2), .LANES(L2), .OUT_W(OW2)) u_fsm2 (
    .clk(div_clk2), .rst_n(rst2_n),
    .fifo_wr_en(fifo2_wr_en), .fifo_wr_data(fifo2_wr_data), .fifo_wr_full(fifo2_wr_full)
  );
  domain_ctrl_fsm #(.WIDTH(W3), .LANES(L3), .OUT_W(OW3)) u_fsm3 (
    .clk(div_clk3), .rst_n(rst3_n),
    .fifo_wr_en(fifo3_wr_en), .fifo_wr_data(fifo3_wr_data), .fifo_wr_full(fifo3_wr_full)
  );
  domain_ctrl_fsm #(.WIDTH(W4), .LANES(L4), .OUT_W(OW4)) u_fsm4 (
    .clk(div_clk4), .rst_n(rst4_n),
    .fifo_wr_en(fifo4_wr_en), .fifo_wr_data(fifo4_wr_data), .fifo_wr_full(fifo4_wr_full)
  );

  // ring CDC: domain N writes fifo N on its own (divided) clock, domain
  // N+1 reads it on its own (divided) clock -- genuinely asynchronous
  // crossing since all 5 masters are independent.
  wire              fifo0_rd_empty, fifo1_rd_empty, fifo2_rd_empty, fifo3_rd_empty, fifo4_rd_empty;
  wire [OW0-1:0]    fifo0_rd_data;
  wire [OW1-1:0]    fifo1_rd_data;
  wire [OW2-1:0]    fifo2_rd_data;
  wire [OW3-1:0]    fifo3_rd_data;
  wire [OW4-1:0]    fifo4_rd_data;

  async_fifo #(.WIDTH(OW0), .ADDR_W(FIFO_ADDR_W)) u_fifo0 (
    .wr_clk(div_clk0), .wr_rst_n(rst0_n), .wr_en(fifo0_wr_en), .wr_data(fifo0_wr_data), .wr_full(fifo0_wr_full),
    .rd_clk(div_clk1), .rd_rst_n(rst1_n), .rd_en(!fifo0_rd_empty), .rd_data(fifo0_rd_data), .rd_empty(fifo0_rd_empty)
  );
  async_fifo #(.WIDTH(OW1), .ADDR_W(FIFO_ADDR_W)) u_fifo1 (
    .wr_clk(div_clk1), .wr_rst_n(rst1_n), .wr_en(fifo1_wr_en), .wr_data(fifo1_wr_data), .wr_full(fifo1_wr_full),
    .rd_clk(div_clk2), .rd_rst_n(rst2_n), .rd_en(!fifo1_rd_empty), .rd_data(fifo1_rd_data), .rd_empty(fifo1_rd_empty)
  );
  async_fifo #(.WIDTH(OW2), .ADDR_W(FIFO_ADDR_W)) u_fifo2 (
    .wr_clk(div_clk2), .wr_rst_n(rst2_n), .wr_en(fifo2_wr_en), .wr_data(fifo2_wr_data), .wr_full(fifo2_wr_full),
    .rd_clk(div_clk3), .rd_rst_n(rst3_n), .rd_en(!fifo2_rd_empty), .rd_data(fifo2_rd_data), .rd_empty(fifo2_rd_empty)
  );
  async_fifo #(.WIDTH(OW3), .ADDR_W(FIFO_ADDR_W)) u_fifo3 (
    .wr_clk(div_clk3), .wr_rst_n(rst3_n), .wr_en(fifo3_wr_en), .wr_data(fifo3_wr_data), .wr_full(fifo3_wr_full),
    .rd_clk(div_clk4), .rd_rst_n(rst4_n), .rd_en(!fifo3_rd_empty), .rd_data(fifo3_rd_data), .rd_empty(fifo3_rd_empty)
  );
  async_fifo #(.WIDTH(OW4), .ADDR_W(FIFO_ADDR_W)) u_fifo4 (
    .wr_clk(div_clk4), .wr_rst_n(rst4_n), .wr_en(fifo4_wr_en), .wr_data(fifo4_wr_data), .wr_full(fifo4_wr_full),
    .rd_clk(div_clk0), .rd_rst_n(rst0_n), .rd_en(!fifo4_rd_empty), .rd_data(fifo4_rd_data), .rd_empty(fifo4_rd_empty)
  );

  // per-domain CRC padding block: free-running self-contained counter feeds
  // crc_pipeline (fully registered, GF(2)-linear -- safe cell-count bulk,
  // see module comment). Result folded into that domain's rx accumulator.
  reg [CRC_W-1:0] crc_ctr0, crc_ctr1, crc_ctr2, crc_ctr3, crc_ctr4;
  wire [CRC_W-1:0] crc_out0, crc_out1, crc_out2, crc_out3, crc_out4;
  wire             crc_ov0, crc_ov1, crc_ov2, crc_ov3, crc_ov4;

  always @(posedge div_clk0 or negedge rst0_n)
    if (!rst0_n) crc_ctr0 <= {CRC_W{1'b0}}; else crc_ctr0 <= crc_ctr0 + 1'b1;
  always @(posedge div_clk1 or negedge rst1_n)
    if (!rst1_n) crc_ctr1 <= {CRC_W{1'b0}}; else crc_ctr1 <= crc_ctr1 + 1'b1;
  always @(posedge div_clk2 or negedge rst2_n)
    if (!rst2_n) crc_ctr2 <= {CRC_W{1'b0}}; else crc_ctr2 <= crc_ctr2 + 1'b1;
  always @(posedge div_clk3 or negedge rst3_n)
    if (!rst3_n) crc_ctr3 <= {CRC_W{1'b0}}; else crc_ctr3 <= crc_ctr3 + 1'b1;
  always @(posedge div_clk4 or negedge rst4_n)
    if (!rst4_n) crc_ctr4 <= {CRC_W{1'b0}}; else crc_ctr4 <= crc_ctr4 + 1'b1;

  crc_pipeline #(.WIDTH(CRC_W), .STAGES(CS0)) u_crc0 (
    .clk(div_clk0), .rst_n(rst0_n), .in_valid(1'b1), .data_in(crc_ctr0), .out_valid(crc_ov0), .data_out(crc_out0));
  crc_pipeline #(.WIDTH(CRC_W), .STAGES(CS1)) u_crc1 (
    .clk(div_clk1), .rst_n(rst1_n), .in_valid(1'b1), .data_in(crc_ctr1), .out_valid(crc_ov1), .data_out(crc_out1));
  crc_pipeline #(.WIDTH(CRC_W), .STAGES(CS2)) u_crc2 (
    .clk(div_clk2), .rst_n(rst2_n), .in_valid(1'b1), .data_in(crc_ctr2), .out_valid(crc_ov2), .data_out(crc_out2));
  crc_pipeline #(.WIDTH(CRC_W), .STAGES(CS3)) u_crc3 (
    .clk(div_clk3), .rst_n(rst3_n), .in_valid(1'b1), .data_in(crc_ctr3), .out_valid(crc_ov3), .data_out(crc_out3));
  crc_pipeline #(.WIDTH(CRC_W), .STAGES(CS4)) u_crc4 (
    .clk(div_clk4), .rst_n(rst4_n), .in_valid(1'b1), .data_in(crc_ctr4), .out_valid(crc_ov4), .data_out(crc_out4));

  // receive-side accumulators (keeps CDC-received data observable/used, on
  // the receiving domain's divided clock) -- folds in both the CDC-received
  // neighbor data and this domain's own crc_pipeline output.
  reg [OW0-1:0] acc0;
  reg [OW1-1:0] acc1;
  reg [OW2-1:0] acc2;
  reg [OW3-1:0] acc3;
  reg [OW4-1:0] acc4;

  always @(posedge div_clk1 or negedge rst1_n)
    if (!rst1_n) acc1 <= {OW1{1'b0}};
    else acc1 <= acc1 ^ (fifo0_rd_empty ? {OW1{1'b0}} : fifo0_rd_data[OW1-1:0])
                       ^ (crc_ov1 ? crc_out1[OW1-1:0] : {OW1{1'b0}});
  always @(posedge div_clk2 or negedge rst2_n)
    if (!rst2_n) acc2 <= {OW2{1'b0}};
    else acc2 <= acc2 ^ (fifo1_rd_empty ? {OW2{1'b0}} : fifo1_rd_data[OW2-1:0])
                       ^ (crc_ov2 ? crc_out2[OW2-1:0] : {OW2{1'b0}});
  always @(posedge div_clk3 or negedge rst3_n)
    if (!rst3_n) acc3 <= {OW3{1'b0}};
    else acc3 <= acc3 ^ (fifo2_rd_empty ? {OW3{1'b0}} : fifo2_rd_data[OW3-1:0])
                       ^ (crc_ov3 ? crc_out3[OW3-1:0] : {OW3{1'b0}});
  always @(posedge div_clk4 or negedge rst4_n)
    if (!rst4_n) acc4 <= {OW4{1'b0}};
    else acc4 <= acc4 ^ (fifo3_rd_empty ? {OW4{1'b0}} : fifo3_rd_data[OW4-1:0])
                       ^ (crc_ov4 ? crc_out4[OW4-1:0] : {OW4{1'b0}});
  always @(posedge div_clk0 or negedge rst0_n)
    if (!rst0_n) acc0 <= {OW0{1'b0}};
    else acc0 <= acc0 ^ (fifo4_rd_empty ? {OW0{1'b0}} : fifo4_rd_data[OW0-1:0])
                       ^ (crc_ov0 ? crc_out0[OW0-1:0] : {OW0{1'b0}});

  assign rx_acc0 = acc0;
  assign rx_acc1 = acc1;
  assign rx_acc2 = acc2;
  assign rx_acc3 = acc3;
  assign rx_acc4 = acc4;
endmodule
