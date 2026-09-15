// Baseline r_en driver, lifted verbatim from the frozen axi_lite_dot.v:
//     assign r_en_1 = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);
module ren_gold(empty_1, empty_2, full, vld, r_en_1, r_en_2);
input  empty_1, empty_2, full;
input [3:0] vld;              // free input: baseline does not use it
output r_en_1, r_en_2;
assign r_en_1 = (!empty_1 && !empty_2 && !full);
assign r_en_2 = (!empty_1 && !empty_2 && !full);
endmodule

// Candidate r_en driver, lifted verbatim from fp4_dot_stage.v.
module ren_gate(empty_1, empty_2, full, vld, r_en_1, r_en_2);
input  empty_1, empty_2, full;
input [3:0] vld;
output r_en_1, r_en_2;
wire src  = (!empty_1 && !empty_2);
wire room = !full;
wire adv  = room && (src || |vld);
assign r_en_1 = adv && src;
assign r_en_2 = adv && src;
endmodule

// Miter: asserts high if the two drivers ever disagree, for ANY value of the
// pipeline-occupancy vector vld. A SAT model here is a counterexample.
module miter(empty_1, empty_2, full, vld, differ);
input  empty_1, empty_2, full;
input [3:0] vld;
output differ;
wire g1, g2, c1, c2;
ren_gold u_gold(empty_1, empty_2, full, vld, g1, g2);
ren_gate u_gate(empty_1, empty_2, full, vld, c1, c2);
assign differ = (g1 ^ c1) | (g2 ^ c2);
endmodule
