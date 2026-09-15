`timescale 1ns / 1ps

// ===================================================================
//  clk_gate -- integrated clock gate, latch based
//
//  A bare `clk_out = clk_in & clk_en` is wrong in silicon: the enable is
//  produced by logic on the same clock, so it can change while clk_in is
//  high, and the pulse it chops is a runt that the flops behind it may or
//  may not see.
//
//  The enable is therefore passed through a latch that is transparent only
//  while clk_in is low. By construction the enable can then only change
//  during the low phase, so every pulse reaching clk_out is either a whole
//  pulse or no pulse at all. This is the structure a standard-cell ICG
//  implements internally.
// ===================================================================
module clk_gate(
    clk_in,
    clk_en,
    clk_out
    );

input  clk_in;
input  clk_en;
output clk_out;

reg en_latch;

// Intentionally a latch, not a flop. A flop here would update on the same
// edge the gate passes, which delays the enable by a cycle and still leaves
// the chop it was meant to remove.
always @(*)
    if (!clk_in)
        en_latch = clk_en;

assign clk_out = clk_in & en_latch;

endmodule
