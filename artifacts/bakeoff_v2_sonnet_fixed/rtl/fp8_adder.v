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

       /////// leading one detector -- balanced tree, not a 9-level
       /////// sequential priority chain. Same found/index result as the
       /////// original "for (i=8; i>=0; i=i-1)" loop, but every group is
       /////// resolved in parallel and only ~4 levels of select feed the
       /////// final answer, instead of 9 dependent iterations of
       /////// "found so far".
        begin : lod_tree
            reg g87_f, g65_f, g43_f, g21_f;
            reg [3:0] g87_i, g65_i, g43_i, g21_i;
            reg g8765_f, g4321_f;
            reg [3:0] g8765_i, g4321_i;
            reg ghi_f;
            reg [3:0] ghi_i;

            g87_f = sum_mant[8] | sum_mant[7];
            g87_i = sum_mant[8] ? 4'd8 : 4'd7;

            g65_f = sum_mant[6] | sum_mant[5];
            g65_i = sum_mant[6] ? 4'd6 : 4'd5;

            g43_f = sum_mant[4] | sum_mant[3];
            g43_i = sum_mant[4] ? 4'd4 : 4'd3;

            g21_f = sum_mant[2] | sum_mant[1];
            g21_i = sum_mant[2] ? 4'd2 : 4'd1;

            g8765_f = g87_f | g65_f;
            g8765_i = g87_f ? g87_i : g65_i;

            g4321_f = g43_f | g21_f;
            g4321_i = g43_f ? g43_i : g21_i;

            ghi_f = g8765_f | g4321_f;
            ghi_i = g8765_f ? g8765_i : g4321_i;

            found           = ghi_f | sum_mant[0];
            leading_1_index = ghi_f ? {1'b0, ghi_i} : 5'd0;
        end


     //////// normilization

if (found)
begin

    if ((a[6:3] != 4'd0) || (b[6:3] != 4'd0))
    begin

        if (leading_1_index > 7)
        begin
            norm_shift  = leading_1_index - 7;
            exp_final   = (a_grater_reg)? exp_a + norm_shift : exp_b + norm_shift;

            sum_mant_norm  = sum_mant >> norm_shift ;
            exp_final_2    = exp_final ;

        end

        else if (leading_1_index < 7)
        begin
            norm_shift      = 7 - leading_1_index;
            exp_final       = (a_grater_reg)? exp_a - norm_shift : exp_b - norm_shift;

               if(exp_final <= 0 )
               begin
                    sum_mant_norm  = sum_mant << ((a_grater_reg ? exp_a : exp_b) - 1);
                    exp_final_2    = 0;
               end



               else
               begin
                    sum_mant_norm  = sum_mant << norm_shift ;
                    exp_final_2    = exp_final ;
               end

        end


        else
        begin
            norm_shift    = 0;
            sum_mant_norm = sum_mant;

            if (exp_a >= exp_b)
                exp_final_2 = {exp_a[5], exp_a};
            else
                exp_final_2 = {exp_b[5], exp_b};
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


           if(mant_rount[4] == 1'b1)
               exp_round = exp_final_2 +1 ;
           else
               exp_round = exp_final_2 ;

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
