`timescale 1ns / 1ps

// ===================================================================
//  isqrt_restoring_32 -- 32-bit integer square root, combinational
//
//  The GPIO block samples a pair of analogue channels and reports a
//  magnitude, which is sqrt(x^2 + y^2). This is the sqrt half, done as
//  the classical restoring (digit-recurrence) square root: sixteen
//  steps, each a 34-bit compare and conditional subtract against a
//  trial root that is rebuilt from the root bits found so far.
//
//  Like div_restoring_32, every step needs the previous step's
//  remainder, so the sixteen subtracts sit in one combinational chain.
//  The transform that helps here is structural -- pipeline the
//  recurrence, or fold pairs of steps into a radix-4 iteration -- not
//  anything the resizer can do to the gates.
// ===================================================================
module isqrt_restoring_32(
    input         clk,
    input  [31:0] radicand,
    output [15:0] root,
    output [16:0] rem_out
);

// Restoring square root, 2 bits (one digit) of radicand consumed per
// iteration, 16 iterations total to produce a 16-bit root. Originally a
// single unrolled combinational block (267 gate levels); now split into
// 4 groups of 4 iterations each, with a register boundary between
// groups, so no single combinational stage does more than 4 digit
// iterations.

function [32:0] sqrt_stage;
    input [31:0] rad;
    input [16:0] rem_in;
    input [15:0] root_in;
    input [4:0]  hi_i;
    integer i;
    reg [16:0] rem_v;
    reg [15:0] root_v;
    reg [1:0]  bits;
    reg [16:0] trial;
    begin
        rem_v  = rem_in;
        root_v = root_in;
        for (i = hi_i; i >= hi_i - 3; i = i - 1) begin
            bits   = rad[2*i +: 2];
            rem_v  = {rem_v[14:0], bits};
            root_v = root_v << 1;
            trial  = {root_v, 1'b1};
            if (rem_v >= trial) begin
                rem_v  = rem_v - trial;
                root_v = root_v | 16'd1;
            end
        end
        sqrt_stage = {rem_v, root_v};
    end
endfunction

// Stage 0: radicand bits [31:24]
wire [32:0] stage0_out = sqrt_stage(radicand, 17'd0, 16'd0, 5'd15);

reg [16:0] rem_p1;
reg [15:0] root_p1;
reg [31:0] radicand_p1;
always @(posedge clk) begin
    rem_p1      <= stage0_out[32:16];
    root_p1     <= stage0_out[15:0];
    radicand_p1 <= radicand;
end

// Stage 1: radicand bits [23:16]
wire [32:0] stage1_out = sqrt_stage(radicand_p1, rem_p1, root_p1, 5'd11);

reg [16:0] rem_p2;
reg [15:0] root_p2;
reg [31:0] radicand_p2;
always @(posedge clk) begin
    rem_p2      <= stage1_out[32:16];
    root_p2     <= stage1_out[15:0];
    radicand_p2 <= radicand_p1;
end

// Stage 2: radicand bits [15:8]
wire [32:0] stage2_out = sqrt_stage(radicand_p2, rem_p2, root_p2, 5'd7);

reg [16:0] rem_p3;
reg [15:0] root_p3;
reg [31:0] radicand_p3;
always @(posedge clk) begin
    rem_p3      <= stage2_out[32:16];
    root_p3     <= stage2_out[15:0];
    radicand_p3 <= radicand_p2;
end

// Stage 3: radicand bits [7:0], final result, combinational tap
wire [32:0] stage3_out = sqrt_stage(radicand_p3, rem_p3, root_p3, 5'd3);

assign rem_out = stage3_out[32:16];
assign root    = stage3_out[15:0];

endmodule
