`timescale 1ns/1ps
module multiplier_pipelined (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] src_a,
    input  wire [31:0] src_b,
    input  wire        is_mulh,
    output wire        mult_busy,
    output wire        done,
    output reg  [31:0] result
);
    reg        valid_s1, valid_s2, valid_s3;
    // Only two flag stages are needed: the select happens off is_mulh_s2,
    // in the same cycle valid_s2 marks the product as ready.
    reg        is_mulh_s1, is_mulh_s2;
    reg signed [31:0] s1_a;
    reg signed [31:0] s1_b;

    wire signed [33:0] booth_b;
    assign booth_b = {s1_b[31], s1_b, 1'b0};

    wire signed [63:0] partial [0:15];
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_PARTIAL
            wire signed [33:0] shifted_b;
            assign shifted_b = booth_b >>> (2 * gi);
            wire [2:0] triplet;
            assign triplet = shifted_b[2:0];
            // Only the low 3 bits of the shifted multiplicand feed the Booth
            // triplet; the upper bits are intentionally unused here.
            wire _unused_ok = &{1'b0, shifted_b[33:3], 1'b0};
            wire signed [63:0] a_ext;
            assign a_ext = {{32{s1_a[31]}}, s1_a};
            reg signed [63:0] pp;
            always @(*) begin
                case (triplet)
                    3'b000,
                    3'b111: pp = 64'sd0;
                    3'b001,
                    3'b010: pp =  (a_ext <<< (2 * gi));
                    3'b011: pp =  (a_ext <<< (2 * gi + 1));
                    3'b100: pp = -(a_ext <<< (2 * gi + 1));
                    3'b101,
                    3'b110: pp = -(a_ext <<< (2 * gi));
                    default: pp = 64'sd0;
                endcase
            end
            assign partial[gi] = pp;
        end
    endgenerate

    wire signed [63:0] lvl0 [0:7];
    genvar la;
    generate
        for (la = 0; la < 8; la = la + 1) begin : LVLA
            assign lvl0[la] = partial[2*la] + partial[2*la+1];
        end
    endgenerate

    wire signed [63:0] lvl1 [0:3];
    genvar lb;
    generate
        for (lb = 0; lb < 4; lb = lb + 1) begin : LVLB
            assign lvl1[lb] = lvl0[2*lb] + lvl0[2*lb+1];
        end
    endgenerate

    wire signed [63:0] lvl2 [0:1];
    assign lvl2[0] = lvl1[0] + lvl1[1];
    assign lvl2[1] = lvl1[2] + lvl1[3];

    wire signed [63:0] sum;
    assign sum = lvl2[0] + lvl2[1];

    reg signed [63:0] product;

    always @(posedge clk) begin
        if (rst) begin
            valid_s1   <= 1'b0;
            valid_s2   <= 1'b0;
            valid_s3   <= 1'b0;
            is_mulh_s1 <= 1'b0;
            is_mulh_s2 <= 1'b0;
            s1_a       <= 32'sd0;
            s1_b       <= 32'sd0;
            product    <= 64'sd0;
            result     <= 32'd0;
        end
        else begin
            valid_s1   <= start;
            is_mulh_s1 <= is_mulh;
            if (start) begin
                s1_a <= $signed(src_a);
                s1_b <= $signed(src_b);
            end

            valid_s2   <= valid_s1;
            is_mulh_s2 <= is_mulh_s1;
            if (valid_s1)
                product <= sum;

            valid_s3   <= valid_s2;
            // is_mulh_s2, not is_mulh_s3. product and valid_s2 both belong to
            // the operation whose flag is sitting in is_mulh_s2 right now;
            // is_mulh_s3 still holds the PREVIOUS operation's flag at this
            // edge. Selecting on it returned the low word for the first mulh
            // after any mul (and the high word for a mul following a mulh).
            if (valid_s2)
                result <= is_mulh_s2 ? product[63:32]
                                     : product[31:0];
        end
    end

    assign mult_busy = valid_s1 | valid_s2;
    assign done      = valid_s3;

endmodule
