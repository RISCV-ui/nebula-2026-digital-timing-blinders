`timescale 1ns / 1ps

// fp4_dot_stage -- the dot unit and the FIFO control around it, as one module.
//
// This is a hierarchy split and nothing else. Every expression below is
// character for character what axi_lite_dot drove before the split, and
// fp4_dot_unit is instantiated unchanged. No logic moved, no logic changed,
// so the flattened netlist and the baseline PPA numbers are still the same
// design.
//
// The split exists because this is the unit the optimizer is aimed at. The
// path slicer attributes 85.7% of the SoC's worst path to three chained
// fp8_adder instances inside fp4_dot_unit, and 31.66 ns of combinational
// delay into a 12.5 ns clk_s5 period cannot be closed by any gate-level
// lever. Whatever closes it has to add registers, which changes when the
// result is pushed relative to when the operands are popped -- and that is a
// question about this control logic, not about the adder tree.
//
// Cutting the module boundary here puts both halves of that question inside
// one single-clock module. axi_lite_dot holds three asynchronous FIFOs and
// two clock domains; a bounded solver stepping both clocks together would be
// checking one phase relationship out of infinitely many. Here the FIFO
// interfaces are free inputs, which is the right cut -- whether the FIFOs
// themselves are safe is G2's question, not this one.

module fp4_dot_stage(clk, rst,
                     empty_1, empty_2, full,
                     data_1, data_2,
                     r_en_1, r_en_2, w_en, data_w);

input             clk, rst;
input             empty_1, empty_2, full;
input      [31:0] data_1, data_2;
output            r_en_1, r_en_2, w_en;
output     [31:0] data_w;

assign r_en_1 = (!empty_1 && !empty_2 && !full);
assign r_en_2 = (!empty_1 && !empty_2 && !full);
assign w_en   = (!empty_1 && !empty_2 && !full);

fp4_dot_unit fp4_dot_0(clk, rst, data_1, data_2, data_w);

// Intentionally unused. fp4_dot_unit is combinational and ignores both, but
// they stay on the port list because anything that pipelines this module will
// need them, and a port list that changes shape is a port list the parent has
// to be re-verified against.
wire _unused_ok = &{1'b0, clk, rst, 1'b0};

endmodule
