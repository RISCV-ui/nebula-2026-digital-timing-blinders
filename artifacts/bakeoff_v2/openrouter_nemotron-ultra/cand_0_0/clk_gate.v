`timescale 1ns / 1ps


module clk_gate(
    clk_in,
    clk_en,
    clk_out
    );

input clk_in,clk_en;
output clk_out;


assign clk_out = clk_in&clk_en ;



endmodule
