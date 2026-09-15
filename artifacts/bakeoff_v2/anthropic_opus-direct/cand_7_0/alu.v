`timescale 1ns / 1ps


module alu (
    input  wire        clk,
    input  wire [31:0] src_a,
    input  wire [31:0] src_b,
    input  wire [3:0]  alu_control,
    output wire [31:0] alu_result,
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
    localparam DIVU = 4'b1001;
    localparam REMU = 4'b1011;

    // ------------------------------------------------------------------
    // 32 step unsigned restoring divider, one restore step per pipeline
    // stage.  Same recurrence as the flat div_restoring_32 it replaces:
    // remainder is shifted left by one dividend bit, compared against the
    // divisor and conditionally reduced; the quotient bit shifts into the
    // low end of the dividend register.  Divisor 0 falls out as
    // quotient = 32'hFFFFFFFF, remainder = dividend, as before.
    // ------------------------------------------------------------------

    wire [32:0] rem_in [0:32];
    wire [31:0] qd_in  [0:32];
    wire [31:0] den_in [0:32];

    reg  [32:0] rem_r  [0:31];
    reg  [31:0] qd_r   [0:31];
    reg  [31:0] den_r  [0:31];

    assign rem_in[0] = 33'd0;
    assign qd_in[0]  = src_a;
    assign den_in[0] = src_b;

    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : div_stage
            wire [32:0] sh = {rem_in[g][31:0], qd_in[g][31]};
            wire        ge = (sh >= {1'b0, den_in[g]});

            always @(posedge clk) begin
                rem_r[g] <= ge ? (sh - {1'b0, den_in[g]}) : sh;
                qd_r[g]  <= {qd_in[g][30:0], ge};
                den_r[g] <= den_in[g];
            end

            assign rem_in[g+1] = rem_r[g];
            assign qd_in[g+1]  = qd_r[g];
            assign den_in[g+1] = den_r[g];
        end
    endgenerate

    wire [31:0] div_quotient  = qd_in[32];
    wire [31:0] div_remainder = rem_in[32][31:0];

    // ------------------------------------------------------------------
    // the cheap operations stay combinational and are carried forward
    // through the same 32 stages so that every ALU output moves together
    // ------------------------------------------------------------------

    reg [31:0] comb_result;

    always @(*) begin
        case (alu_control)
            ADD:     comb_result = src_a + src_b;
            SUB:     comb_result = src_a - src_b;
            SLT:     comb_result = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;
            SLTU:    comb_result = (src_a < src_b) ? 32'd1 : 32'd0;
            XOR:     comb_result = src_a ^ src_b;
            SLL:     comb_result = src_a << src_b[4:0];
            SRL:     comb_result = src_a >> src_b[4:0];
            SRA:     comb_result = $signed(src_a) >>> src_b[4:0];
            OR:      comb_result = src_a | src_b;
            AND:     comb_result = src_a & src_b;
            DIVU:    comb_result = 32'd0;
            REMU:    comb_result = 32'd0;
            default: comb_result = 32'd0;
        endcase
    end

    wire is_divu = (alu_control == DIVU);
    wire is_remu = (alu_control == REMU);

    reg [31:0] cr_d   [0:31];
    reg        divu_d [0:31];
    reg        remu_d [0:31];

    integer i;
    always @(posedge clk) begin
        cr_d[0]   <= comb_result;
        divu_d[0] <= is_divu;
        remu_d[0] <= is_remu;
        for (i = 1; i < 32; i = i + 1) begin
            cr_d[i]   <= cr_d[i-1];
            divu_d[i] <= divu_d[i-1];
            remu_d[i] <= remu_d[i-1];
        end
    end

    assign alu_result = divu_d[31] ? div_quotient :
                        remu_d[31] ? div_remainder :
                                     cr_d[31];

    assign zero = (alu_result == 32'd0);

endmodule
