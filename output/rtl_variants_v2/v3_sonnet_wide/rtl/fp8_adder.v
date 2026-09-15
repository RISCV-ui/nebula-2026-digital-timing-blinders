`timescale 1ns / 1ps



module fp8_adder(a, b, y);

input  [7:0] a, b;
output reg [7:0] y;

///// wire declaration
wire signed [5:0] exp_a, exp_b;
wire [3:0] mant_a, mant_b;

///// reg declaration
reg [3:0] shift_a, shift_b;
reg signed [5:0] exp_diff;   // full-width exponent difference before narrowing to shift_a/shift_b
reg [9:0] mant_a_reg, mant_b_reg,a_operand,b_operand;

reg [10:0] sum_mant;
reg [10:0] sum_mant_norm;

reg found;
reg [4:0] leading_1_index;
reg [5:0] norm_shift;

reg signed [6:0] exp_final_2,exp_final,exp_round;
reg       sing_reg;

reg a_grater_reg,b_grater_reg;
reg [5:0]mant_rount;

reg sticky_a, sticky_b;

// precomputed "whichever operand had the larger exponent" value.
reg signed [5:0] base_exp;

// Restructured rounding/overflow candidates.
reg signed [6:0] exp_round_keep, exp_round_inc;
reg ovf_keep, ovf_inc;

// Restructured normalization candidates -- computed unconditionally so the
// leading_1_index>7 / <7 / ==7 branches, and the underflow check nested
// inside the <7 branch, only have to select among already-finished values
// instead of computing arithmetic serially behind each compare.
reg [5:0] norm_shift_r, norm_shift_l;
reg signed [6:0] exp_cand_r, exp_cand_l;
reg underflow_cond;
reg [10:0] shr_val, shl_val, shu_val;

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
    base_exp        = 6'sd0;

    exp_round_keep  = 7'sd0;
    exp_round_inc   = 7'sd0;
    ovf_keep        = 1'b0;
    ovf_inc         = 1'b0;

    norm_shift_r    = 6'd0;
    norm_shift_l    = 6'd0;
    exp_cand_r      = 7'sd0;
    exp_cand_l      = 7'sd0;
    underflow_cond  = 1'b0;
    shr_val         = 11'd0;
    shl_val         = 11'd0;
    shu_val         = 11'd0;


    if (a[6:0] == 7'd0 && b[6:0] == 7'd0)
    begin
        y = (a[7] & b[7]) ? {1'b1,7'd0} : {1'b0,7'd0};
    end

    else if (a[6:0] == 7'd0)
    begin
        y = b;
    end

    else if (b[6:0] == 7'd0)
    begin
        y = a;
    end

    else if (a[7] != b[7] && b[6:0] == a[6:0])
    begin
        y = 0;
    end

    else if ( a[6:0] ==  7'b1111111)
    begin
        y = {a[7],7'b1111111 };
    end

    else if ( b[6:0] ==  7'b1111111)
    begin
        y = {b[7],7'b1111111 };
    end

     else if ( (a[6:3] ==  4'b1111 && b[6:3] ==  4'b1111)&& a[2:0]+b[2:0]>15  )
    begin
        y = {a[7],7'b1111111 };
    end

    else
    begin

          //// shift calculate

            if (exp_a > exp_b)
            begin
                exp_diff      = exp_a - exp_b;
                shift_a       = exp_diff[3:0];
                a_grater_reg  = 1'b1;
            end

            else if (exp_b > exp_a)
            begin
                exp_diff      = exp_b - exp_a;
                shift_b       = exp_diff[3:0];
                b_grater_reg  = 1'b1;
            end

            base_exp = a_grater_reg ? exp_a : exp_b;


        if (shift_b == 4'd0)
            sticky_a = 1'b0;
        else if (shift_b >= 4'd8)
            sticky_a = |{mant_a,4'd0};
        else
            sticky_a = |(({mant_a,4'd0}) & (8'hFF >> (8 - shift_b)));

        if (shift_a == 4'd0)
            sticky_b = 1'b0;
        else if (shift_a >= 4'd8)
            sticky_b = |{mant_b,4'd0};
        else
            sticky_b = |(({mant_b,4'd0}) & (8'hFF >> (8 - shift_a)));



        mant_a_reg =  b_grater_reg ?{2'b00, (({mant_a,4'd0}) >> shift_b) | {7'b0, sticky_a}} : {2'b00, {mant_a,4'd0}};

        mant_b_reg =  a_grater_reg ?{2'b00, (({mant_b,4'd0}) >> shift_a) | {7'b0, sticky_b}} : {2'b00, {mant_b,4'd0}};



       ///////  compliment the operand


        a_operand = ((b[6:0] > a[6:0]) && (a[7] ^ b[7]))?(~mant_a_reg) :mant_a_reg;
        b_operand =  ((a[6:0] > b[6:0]) && (a[7] ^ b[7])) ?(~mant_b_reg): mant_b_reg;
        sum_mant =  a_operand + b_operand + {10'b0, (a[7] ^ b[7])};

       //////  sign calculator

        if (a[7] == b[7])
        begin
            sing_reg = a[7];
        end
        else
        begin
            if (a[6:0] >= b[6:0])
                sing_reg = a[7];
            else
                sing_reg = b[7];
        end

       /////// leading one detector (flat casez priority encoder)

        casez (sum_mant[8:0])
            9'b1????????: begin leading_1_index = 5'd8; found = 1'b1; end
            9'b01???????: begin leading_1_index = 5'd7; found = 1'b1; end
            9'b001??????: begin leading_1_index = 5'd6; found = 1'b1; end
            9'b0001?????: begin leading_1_index = 5'd5; found = 1'b1; end
            9'b00001????: begin leading_1_index = 5'd4; found = 1'b1; end
            9'b000001???: begin leading_1_index = 5'd3; found = 1'b1; end
            9'b0000001??: begin leading_1_index = 5'd2; found = 1'b1; end
            9'b00000001?: begin leading_1_index = 5'd1; found = 1'b1; end
            9'b000000001: begin leading_1_index = 5'd0; found = 1'b1; end
            default:      begin leading_1_index = 5'd0; found = 1'b0; end
        endcase


     //////// normalization -- candidates for every branch computed
     //////// unconditionally in parallel; the branch conditions only pick
     //////// among finished values (single flat mux level) instead of the
     //////// original 3-deep nested if/else forcing each candidate's
     //////// arithmetic to start only after the previous branch's compare.

if (found)
begin

    if ((a[6:3] != 4'd0) || (b[6:3] != 4'd0))
    begin

        norm_shift_r   = leading_1_index - 7;
        norm_shift_l   = 7 - leading_1_index;
        exp_cand_r     = base_exp + norm_shift_r;
        exp_cand_l     = base_exp - norm_shift_l;
        underflow_cond = (base_exp <= $signed({1'b0, norm_shift_l}));
        shr_val        = sum_mant >> norm_shift_r;
        shl_val        = sum_mant << norm_shift_l;
        shu_val        = sum_mant << (base_exp - 1);

        if (leading_1_index > 7)
        begin
            norm_shift     = norm_shift_r;
            exp_final      = exp_cand_r;
            sum_mant_norm  = shr_val;
            exp_final_2    = exp_cand_r;
        end

        else if (leading_1_index < 7)
        begin
            norm_shift     = norm_shift_l;
            exp_final      = exp_cand_l;

            sum_mant_norm  = underflow_cond ? shu_val : shl_val;
            exp_final_2    = underflow_cond ? 7'sd0    : exp_cand_l;
        end


        else
        begin
            norm_shift    = 0;
            sum_mant_norm = sum_mant;

            exp_final_2 = {base_exp[5], base_exp};
        end
   end

   else
   begin
        sum_mant_norm = sum_mant;

        if (leading_1_index >= 7)

                exp_final_2 =  $signed({2'b00, leading_1_index}) - 7'sd6;

        end
end

                               //l
//////  rounding    ////    1.xxx g r s

     if(exp_final_2 == 0)
     begin

           mant_rount =  {2'b00, sum_mant_norm[7:4]};
     end

     else
     begin

           mant_rount =  {2'b00, sum_mant_norm[7:4]} + {5'b0, (sum_mant_norm[3]&(sum_mant_norm[2]|sum_mant_norm[1]|sum_mant_norm[0]|sum_mant_norm[4]))};
     end

     exp_round_keep = exp_final_2;
     exp_round_inc  = exp_final_2 + 1;
     ovf_keep       = (exp_round_keep > 15);
     ovf_inc        = (exp_round_inc  > 15);

     exp_round = mant_rount[4] ? exp_round_inc : exp_round_keep;

            if (mant_rount[4] ? ovf_inc : ovf_keep)
                y = {sing_reg, 7'b1111111};
            else
                y = {sing_reg, exp_round[3:0], mant_rount[2:0]};

    end

end

wire _unused_ok = &{1'b0,
                     exp_diff[5:4], sum_mant_norm[10:8], mant_rount[5], mant_rount[3],
                     1'b0};

endmodule
