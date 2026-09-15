// Cut models for the absorption proof.
//
// Both FIFOs and the dot unit are replaced by free-behaviour stubs, so every
// signal crossing into the clk_1 read side is unconstrained. That is
// deliberate, and it is the same cut fp4_dot_stage documents: axi_lite_dot
// spans two asynchronous clock domains, and a bounded solver stepping both
// together would be proving one phase relationship out of infinitely many.
// Whether the FIFOs themselves are safe is G2's question, not this one.
//
// The stubs use `anyseq` rather than a blackbox attribute: a blackbox fails
// Yosys's hierarchy check, and an empty module would drive its outputs to a
// constant x instead of leaving them free, which would make the proof
// vacuous. `anyseq` hands the solver a fresh unconstrained value every cycle.
//
// Free outputs make the proof strictly harder, not easier: the properties must
// hold for *every* behaviour the FIFO could exhibit, including adversarial
// ones the real FIFO never produces. Ports mirror the real modules in name and
// order; every instantiation in axi_lite_dot is positional.
module asynchronous_fifo_gen #(parameter width = 36, parameter logofdepth = 4)
                        (clk_1, rst_1,
                         clk_2, rst_2,
                         data_in_clk1, w_en_clk_1,
                         data_out_clk2, r_en_clk_2,
                         fifo_full, fifo_empty);
input              clk_1, rst_1, clk_2, rst_2;
input  [width-1:0] data_in_clk1;
input              w_en_clk_1, r_en_clk_2;
output [width-1:0] data_out_clk2;
output             fifo_full, fifo_empty;

(* anyseq *) wire [width-1:0] free_data;
(* anyseq *) wire             free_full, free_empty;
assign data_out_clk2 = free_data;
assign fifo_full     = free_full;
assign fifo_empty    = free_empty;
endmodule

module fp4_dot_unit(clk, rst, va, vb, dot_out);
input         clk, rst;
input  [31:0] va, vb;
output [31:0] dot_out;
(* anyseq *) wire [31:0] free_dot;
assign dot_out = free_dot;
endmodule
