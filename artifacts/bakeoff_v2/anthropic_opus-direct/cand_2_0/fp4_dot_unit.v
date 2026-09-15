`timescale 1ns / 1ps


module fp4_dot_unit(clk, rst, va ,vb , dot_out  );
                    
input clk,rst ;
input [31:0]va,vb ;
output [31:0]dot_out;             

wire [7:0] y_0,y_1,y_2,y_3,y_4,y_5,y_6,y_7,y;
wire [7:0] add_0,add_1,add_2,add_3;
wire [7:0] add_4,add_5;

// pipeline registers: stage 1 after the multipliers, stage 2 after adder
// level 1, stage 3 after adder level 2.  No reset: these are feed-forward
// datapath stages and hold no recoverable state.
reg [7:0] y0_q,y1_q,y2_q,y3_q,y4_q,y5_q,y6_q,y7_q;
reg [7:0] add0_q,add1_q,add2_q,add3_q;
reg [7:0] add4_q,add5_q;

assign dot_out = { 24'd0, y};

// 8 FP4 multipliers  -- stage 0 logic
fp4_mul fp4_0 (va[3:0],   vb[3:0],   y_0);
fp4_mul fp4_1 (va[7:4],   vb[7:4],   y_1);
fp4_mul fp4_2 (va[11:8],  vb[11:8],  y_2);
fp4_mul fp4_3 (va[15:12], vb[15:12], y_3);
fp4_mul fp4_4 (va[19:16], vb[19:16], y_4);
fp4_mul fp4_5 (va[23:20], vb[23:20], y_5);
fp4_mul fp4_6 (va[27:24], vb[27:24], y_6);
fp4_mul fp4_7 (va[31:28], vb[31:28], y_7);

always @(posedge clk)
begin
    y0_q <= y_0;
    y1_q <= y_1;
    y2_q <= y_2;
    y3_q <= y_3;
    y4_q <= y_4;
    y5_q <= y_5;
    y6_q <= y_6;
    y7_q <= y_7;
end

// Level 1  -- stage 1 logic
fp8_adder add0 (y0_q, y1_q, add_0);
fp8_adder add1 (y2_q, y3_q, add_1);
fp8_adder add2 (y4_q, y5_q, add_2);
fp8_adder add3 (y6_q, y7_q, add_3);

always @(posedge clk)
begin
    add0_q <= add_0;
    add1_q <= add_1;
    add2_q <= add_2;
    add3_q <= add_3;
end

// Level 2  -- stage 2 logic
fp8_adder add4 (add0_q, add1_q, add_4);
fp8_adder add5 (add2_q, add3_q, add_5);

always @(posedge clk)
begin
    add4_q <= add_4;
    add5_q <= add_5;
end

// Level 3  -- stage 3 logic
fp8_adder add6 (add4_q, add5_q, y);

// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     rst,
                     1'b0};

endmodule
