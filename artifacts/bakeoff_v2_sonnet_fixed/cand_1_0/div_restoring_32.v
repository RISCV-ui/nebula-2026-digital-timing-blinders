`timescale 1ns / 1ps

// ===================================================================
//  div_restoring_32 -- 32-bit unsigned restoring divider, combinational
//
//  The core has MUL (multiplier_pipelined) but no divide, so DIV/REM
//  trap out to software. This is the hardware divider, written the
//  obvious way first: thirty-two restoring steps, each a 33-bit compare
//  and conditional subtract, chained end to end in one cycle.
//
//  That chain is the point. Every step depends on the remainder the
//  previous step produced, so the path is 32 subtractors deep and no
//  amount of gate sizing shortens it -- the structure has to change.
//  Pipelining it, or reworking it as a higher-radix / SRT recurrence,
//  is an RTL decision.
//
//  Division by zero returns all-ones quotient and the dividend as
//  remainder, matching the RISC-V unsigned DIVU/REMU definition, so the
//  block can be dropped into the execute stage without a guard.
// ===================================================================
module div_restoring_32(dividend, divisor, quotient, remainder);

input  wire [31:0] dividend;
input  wire [31:0] divisor;
output wire [31:0] quotient;
output wire [31:0] remainder;

// rem_chain[i] is the running remainder after 32-i steps; the extra bit
// is the headroom the compare needs before the subtract.
wire [32:0] rem_chain [0:32];
wire [31:0] quo_bits;

assign rem_chain[0] = 33'd0;

genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : restoring_step
        // Shift the next dividend bit in at the bottom, then subtract the
        // divisor if it fits. "If it fits" is the quotient bit.
        wire [32:0] shifted = {rem_chain[i][31:0], dividend[31 - i]};
        wire [32:0] trial   = shifted - {1'b0, divisor};
        wire        fits    = (shifted >= {1'b0, divisor});

        assign quo_bits[31 - i]  = fits;
        assign rem_chain[i + 1]  = fits ? trial : shifted;
    end
endgenerate

wire div_by_zero = (divisor == 32'd0);

assign quotient  = div_by_zero ? 32'hFFFF_FFFF : quo_bits;
assign remainder = div_by_zero ? dividend      : rem_chain[32][31:0];

endmodule
