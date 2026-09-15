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
    input clk,
    input  [31:0] radicand,
    output [15:0] root,
    output [16:0] rem_out
);

// Bit-pair restoring square root, 16 iterations total. Originally fully
// combinational (267 gate-stages deep). Now split into 4 pipeline stages
// of 4 iterations each, with 3 register boundaries in between, so no
// single combinational section is more than ~4 iterations deep. clk is a
// new port added purely to host these internal pipeline stages; the
// stages carry no reset because they hold no state that must be
// recovered (they are pure feed-forward pipeline registers).

integer i;

// ---- stage 0: iterations for bit-pairs i=15..12 ----
reg [33:0] rem_s0;
reg [15:0] root_s0;
always @(*) begin
    rem_s0  = 34'd0;
    root_s0 = 16'd0;
    for (i = 15; i >= 12; i = i - 1) begin
        rem_s0  = {rem_s0[31:0], radicand[2*i+1], radicand[2*i]};
        root_s0 = root_s0 << 1;
        if (rem_s0 >= {root_s0, 2'b01}) begin
            rem_s0  = rem_s0 - {root_s0, 2'b01};
            root_s0 = root_s0 | 16'd1;
        end
    end
end

reg [33:0] rem_p1;
reg [15:0] root_p1;
always @(posedge clk) begin
    rem_p1  <= rem_s0;
    root_p1 <= root_s0;
end

// ---- stage 1: iterations for bit-pairs i=11..8 ----
reg [33:0] rem_s1;
reg [15:0] root_s1;
always @(*) begin
    rem_s1  = rem_p1;
    root_s1 = root_p1;
    for (i = 11; i >= 8; i = i - 1) begin
        rem_s1  = {rem_s1[31:0], radicand[2*i+1], radicand[2*i]};
        root_s1 = root_s1 << 1;
        if (rem_s1 >= {root_s1, 2'b01}) begin
            rem_s1  = rem_s1 - {root_s1, 2'b01};
            root_s1 = root_s1 | 16'd1;
        end
    end
end

reg [33:0] rem_p2;
reg [15:0] root_p2;
always @(posedge clk) begin
    rem_p2  <= rem_s1;
    root_p2 <= root_s1;
end

// ---- stage 2: iterations for bit-pairs i=7..4 ----
reg [33:0] rem_s2;
reg [15:0] root_s2;
always @(*) begin
    rem_s2  = rem_p2;
    root_s2 = root_p2;
    for (i = 7; i >= 4; i = i - 1) begin
        rem_s2  = {rem_s2[31:0], radicand[2*i+1], radicand[2*i]};
        root_s2 = root_s2 << 1;
        if (rem_s2 >= {root_s2, 2'b01}) begin
            rem_s2  = rem_s2 - {root_s2, 2'b01};
            root_s2 = root_s2 | 16'd1;
        end
    end
end

reg [33:0] rem_p3;
reg [15:0] root_p3;
always @(posedge clk) begin
    rem_p3  <= rem_s2;
    root_p3 <= root_s2;
end

// ---- stage 3: iterations for bit-pairs i=3..0 ----
reg [33:0] rem_s3;
reg [15:0] root_s3;
always @(*) begin
    rem_s3  = rem_p3;
    root_s3 = root_p3;
    for (i = 3; i >= 0; i = i - 1) begin
        rem_s3  = {rem_s3[31:0], radicand[2*i+1], radicand[2*i]};
        root_s3 = root_s3 << 1;
        if (rem_s3 >= {root_s3, 2'b01}) begin
            rem_s3  = rem_s3 - {root_s3, 2'b01};
            root_s3 = root_s3 | 16'd1;
        end
    end
end

assign root    = root_s3;
assign rem_out = rem_s3[16:0];

endmodule
