`timescale 1ns / 1ps

// ===================================================================
//  bin_to_bcd_32 -- 32-bit binary to 10-digit packed BCD, combinational
//
//  The UART prints counters in decimal, so something has to turn a
//  32-bit value into digits. This is double dabble: shift the binary
//  value left one bit at a time into a BCD accumulator, and before each
//  shift add 3 to any BCD digit that has reached 5 or more.
//
//  There are 32 shifts and each one reads the accumulator the previous
//  shift produced, with ten parallel add-3 corrections in between, so
//  the whole conversion is one 32-deep combinational chain. Splitting
//  it across UART bit-periods, or converting one digit at a time, is a
//  structural change -- the correction chain itself cannot be sized
//  faster.
// ===================================================================
module bin_to_bcd_32(binary, bcd);

input  wire [31:0] binary;
output wire [39:0] bcd;      // 10 BCD digits, most significant first

wire [39:0] bcd_chain [0:32];

assign bcd_chain[0] = 40'd0;

genvar i, d;
generate
    for (i = 0; i < 32; i = i + 1) begin : dabble_step
        // 39 bits, not 40. The shift below keeps the low 39 and drops the
        // top one, so computing the top bit of digit 9 would produce a value
        // nothing reads. It can be dropped rather than sunk because it is
        // provably dead: a 32-bit input tops out at 4_294_967_295, so digit 9
        // never exceeds 4, its add-3 can never fire, and the three bits kept
        // below already carry everything digit 9 can hold.
        wire [38:0] corrected;

        // Add 3 to every digit already >= 5, so that the shift that
        // follows carries into the next digit at the right point.
        for (d = 0; d < 9; d = d + 1) begin : digit
            wire [3:0] nibble = bcd_chain[i][4*d + 3 : 4*d];
            assign corrected[4*d + 3 : 4*d] = (nibble >= 4'd5) ? (nibble + 4'd3)
                                                               : nibble;
        end
        assign corrected[38:36] = bcd_chain[i][38:36];

        // Shift left, bringing in the next binary bit, most significant
        // bit of the input first.
        assign bcd_chain[i + 1] = {corrected, binary[31 - i]};
    end
endgenerate

assign bcd = bcd_chain[32];

endmodule
