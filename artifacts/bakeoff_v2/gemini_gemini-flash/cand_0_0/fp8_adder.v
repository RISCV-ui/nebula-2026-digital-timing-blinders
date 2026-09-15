`timescale 1ns / 1ps



module fp8_adder(a, b, y);

input  [7:0] a, b;
output reg [7:0] y;

wire signed [5:0] exp_a = (a[6:3] == 4'd0) ? 6'sd1 : $signed({2'b00, a[6:3]});
wire signed [5:0] exp_b = (b[6:3] == 4'd0) ? 6'sd1 : $signed({2'b00, b[6:3]});

wire [3:0] mant_a = {(a[6:3] != 4'd0), a[2:0]};
wire [3:0] mant_b = {(b[6:3] != 4'd0), b[2:0]};

wire signed [5:0] exp_diff_a_b = exp_a - exp_b;
wire signed [5:0] exp_diff_b_a = exp_b - exp_a;

wire exp_a_gt_b = (exp_a > exp_b);
wire exp_b_gt_a = (exp_b > exp_a);

wire [3:0] shift_a_w = exp_b_gt_a ? (exp_diff_b_a > 6'sd8 ? 4'd8 : exp_diff_b_a[3:0]) : 4'd0;
wire [3:0] shift_b_w = exp_a_gt_b ? (exp_diff_a_b > 6'sd8 ? 4'd8 : exp_diff_a_b[3:0]) : 4'd0;

wire sticky_a_w = (shift_b_w == 4'd5) ? mant_a[0] :
                  (shift_b_w == 4'd6) ? |mant_a[1:0] :
                  (shift_b_w == 4'd7) ? |mant_a[2:0] :
                  (shift_b_w >= 4'd8) ? |mant_a : 1'b0;

wire sticky_b_w = (shift_a_w == 4'd5) ? mant_b[0] :
                  (shift_a_w == 4'd6) ? |mant_b[1:0] :
                  (shift_a_w == 4'd7) ? |mant_b[2:0] :
                  (shift_a_w >= 4'd8) ? |mant_b : 1'b0;

wire [7:0] mant_a_shifted = ({mant_a, 4'd0} >> shift_b_w) | {7'b0, sticky_a_w};
wire [7:0] mant_b_shifted = ({mant_b, 4'd0} >> shift_a_w) | {7'b0, sticky_b_w};

wire a_grater_reg = exp_a_gt_b;
wire b_grater_reg = exp_b_gt_a;

wire [9:0] mant_a_reg_w = b_grater_reg ? {2'b00, mant_a_shifted} : {2'b00, mant_a, 4'd0};
wire [9:0] mant_b_reg_w = a_grater_reg ? {2'b00, mant_b_shifted} : {2'b00, mant_b, 4'd0};

wire [9:0] a_operand_w = ((b[6:0] > a[6:0]) && (a[7] ^ b[7])) ? (~mant_a_reg_w) : mant_a_reg_w;
wire [9:0] b_operand_w = ((a[6:0] > b[6:0]) && (a[7] ^ b[7])) ? (~mant_b_reg_w) : mant_b_reg_w;
wire [10:0] sum_mant = a_operand_w + b_operand_w + {10'b0, (a[7] ^ b[7])};

wire sing_reg_w = (a[7] == b[7]) ? a[7] : ((a[6:0] >= b[6:0]) ? a[7] : b[7]);

wire [8:0] sum_mant_9 = sum_mant[8:0];
wire found_w = |sum_mant_9;
wire [4:0] leading_1_index_w = sum_mant_9[8] ? 5'd8 :
                               sum_mant_9[7] ? 5'd7 :
                               sum_mant_9[6] ? 5'd6 :
                               sum_mant_9[5] ? 5'd5 :
                               sum_mant_9[4] ? 5'd4 :
                               sum_mant_9[3] ? 5'd3 :
                               sum_mant_9[2] ? 5'd2 :
                               sum_mant_9[1] ? 5'd1 :
                               sum_mant_9[0] ? 5'd0 : 5'd0;

wire is_subnormal = (a[6:3] == 4'd0) && (b[6:3] == 4'd0);
wire signed [5:0] exp_base = a_grater_reg ? exp_a : exp_b;
wire signed [6:0] exp_base_7 = $signed(exp_base);
wire [2:0] shift_val = 3'd7 - leading_1_index_w[2:0];
wire signed [6:0] shift_val_signed = $signed({4'b0000, shift_val});

reg [10:0] sum_mant_norm_w;
reg signed [6:0] exp_final_2_w;

always @(*) begin
    sum_mant_norm_w = 11'd0;
    exp_final_2_w = 7'sd0;
    if (found_w) begin
        if (is_subnormal) begin
            sum_mant_norm_w = sum_mant;
            if (leading_1_index_w >= 5'd7)
                exp_final_2_w = $signed({2'b00, leading_1_index_w}) - 7'sd6;
            else
                exp_final_2_w = 7'sd0;
        end else begin
            if (leading_1_index_w == 5'd8) begin
                sum_mant_norm_w = sum_mant >> 1;
                exp_final_2_w = exp_base_7 + 7'sd1;
            end else if (leading_1_index_w == 5'd7) begin
                sum_mant_norm_w = sum_mant;
                exp_final_2_w = exp_base_7;
            end else begin
                if (exp_base_7 <= shift_val_signed) begin
                    sum_mant_norm_w = sum_mant << (exp_base - 1);
                    exp_final_2_w = 7'sd0;
                end else begin
                    sum_mant_norm_w = sum_mant << shift_val;
                    exp_final_2_w = exp_base_7 - shift_val_signed;
                end
            end
        end
    end
end

wire [5:0] mant_rount_w = (exp_final_2_w == 7'sd0) ? {2'b00, sum_mant_norm_w[7:4]} :
                          ({2'b00, sum_mant_norm_w[7:4]} + {5'b0, (sum_mant_norm_w[3] & (sum_mant_norm_w[2] | sum_mant_norm_w[1] | sum_mant_norm_w[0] | sum_mant_norm_w[4]))});

wire signed [6:0] exp_round_w = mant_rount_w[4] ? (exp_final_2_w + 7'sd1) : exp_final_2_w;
wire [7:0] y_normal = (exp_round_w > 7'sd15) ? {sing_reg_w, 7'b1111111} : {sing_reg_w, exp_round_w[3:0], mant_rount_w[2:0]};

always @(*) begin
    if (a[6:0] == 7'd0 && b[6:0] == 7'd0)
        y = (a[7] & b[7]) ? {1'b1, 7'd0} : {1'b0, 7'd0};
    else if (a[6:0] == 7'd0)
        y = b;
    else if (b[6:0] == 7'd0)
        y = a;
    else if (a[7] != b[7] && b[6:0] == a[6:0])
        y = 8'd0;
    else if (a[6:0] == 7'b1111111)
        y = {a[7], 7'b1111111};
    else if (b[6:0] == 7'b1111111)
        y = {b[7], 7'b1111111};
    else if ((a[6:3] == 4'b1111 && b[6:3] == 4'b1111) && (a[2:0] + b[2:0] > 15))
        y = {a[7], 7'b1111111};
    else
        y = y_normal;
end

wire _unused_ok = &{1'b0,
                     exp_diff_a_b[5:4], exp_diff_b_a[5:4], sum_mant_norm_w[10:8], mant_rount_w[5], mant_rount_w[3],
                     1'b0};

endmodule
