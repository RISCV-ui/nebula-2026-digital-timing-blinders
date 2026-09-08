`timescale 1ns / 1ps


module alu (
    input  wire [31:0] src_a,
    input  wire [31:0] src_b,
    input  wire [3:0]  alu_control,
    output reg  [31:0] alu_result,
    output wire        zero
);

    localparam ADD  = 4'b0000;  /// i have changed to [f7[5],fun3] format 
    localparam SUB  = 4'b1000;
    localparam SLT  = 4'b0010;
    localparam SLTU = 4'b0011;
    localparam XOR  = 4'b0100;
    localparam SLL  = 4'b0001;
    localparam SRL  = 4'b0101;
    localparam SRA  = 4'b1101;
    localparam OR   = 4'b0110;
    localparam AND  = 4'b0111;

    always @(*) begin
        case (alu_control)

            ADD:
                alu_result = src_a + src_b;



            SUB:
                alu_result = src_a - src_b;

            SLT:
                alu_result = ($signed(src_a) < $signed(src_b))
                             ? 32'd1 : 32'd0;

            SLTU:
                alu_result = (src_a < src_b)
                             ? 32'd1 : 32'd0;

            XOR:
                alu_result = src_a ^ src_b;

            SLL:
                alu_result = src_a << src_b[4:0];

            SRL:
                alu_result = src_a >> src_b[4:0];

            SRA:
                alu_result = $signed(src_a) >>> src_b[4:0];

            OR:
                alu_result = src_a | src_b;

            AND:
                alu_result = src_a & src_b;

            default:
                alu_result = 32'd0;

        endcase
    end

    assign zero = (alu_result == 32'd0);

endmodule
