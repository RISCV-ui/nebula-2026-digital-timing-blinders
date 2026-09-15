`timescale 1ns / 1ps

// ===================================================================
//  clk_div_mux -- glitch-free 1/2/4/8 clock divider select
//
//  Software picks the divide ratio through `sel`, which means the select
//  can change at any time, including in the middle of a pulse on the
//  branch currently driving the output. A plain `case` over four clocks
//  truncates that pulse, and a truncated clock pulse is a runt: too short
//  to meet setup on the flops it feeds, wide enough for some of them to
//  latch it anyway.
//
//  The standard fix, implemented here, is a handover rather than a select:
//
//    - each branch has its own two-stage enable chain, clocked by that
//      branch's own clock, so a branch can only turn on or off on its own
//      edges;
//    - a branch may only turn ON once every other branch reports OFF, so
//      two branches are never enabled at the same time;
//    - the second stage of each chain samples on the FALLING edge, so the
//      AND gate in front of the output only ever changes while that
//      branch's clock is low.
//
//  Together those give the same property the ICG gives: whatever comes out
//  is whole pulses of exactly one source. The cost is that a switch takes a
//  few cycles of the old and new clocks to complete, which is what makes it
//  safe -- the output stops cleanly before it restarts.
//
//  Ports and behaviour under a fixed `sel` are identical to the previous
//  combinational version, so soc_top and the SDC are unchanged.
// ===================================================================
module clk_div_mux(
    clk,
    rst,
    sel,
    clk_out
    );

input  clk;
input  rst;
input  [1:0] sel;

output clk_out;

reg [2:0] clk_div;

always @(posedge clk)
begin
    if (rst)
        clk_div <= 3'b000;
    else
        clk_div <= clk_div + 1'b1;
end

wire clk_div2 = clk_div[0];
wire clk_div4 = clk_div[1];
wire clk_div8 = clk_div[2];

// One request bit per branch. Exactly one is ever high.
wire req0 = (sel == 2'b00);
wire req1 = (sel == 2'b01);
wire req2 = (sel == 2'b10);
wire req3 = (sel == 2'b11);

// Enable chains. q1 rises on its branch's rising edge once every other
// branch has released; q2 follows on the falling edge, so the output AND
// only switches while that branch's clock is low.
reg q1_0, q2_0;
reg q1_1, q2_1;
reg q1_2, q2_2;
reg q1_3, q2_3;

// Reset parks the mux on branch 0 -- the undivided clock -- so the design
// comes out of reset already clocked rather than waiting for a handover.
always @(posedge clk or posedge rst)
    if (rst) q1_0 <= 1'b1;
    else     q1_0 <= req0 & ~q2_1 & ~q2_2 & ~q2_3;

always @(negedge clk or posedge rst)
    if (rst) q2_0 <= 1'b1;
    else     q2_0 <= q1_0;

always @(posedge clk_div2 or posedge rst)
    if (rst) q1_1 <= 1'b0;
    else     q1_1 <= req1 & ~q2_0 & ~q2_2 & ~q2_3;

always @(negedge clk_div2 or posedge rst)
    if (rst) q2_1 <= 1'b0;
    else     q2_1 <= q1_1;

always @(posedge clk_div4 or posedge rst)
    if (rst) q1_2 <= 1'b0;
    else     q1_2 <= req2 & ~q2_0 & ~q2_1 & ~q2_3;

always @(negedge clk_div4 or posedge rst)
    if (rst) q2_2 <= 1'b0;
    else     q2_2 <= q1_2;

always @(posedge clk_div8 or posedge rst)
    if (rst) q1_3 <= 1'b0;
    else     q1_3 <= req3 & ~q2_0 & ~q2_1 & ~q2_2;

always @(negedge clk_div8 or posedge rst)
    if (rst) q2_3 <= 1'b0;
    else     q2_3 <= q1_3;

assign clk_out = (clk      & q2_0)
               | (clk_div2 & q2_1)
               | (clk_div4 & q2_2)
               | (clk_div8 & q2_3);

endmodule
