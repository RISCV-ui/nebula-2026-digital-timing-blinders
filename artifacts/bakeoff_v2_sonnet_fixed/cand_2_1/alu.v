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
    // Unsigned divide and remainder. The {f7[5],funct3} encoding the
    // rest of this table uses cannot reach the M-extension codes --
    // DIVU would collapse onto SRL -- so decode assigns these two out
    // of the unused half of the space.
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

            DIVU:
                alu_result = div_quotient;

            REMU:
                alu_result = div_remainder;

            default:
                alu_result = 32'd0;

        endcase
    end

    assign zero = (alu_result == 32'd0);

endmodule
