`timescale 1ns / 1ps

// fp4_dot_stage -- the pipelined dot unit plus the elastic control that
// carries it, as one module with FIFO-shaped ports.
//
// This exists as its own module because it is the unit the proof is about.
// fp4_dot_unit used to be combinational, so axi_lite_dot popped a pair of
// operands and pushed the result on the same cycle and the whole thing was a
// wire. Four pipeline stages make the push a separate event from the pop, and
// the question "does the same sequence of results still come out" is not a
// question about axi_lite_dot -- that module also holds three asynchronous
// FIFOs and two clock domains, and a bounded solver stepping both clocks
// together would be modelling one phase relationship out of infinitely many.
//
// Cut here instead. Everything in this module runs on one clock. The FIFO
// interfaces are free inputs, which is the right cut: whether the FIFOs
// themselves are safe is G2's question, not this one.
//
// Ports mirror the signals it replaced in axi_lite_dot one for one, so the
// parent keeps the same net names and the diff there is an instantiation.

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
wire adv  = room && (src || |vld);

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
