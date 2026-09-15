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
module isqrt_restoring_32(radicand, root, rem_out);

input  wire [31:0] radicand;
output wire [15:0] root;
output wire [16:0] rem_out;

wire [33:0] rem_chain  [0:16];
wire [15:0] root_chain [0:16];

assign rem_chain[0]  = 34'd0;
assign root_chain[0] = 16'd0;

genvar i;
generate
    for (i = 0; i < 16; i = i + 1) begin : sqrt_step
        // Bring down the next two radicand bits, most significant pair
        // first.
        wire [33:0] shifted = {rem_chain[i][31:0], radicand[31 - 2*i], radicand[30 - 2*i]};

        // Trial subtrahend is (root << 2) | 1, which is what the running
        // root expands to when the next digit is assumed to be 1.
        wire [33:0] trial_sub = {16'd0, root_chain[i], 2'b01};
        wire        fits      = (shifted >= trial_sub);

        assign rem_chain[i + 1]  = fits ? (shifted - trial_sub) : shifted;
        assign root_chain[i + 1] = {root_chain[i][14:0], fits};
    end
endgenerate

assign root    = root_chain[16];
assign rem_out = rem_chain[16][16:0];

endmodule
