`timescale 1ns / 1ps


module alu (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] src_a,
    input  wire [31:0] src_b,
    input  wire [3:0]  alu_control,
    output reg  [31:0] alu_result,
    output wire        zero
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

    // Combinational ALU for non-divide operations
    wire [31:0] alu_result_comb;
    reg  [31:0] div_quotient_reg, div_remainder_reg;
    reg  [5:0]  div_state; // 0=idle, 1-32=running
    reg  [31:0] div_dividend, div_divisor;
    reg  [31:0] div_rem, div_quot;
    reg  [5:0]  div_cnt;
    wire [31:0] div_sub = div_rem - div_divisor;
    wire        div_ge  = (div_rem >= div_divisor);

    always @(*) begin
        case (alu_control)
            ADD:  alu_result_comb = src_a + src_b;
            SUB:  alu_result_comb = src_a - src_b;
            SLT:  alu_result_comb = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;
            SLTU: alu_result_comb = (src_a < src_b) ? 32'd1 : 32'd0;
            XOR:  alu_result_comb = src_a ^ src_b;
            SLL:  alu_result_comb = src_a << src_b[4:0];
            SRL:  alu_result_comb = src_a >> src_b[4:0];
            SRA:  alu_result_comb = $signed(src_a) >>> src_b[4:0];
            OR:   alu_result_comb = src_a | src_b;
            AND:  alu_result_comb = src_a & src_b;
            default: alu_result_comb = 32'd0;
        endcase
    end

    // Sequential restoring divider
    always @(posedge clk) begin
        if (rst) begin
            div_state         <= 6'd0;
            div_quotient_reg  <= 32'd0;
            div_remainder_reg <= 32'd0;
        end else begin
            case (alu_control)
                DIVU, REMU: begin
                    if (div_state == 6'd0) begin
                        div_dividend <= src_a;
                        div_divisor  <= src_b;
                        div_rem      <= 32'd0;
                        div_quot     <= src_a;
                        div_cnt      <= 6'd0;
                        div_state    <= 6'd1;
                    end else if (div_state < 6'd32) begin
                        {div_rem, div_quot} <= {div_rem, div_quot} << 1;
                        if (div_ge) begin
                            div_rem  <= div_sub;
                            div_quot <= div_quot | 1;
                        end
                        div_cnt   <= div_cnt + 1;
                        div_state <= div_state + 1;
                    end else begin
                        div_quotient_reg  <= div_quot;
                        div_remainder_reg <= div_rem;
                        div_state         <= 6'd0;
                    end
                end
                default: begin
                    div_state <= 6'd0;
                end
            endcase
        end
    end

    always @(*) begin
        case (alu_control)
            DIVU: alu_result = div_quotient_reg;
            REMU: alu_result = div_remainder_reg;
            default: alu_result = alu_result_comb;
        endcase
    end

    assign zero = (alu_result == 32'd0);

endmodule
