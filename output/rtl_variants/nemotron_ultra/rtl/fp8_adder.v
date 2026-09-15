`timescale 1ns / 1ps



module fp8_adder(a, b, y);

input  [7:0] a, b;
output reg [7:0] y;

///// wire declaration
wire signed [5:0] exp_a, exp_b;
wire [3:0] mant_a, mant_b;

///// reg declaration
reg [3:0] shift_a, shift_b;
reg signed [5:0] exp_diff;
reg [9:0] mant_a_reg, mant_b_reg, a_operand, b_operand;
reg [10:0] sum_mant;
reg [10:0] sum_mant_norm;
reg found;
reg [4:0] leading_1_index;
reg [5:0] norm_shift;
reg signed [6:0] exp_final_2, exp_final, exp_round;
reg sing_reg;
reg a_grater_reg, b_grater_reg;
reg [5:0] mant_rount;
reg sticky_a, sticky_b;

///// assign
assign exp_a = (a[6:3] == 4'd0) ? 6'sd1 : $signed({2'b00, a[6:3]});
assign exp_b = (b[6:3] == 4'd0) ? 6'sd1 : $signed({2'b00, b[6:3]});
assign mant_a = {(a[6:3] != 4'd0), a[2:0]};
assign mant_b = {(b[6:3] != 4'd0), b[2:0]};

///// combinational logic
always @(*)
begin
    // defaults
    shift_a         = 4'd0;
    shift_b         = 4'd0;
    y               = 8'd0;
    mant_a_reg      = 10'd0;
    mant_b_reg      = 10'd0;
    a_operand       = 10'd0;
    b_operand       = 10'd0;
    sum_mant        = 11'd0;
    sum_mant_norm   = 11'd0;
    found           = 1'b0;
    leading_1_index = 5'd0;
    norm_shift      = 6'd0;
    exp_final       = 7'sd0;
    exp_final_2     = 7'sd0;
    sing_reg        = 1'b0;
    a_grater_reg    = 1'b0;
    b_grater_reg    = 1'b0;
    mant_rount      = 6'd0;
    exp_round       = 7'sd0;
    sticky_a        = 1'b0;
    sticky_b        = 1'b0;
    exp_diff        = 6'sd0;

    // Special cases
    if (a[6:0] == 7'd0 && b[6:0] == 7'd0) begin
        y = (a[7] & b[7]) ? {1'b1,7'd0} : {1'b0,7'd0};
    end else if (a[6:0] == 7'd0) begin
        y = b;
    end else if (b[6:0] == 7'd0) begin
        y = a;
    end else if (a[7] != b[7] && b[6:0] == a[6:0]) begin
        y = 0;
    end else if (a[6:0] == 7'b1111111) begin
        y = {a[7], 7'b1111111};
    end else if (b[6:0] == 7'b1111111) begin
        y = {b[7], 7'b1111111};
    end else if ((a[6:3] == 4'b1111 && b[6:3] == 4'b1111) && a[2:0] + b[2:0] > 15) begin
        y = {a[7], 7'b1111111};
    end else begin
        // Exponent alignment
        if (exp_a > exp_b) begin
            exp_diff     = exp_a - exp_b;
            shift_a      = exp_diff[3:0];
            a_grater_reg = 1'b1;
        end else if (exp_b > exp_a) begin
            exp_diff     = exp_b - exp_a;
            shift_b      = exp_diff[3:0];
            b_grater_reg = 1'b1;
        end

        // Sticky bits computation
        sticky_a = (shift_b == 4'd0) ? 1'b0 :
                   (shift_b >= 4'd8) ? |{mant_a, 4'd0} :
                   |(({mant_a, 4'd0}) & (8'hFF >> (8 - shift_b)));
        sticky_b = (shift_a == 4'd0) ? 1'b0 :
                   (shift_a >= 4'd8) ? |{mant_b, 4'd0} :
                   |(({mant_b, 4'd0}) & (8'hFF >> (8 - shift_a)));

        // Aligned mantissas
        mant_a_reg = b_grater_reg ? {2'b00, (({mant_a, 4'd0}) >> shift_b) | {7'b0, sticky_a}} : {2'b00, {mant_a, 4'd0}};
        mant_b_reg = a_grater_reg ? {2'b00, (({mant_b, 4'd0}) >> shift_a) | {7'b0, sticky_b}} : {2'b00, {mant_b, 4'd0}};

        // Operand selection for addition/subtraction
        a_operand = ((b[6:0] > a[6:0]) && (a[7] ^ b[7])) ? (~mant_a_reg) : mant_a_reg;
        b_operand = ((a[6:0] > b[6:0]) && (a[7] ^ b[7])) ? (~mant_b_reg) : mant_b_reg;
        sum_mant  = a_operand + b_operand + {10'b0, (a[7] ^ b[7])};

        // Sign determination
        sing_reg = (a[7] == b[7]) ? a[7] : ((a[6:0] >= b[6:0]) ? a[7] : b[7]);

        // Leading one detector (casez for shallow logic)
        casez (sum_mant[8:0])
            9'b1????????: leading_1_index = 5'd8;
            9'b01???????: leading_1_index = 5'd7;
            9'b001??????: leading_1_index = 5'd6;
            9'b0001?????: leading_1_index = 5'd5;
            9'b00001????: leading_1_index = 5'd4;
            9'b000001???: leading_1_index = 5'd3;
            9'b0000001??: leading_1_index = 5'd2;
            9'b00000001?: leading_1_index = 5'd1;
            9'b000000001: leading_1_index = 5'd0;
            default:      leading_1_index = 5'd0;
        endcase
        found = |sum_mant[8:0];

        // Normalization
        if (found) begin
            if ((a[6:3] != 4'd0) || (b[6:3] != 4'd0)) begin
                if (leading_1_index > 7) begin
                    norm_shift    = leading_1_index - 7;
                    exp_final     = a_grater_reg ? exp_a + norm_shift : exp_b + norm_shift;
                    sum_mant_norm = sum_mant >> norm_shift;
                    exp_final_2   = exp_final;
                end else if (leading_1_index < 7) begin
                    norm_shift = 7 - leading_1_index;
                    exp_final  = a_grater_reg ? exp_a - norm_shift : exp_b - norm_shift;
                    if (exp_final <= 0) begin
                        sum_mant_norm = sum_mant << ((a_grater_reg ? exp_a : exp_b) - 1);
                        exp_final_2   = 0;
                    end else begin
                        sum_mant_norm = sum_mant << norm_shift;
                        exp_final_2   = exp_final;
                    end
                end else begin
                    norm_shift     = 0;
                    sum_mant_norm  = sum_mant;
                    exp_final_2    = (exp_a >= exp_b) ? {exp_a[5], exp_a} : {exp_b[5], exp_b};
                end
            end else begin
                sum_mant_norm = sum_mant;
                if (leading_1_index >= 7)
                    exp_final_2 = $signed({2'b00, leading_1_index}) - 7'sd6;
            end
        end

        // Rounding
        if (exp_final_2 == 0)
            mant_rount = {2'b00, sum_mant_norm[7:4]};
        else
            mant_rount = {2'b00, sum_mant_norm[7:4]} + {5'b0, (sum_mant_norm[3] & (sum_mant_norm[2] | sum_mant_norm[1] | sum_mant_norm[0] | sum_mant_norm[4]))};

        exp_round = (mant_rount[4] == 1'b1) ? exp_final_2 + 1 : exp_final_2;

        if (exp_round > 15)
            y = {sing_reg, 7'b1111111};
        else
            y = {sing_reg, exp_round[3:0], mant_rount[2:0]};
    end
end

// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     exp_diff[5:4], sum_mant_norm[10:8], mant_rount[5], mant_rount[3],
                     1'b0};

endmodule
