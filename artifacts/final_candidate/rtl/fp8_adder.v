`timescale 1ns / 1ps



module fp8_adder(a, b, y);

input  [7:0] a, b;
output reg [7:0] y;

///// wire declaration
wire signed [5:0] exp_a, exp_b;
wire [3:0] mant_a, mant_b;

assign exp_a = (a[6:3] == 4'd0) ? 6'sd1 : $signed({2'b00, a[6:3]});
assign exp_b = (b[6:3] == 4'd0) ? 6'sd1 : $signed({2'b00, b[6:3]});

assign mant_a = {(a[6:3] != 4'd0), a[2:0]};
assign mant_b = {(b[6:3] != 4'd0), b[2:0]};

// Special cases
reg use_special_case;
reg [7:0] special_y;

always @(*) begin
    use_special_case = 1'b1;
    if (a[6:0] == 7'd0 && b[6:0] == 7'd0)
        special_y = (a[7] & b[7]) ? 8'h80 : 8'h00;
    else if (a[6:0] == 7'd0)
        special_y = b;
    else if (b[6:0] == 7'd0)
        special_y = a;
    else if (a[7] != b[7] && b[6:0] == a[6:0])
        special_y = 8'h00;
    else if (a[6:0] == 7'b1111111)
        special_y = {a[7], 7'b1111111};
    else if (b[6:0] == 7'b1111111)
        special_y = {b[7], 7'b1111111};
    else if ((a[6:3] == 4'b1111 && b[6:3] == 4'b1111) && (a[2:0] + b[2:0] > 15))
        special_y = {a[7], 7'b1111111};
    else begin
        use_special_case = 1'b0;
        special_y = 8'h00;
    end
end

// Main path
wire signed [5:0] exp_diff_a_b = exp_a - exp_b;
wire signed [5:0] exp_diff_b_a = exp_b - exp_a;

wire a_greater = (exp_a > exp_b);
wire b_greater = (exp_b > exp_a);

wire [3:0] shift_a = a_greater ? exp_diff_a_b[3:0] : 4'd0;
wire [3:0] shift_b = b_greater ? exp_diff_b_a[3:0] : 4'd0;

reg sticky_a;
always @(*) begin
    if (shift_b <= 4'd4)
        sticky_a = 1'b0;
    else if (shift_b == 4'd5)
        sticky_a = mant_a[0];
    else if (shift_b == 4'd6)
        sticky_a = |mant_a[1:0];
    else if (shift_b == 4'd7)
        sticky_a = |mant_a[2:0];
    else
        sticky_a = |mant_a;
end

reg sticky_b;
always @(*) begin
    if (shift_a <= 4'd4)
        sticky_b = 1'b0;
    else if (shift_a == 4'd5)
        sticky_b = mant_b[0];
    else if (shift_a == 4'd6)
        sticky_b = |mant_b[1:0];
    else if (shift_a == 4'd7)
        sticky_b = |mant_b[2:0];
    else
        sticky_b = |mant_b;
end

reg [7:0] mant_a_shifted;
always @(*) begin
    case (shift_b)
        4'd1:    mant_a_shifted = {1'b0, mant_a, 3'b0};
        4'd2:    mant_a_shifted = {2'b0, mant_a, 2'b0};
        4'd3:    mant_a_shifted = {3'b0, mant_a, 1'b0};
        4'd4:    mant_a_shifted = {4'b0, mant_a};
        4'd5:    mant_a_shifted = {5'b0, mant_a[3:1]};
        4'd6:    mant_a_shifted = {6'b0, mant_a[3:2]};
        4'd7:    mant_a_shifted = {7'b0, mant_a[3]};
        default: mant_a_shifted = 8'b0;
    endcase
end

reg [7:0] mant_b_shifted;
always @(*) begin
    case (shift_a)
        4'd1:    mant_b_shifted = {1'b0, mant_b, 3'b0};
        4'd2:    mant_b_shifted = {2'b0, mant_b, 2'b0};
        4'd3:    mant_b_shifted = {3'b0, mant_b, 1'b0};
        4'd4:    mant_b_shifted = {4'b0, mant_b};
        4'd5:    mant_b_shifted = {5'b0, mant_b[3:1]};
        4'd6:    mant_b_shifted = {6'b0, mant_b[3:2]};
        4'd7:    mant_b_shifted = {7'b0, mant_b[3]};
        default: mant_b_shifted = 8'b0;
    endcase
end

wire [9:0] mant_a_reg = b_greater ? {2'b00, mant_a_shifted[7:1], mant_a_shifted[0] | sticky_a} : {2'b00, mant_a, 4'd0};
wire [9:0] mant_b_reg = a_greater ? {2'b00, mant_b_shifted[7:1], mant_b_shifted[0] | sticky_b} : {2'b00, mant_b, 4'd0};

wire mag_b_gt_a = (b[6:0] > a[6:0]);
wire mag_a_gt_b = (a[6:0] > b[6:0]);
wire diff_sign = a[7] ^ b[7];

wire [9:0] a_operand = (mag_b_gt_a && diff_sign) ? ~mant_a_reg : mant_a_reg;
wire [9:0] b_operand = (mag_a_gt_b && diff_sign) ? ~mant_b_reg : mant_b_reg;
wire [10:0] sum_mant = a_operand + b_operand + {10'b0, diff_sign};

wire sing_reg = (a[6:0] >= b[6:0]) ? a[7] : b[7];

wire [8:0] sum_mant_9 = sum_mant[8:0];
reg found;
reg [4:0] leading_1_index;
always @(*) begin
    found = |sum_mant_9;
    if (sum_mant_9[8])      leading_1_index = 5'd8;
    else if (sum_mant_9[7]) leading_1_index = 5'd7;
    else if (sum_mant_9[6]) leading_1_index = 5'd6;
    else if (sum_mant_9[5]) leading_1_index = 5'd5;
    else if (sum_mant_9[4]) leading_1_index = 5'd4;
    else if (sum_mant_9[3]) leading_1_index = 5'd3;
    else if (sum_mant_9[2]) leading_1_index = 5'd2;
    else if (sum_mant_9[1]) leading_1_index = 5'd1;
    else if (sum_mant_9[0]) leading_1_index = 5'd0;
    else                    leading_1_index = 5'd0;
end

wire normal = (a[6:3] != 4'd0) || (b[6:3] != 4'd0);
wire signed [5:0] exp_max = (exp_a >= exp_b) ? exp_a : exp_b;
wire [3:0] exp_max_minus_1 = exp_max[3:0] - 4'd1;

reg [10:0] sum_mant_norm_normal;
reg signed [6:0] exp_final_2_normal;

always @(*) begin
    sum_mant_norm_normal = sum_mant;
    exp_final_2_normal = {exp_max[5], exp_max};
    case (leading_1_index)
        5'd8: begin
            sum_mant_norm_normal = sum_mant >> 1;
            exp_final_2_normal = exp_max + 1;
        end
        5'd7: begin
            sum_mant_norm_normal = sum_mant;
            exp_final_2_normal = {exp_max[5], exp_max};
        end
        5'd6: begin
            if (exp_max <= 6'sd1) begin
                sum_mant_norm_normal = sum_mant << exp_max_minus_1;
                exp_final_2_normal = 7'sd0;
            end else begin
                sum_mant_norm_normal = sum_mant << 1;
                exp_final_2_normal = exp_max - 1;
            end
        end
        5'd5: begin
            if (exp_max <= 6'sd2) begin
                sum_mant_norm_normal = sum_mant << exp_max_minus_1;
                exp_final_2_normal = 7'sd0;
            end else begin
                sum_mant_norm_normal = sum_mant << 2;
                exp_final_2_normal = exp_max - 2;
            end
        end
        5'd4: begin
            if (exp_max <= 6'sd3) begin
                sum_mant_norm_normal = sum_mant << exp_max_minus_1;
                exp_final_2_normal = 7'sd0;
            end else begin
                sum_mant_norm_normal = sum_mant << 3;
                exp_final_2_normal = exp_max - 3;
            end
        end
        5'd3: begin
            if (exp_max <= 6'sd4) begin
                sum_mant_norm_normal = sum_mant << exp_max_minus_1;
                exp_final_2_normal = 7'sd0;
            end else begin
                sum_mant_norm_normal = sum_mant << 4;
                exp_final_2_normal = exp_max - 4;
            end
        end
        5'd2: begin
            if (exp_max <= 6'sd5) begin
                sum_mant_norm_normal = sum_mant << exp_max_minus_1;
                exp_final_2_normal = 7'sd0;
            end else begin
                sum_mant_norm_normal = sum_mant << 5;
                exp_final_2_normal = exp_max - 5;
            end
        end
        5'd1: begin
            if (exp_max <= 6'sd6) begin
                sum_mant_norm_normal = sum_mant << exp_max_minus_1;
                exp_final_2_normal = 7'sd0;
            end else begin
                sum_mant_norm_normal = sum_mant << 6;
                exp_final_2_normal = exp_max - 6;
            end
        end
        5'd0: begin
            if (exp_max <= 6'sd7) begin
                sum_mant_norm_normal = sum_mant << exp_max_minus_1;
                exp_final_2_normal = 7'sd0;
            end else begin
                sum_mant_norm_normal = sum_mant << 7;
                exp_final_2_normal = exp_max - 7;
            end
        end
        default: begin
            sum_mant_norm_normal = sum_mant;
            exp_final_2_normal = {exp_max[5], exp_max};
        end
    endcase
end

reg [10:0] sum_mant_norm_subnormal;
reg signed [6:0] exp_final_2_subnormal;

always @(*) begin
    sum_mant_norm_subnormal = sum_mant;
    if (leading_1_index == 5'd8)
        exp_final_2_subnormal = 7'sd2;
    else if (leading_1_index == 5'd7)
        exp_final_2_subnormal = 7'sd1;
    else
        exp_final_2_subnormal = 7'sd0;
end

reg [10:0] sum_mant_norm;
reg signed [6:0] exp_final_2;

always @(*) begin
    if (found) begin
        if (normal) begin
            sum_mant_norm = sum_mant_norm_normal;
            exp_final_2   = exp_final_2_normal;
        end else begin
            sum_mant_norm = sum_mant_norm_subnormal;
            exp_final_2   = exp_final_2_subnormal;
        end
    end else begin
        sum_mant_norm = 11'd0;
        exp_final_2   = 7'sd0;
    end
end

wire round_bit = sum_mant_norm[3] & (sum_mant_norm[2] | sum_mant_norm[1] | sum_mant_norm[0] | sum_mant_norm[4]);
reg [5:0] mant_rount;
always @(*) begin
    if (exp_final_2 == 0)
        mant_rount = {2'b00, sum_mant_norm[7:4]};
    else
        mant_rount = {2'b00, sum_mant_norm[7:4]} + {5'b0, round_bit};
end

wire signed [6:0] exp_round = (mant_rount[4] == 1'b1) ? (exp_final_2 + 7'sd1) : exp_final_2;

wire [7:0] normal_y = (exp_round > 15) ? {sing_reg, 7'b1111111} : {sing_reg, exp_round[3:0], mant_rount[2:0]};

always @(*) begin
    y = use_special_case ? special_y : normal_y;
end

wire _unused_ok = &{1'b0,
                     exp_diff_a_b[5:4], exp_diff_b_a[5:4], sum_mant_norm[10:8], mant_rount[5], mant_rount[3],
                     1'b0};

endmodule
