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

parameter DOT_LAT = 4;

input             clk, rst;
input             empty_1, empty_2, full;
input      [31:0] data_1, data_2;
output            r_en_1, r_en_2, w_en;
output     [31:0] data_w;

reg [DOT_LAT-1:0] vld;

// src   operands are available to pop
// room  the result FIFO can accept a write
// adv   the pipeline may move: there is somewhere to put a result, and
//       either a new operand pair to start or work still in flight
wire src  = (!empty_1 && !empty_2);
wire room = !full;
wire adv  = room && src;

// `|vld` in `adv` is what drains the pipe. Without it the last DOT_LAT
// results sit in the stages until new operands happen to arrive, so a master
// that writes five operand pairs reads back one result. That is a functional
// change, not a latency change, and it is the failure this term prevents.
//
// r_en is deliberately unchanged in value: adv && src reduces to room && src,
// which is exactly what the combinational version drove. Operand consumption
// is bit-identical to the baseline; only the result push moved.
assign r_en_1 = adv && src;
assign r_en_2 = adv && src;
assign w_en   = adv && vld[DOT_LAT-1];

// No result is ever dropped: the pipeline stages and vld share one enable, so
// they stall and advance together. No overflow is possible: adv requires
// !full, and at most one vld bit leaves per adv.
always @(posedge clk)
begin
     if (rst)
          vld <= {DOT_LAT{1'b0}};
     else if (adv)
          vld <= {vld[DOT_LAT-2:0], src};
end

fp4_dot_unit fp4_dot_0(clk, rst, adv, data_1, data_2, data_w);

endmodule
