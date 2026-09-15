`timescale 1ns / 1ps

// ===================================================================
//  mult_array_32 -- 32x32 unsigned multiply, combinational ripple array
//
//  The timer converts between its own tick rate and the rate software
//  asked for, which is a 32x32 multiply. multiplier_pipelined already
//  exists in the core, but it is three stages deep and lives in the
//  clk1 domain; the timer needs the product inside one clk_s1 tick, so
//  this is the flat version.
//
//  Flat is the operative word: the partial products are summed by a
//  linear chain of 32 adders, each waiting on the one before it. That
//  is 32 carry-propagate additions in series -- textbook-slow on
//  purpose, and exactly the shape that retiming or a Wallace/Booth
//  restructure fixes.
// ===================================================================
module mult_array_32(a, b, product);

input  wire [31:0] a;
input  wire [31:0] b;
output wire [63:0] product;

wire [63:0] partial_sum [0:32];

assign partial_sum[0] = 64'd0;

genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : pp_row
        // Row i is a AND b[i], shifted into place. Summing row by row,
        // rather than in a tree, is what keeps the carry chains in
        // series instead of in parallel.
        wire [63:0] row = b[i] ? ({32'd0, a} << i) : 64'd0;
        assign partial_sum[i + 1] = partial_sum[i] + row;
    end
endgenerate

assign product = partial_sum[32];

endmodule
