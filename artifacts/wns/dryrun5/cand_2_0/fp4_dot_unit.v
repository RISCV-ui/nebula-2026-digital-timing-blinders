`timescale 1ns / 1ps


module fp4_dot_unit(clk, rst, en, va, vb, dot_out);

input        clk, rst, en;
input [31:0] va, vb;
output [31:0] dot_out;

wire [7:0] y_0, y_1, y_2, y_3, y_4, y_5, y_6, y_7;
wire [7:0] add_0, add_1, add_2, add_3;
wire [7:0] add_4, add_5;
wire [7:0] y;

// stage registers
reg [7:0] s0_y0, s0_y1, s0_y2, s0_y3, s0_y4, s0_y5, s0_y6, s0_y7;
reg [7:0] s1_a0, s1_a1, s1_a2, s1_a3;
reg [7:0] s2_a4, s2_a5;
reg [7:0] s3_y;

assign dot_out = {24'd0, s3_y};

// ---- stage 0: 8 FP4 multipliers ----------------------------------------
fp4_mul fp4_0 (va[3:0],   vb[3:0],   y_0);
fp4_mul fp4_1 (va[7:4],   vb[7:4],   y_1);
fp4_mul fp4_2 (va[11:8],  vb[11:8],  y_2);
fp4_mul fp4_3 (va[15:12], vb[15:12], y_3);
fp4_mul fp4_4 (va[19:16], vb[19:16], y_4);
fp4_mul fp4_5 (va[23:20], vb[23:20], y_5);
fp4_mul fp4_6 (va[27:24], vb[27:24], y_6);
fp4_mul fp4_7 (va[31:28], vb[31:28], y_7);

// ---- stage 1: adder level 1 --------------------------------------------
fp8_adder add0 (s0_y0, s0_y1, add_0);
fp8_adder add1 (s0_y2, s0_y3, add_1);
fp8_adder add2 (s0_y4, s0_y5, add_2);
fp8_adder add3 (s0_y6, s0_y7, add_3);

// ---- stage 2: adder level 2 --------------------------------------------
fp8_adder add4 (s1_a0, s1_a1, add_4);
fp8_adder add5 (s1_a2, s1_a3, add_5);

// ---- stage 3: adder level 3 --------------------------------------------
fp8_adder add6 (s2_a4, s2_a5, y);

always @(posedge clk) begin
    if (rst) begin
        s0_y0 <= 8'd0; s0_y1 <= 8'd0; s0_y2 <= 8'd0; s0_y3 <= 8'd0;
        s0_y4 <= 8'd0; s0_y5 <= 8'd0; s0_y6 <= 8'd0; s0_y7 <= 8'd0;
        s1_a0 <= 8'd0; s1_a1 <= 8'd0; s1_a2 <= 8'd0; s1_a3 <= 8'd0;
        s2_a4 <= 8'd0; s2_a5 <= 8'd0;
        s3_y  <= 8'd0;
    end
    else if (en) begin
        s0_y0 <= y_0; s0_y1 <= y_1; s0_y2 <= y_2; s0_y3 <= y_3;
        s0_y4 <= y_4; s0_y5 <= y_5; s0_y6 <= y_6; s0_y7 <= y_7;
        s1_a0 <= add_0; s1_a1 <= add_1; s1_a2 <= add_2; s1_a3 <= add_3;
        s2_a4 <= add_4; s2_a5 <= add_5;
        s3_y  <= y;
    end
end

endmodule
