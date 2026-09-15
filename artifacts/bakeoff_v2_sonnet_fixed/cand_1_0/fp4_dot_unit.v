`timescale 1ns / 1ps


module fp4_dot_unit(clk, rst, va ,vb , dot_out  );


input clk,rst ;
input [31:0]va,vb ;
output [31:0]dot_out;             



wire [7:0] y_0,y_1,y_2,y_3,y_4,y_5,y_6,y_7,y;
wire [7:0] add_0,add_1,add_2,add_3;
wire [7:0] add_4,add_5;

reg [7:0] add_0_r, add_1_r, add_2_r, add_3_r;
reg [7:0] add_4_r, add_5_r;

assign dot_out = { 24'd0, y};

// 8 FP4 multipliers
fp4_mul fp4_0 (va[3:0],   vb[3:0],   y_0);
fp4_mul fp4_1 (va[7:4],   vb[7:4],   y_1);
fp4_mul fp4_2 (va[11:8],  vb[11:8],  y_2);
fp4_mul fp4_3 (va[15:12], vb[15:12], y_3);
fp4_mul fp4_4 (va[19:16], vb[19:16], y_4);
fp4_mul fp4_5 (va[23:20], vb[23:20], y_5);
fp4_mul fp4_6 (va[27:24], vb[27:24], y_6);
fp4_mul fp4_7 (va[31:28], vb[31:28], y_7);

// Level 1
fp8_adder add0 (y_0, y_1, add_0);
fp8_adder add1 (y_2, y_3, add_1);
fp8_adder add2 (y_4, y_5, add_2);
fp8_adder add3 (y_6, y_7, add_3);

// Pipeline stage 1: register the level-1 sums so level-2 addition
// starts on a fresh cycle instead of chaining straight off level-1.
always @(posedge clk) begin
    add_0_r <= add_0;
    add_1_r <= add_1;
    add_2_r <= add_2;
    add_3_r <= add_3;
end

// Level 2
fp8_adder add4 (add_0_r, add_1_r, add_4);
fp8_adder add5 (add_2_r, add_3_r, add_5);

// Pipeline stage 2: register the level-2 sums so the final add
// starts on a fresh cycle.
always @(posedge clk) begin
    add_4_r <= add_4;
    add_5_r <= add_5;
end

// Level 3
fp8_adder add6 (add_4_r, add_5_r, y);



// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     rst,
                     1'b0};

endmodule
