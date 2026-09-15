`timescale 1ns / 1ps


module fp4_dot_unit(clk, rst, va ,vb , dot_out, dot_valid );
                   
                   
input clk,rst ;
input [31:0]va,vb ;
output [31:0]dot_out;
output dot_valid;


wire [7:0] y_0,y_1,y_2,y_3,y_4,y_5,y_6,y_7;
wire [7:0] add_0,add_1,add_2,add_3;
wire [7:0] add_4,add_5;
wire [7:0] y;

// 8 FP4 multipliers
fp4_mul fp4_0 (va[3:0],   vb[3:0],   y_0);
fp4_mul fp4_1 (va[7:4],   vb[7:4],   y_1);
fp4_mul fp4_2 (va[11:8],  vb[11:8],  y_2);
fp4_mul fp4_3 (va[15:12], vb[15:12], y_3);
fp4_mul fp4_4 (va[19:16], vb[19:16], y_4);
fp4_mul fp4_5 (va[23:20], vb[23:20], y_5);
fp4_mul fp4_6 (va[27:24], vb[27:24], y_6);
fp4_mul fp4_7 (va[31:28], vb[31:28], y_7);

// Level 1 adders (combinational)
fp8_adder add0 (y_0, y_1, add_0);
fp8_adder add1 (y_2, y_3, add_1);
fp8_adder add2 (y_4, y_5, add_2);
fp8_adder add3 (y_6, y_7, add_3);

// Pipeline stage 1: after level 1 adders
reg [7:0] add_0_s1, add_1_s1, add_2_s1, add_3_s1;
always @(posedge clk) begin
    if (rst) begin
        add_0_s1 <= 8'd0; add_1_s1 <= 8'd0; add_2_s1 <= 8'd0; add_3_s1 <= 8'd0;
    end else begin
        add_0_s1 <= add_0; add_1_s1 <= add_1; add_2_s1 <= add_2; add_3_s1 <= add_3;
    end
end

// Level 2 adders (combinational)
fp8_adder add4 (add_0_s1, add_1_s1, add_4);
fp8_adder add5 (add_2_s1, add_3_s1, add_5);

// Pipeline stage 2: after level 2 adders
reg [7:0] add_4_s2, add_5_s2;
always @(posedge clk) begin
    if (rst) begin
        add_4_s2 <= 8'd0; add_5_s2 <= 8'd0;
    end else begin
        add_4_s2 <= add_4; add_5_s2 <= add_5;
    end
end

// Level 3 adder (combinational)
fp8_adder add6 (add_4_s2, add_5_s2, y);

// Pipeline stage 3: output register
reg [7:0] y_s3;
reg valid_s1, valid_s2, valid_s3;
always @(posedge clk) begin
    if (rst) begin
        y_s3 <= 8'd0;
        valid_s1 <= 1'b0; valid_s2 <= 1'b0; valid_s3 <= 1'b0;
    end else begin
        y_s3 <= y;
        valid_s1 <= 1'b1;
        valid_s2 <= valid_s1;
        valid_s3 <= valid_s2;
    end
end

assign dot_out = { 24'd0, y_s3 };
assign dot_valid = valid_s3;


// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     1'b0};

endmodule
