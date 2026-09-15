`timescale 1ns / 1ps


module alu_src_a_mux (
    input  wire [31:0] rd1,
    input  wire [31:0] pc,
    input  wire [31:0]csr_read,
    input  wire [1:0]  sel,
    output reg  [31:0] src_a
);
    always @(*) begin
        case (sel)
            2'b00:   src_a = rd1;
            2'b01:   src_a = pc;
            2'b10:   src_a = 32'd0;
            2'b11:   src_a = csr_read;
            default: src_a = rd1;
        endcase
    end
endmodule

