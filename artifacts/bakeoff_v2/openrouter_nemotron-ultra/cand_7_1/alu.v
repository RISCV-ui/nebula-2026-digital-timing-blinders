`timescale 1ns / 1ps


module alu (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] src_a,
    input  wire [31:0] src_b,
    input  wire [3:0]  alu_control,
    output reg  [31:0] alu_result,
    output reg         zero
);

    localparam ADD  = 4'b0000;
    localparam SUB  = 4'b1000;
    localparam SLT  = 4'b0010;
    localparam SLTU = 4'b0011;
    localparam XOR  = 4'b0100;
    localparam SLL  = 4'b0001;
    localparam SRL  = 4'b0101;
    localparam SRA  = 4'b1101;
    localparam OR   = 4'b0110;
    localparam AND  = 4'b0111;
    localparam DIVU = 4'b1001;
    localparam REMU = 4'b1011;

    wire [31:0] div_quotient;
    wire [31:0] div_remainder;

    div_restoring_32 alu_div(
        .dividend  (src_a),
        .divisor   (src_b),
        .quotient  (div_quotient),
        .remainder (div_remainder)
    );

    reg [31:0] next_alu_result;
    reg        next_zero;

    always @(*) begin
        case (alu_control)
            ADD:  next_alu_result = src_a + src_b;
            SUB:  next_alu_result = src_a - src_b;
            SLT:  next_alu_result = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;
            SLTU: next_alu_result = (src_a < src_b) ? 32'd1 : 32'd0;
            XOR:  next_alu_result = src_a ^ src_b;
            SLL:  next_alu_result = src_a << src_b[4:0];
            SRL:  next_alu_result = src_a >> src_b[4:0];
            SRA:  next_alu_result = $signed(src_a) >>> src_b[4:0];
            OR:   next_alu_result = src_a | src_b;
            AND:  next_alu_result = src_a & src_b;
            DIVU: next_alu_result = div_quotient;
            REMU: next_alu_result = div_remainder;
            default: next_alu_result = 32'd0;
        endcase
        next_zero = (next_alu_result == 32'd0);
    end

    always @(posedge clk) begin
        alu_result <= next_alu_result;
        zero <= next_zero;
    end
endmodule
