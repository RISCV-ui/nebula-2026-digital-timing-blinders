`timescale 1ns / 1ps


module alu_src_b_mux (
    input  wire [31:0] rd2,
    input  wire [31:0] imm_ext,
    input  wire [1:0]  sel,
    output reg  [31:0] src_b
);
    always @(*) begin
        case (sel)
            2'b00:   src_b = rd2;
            2'b01:   src_b = imm_ext;
            2'b10:   src_b = 32'd4;
            2'b11:   src_b = 32'd0;
            default: src_b = rd2;
        endcase
    end
endmodule
