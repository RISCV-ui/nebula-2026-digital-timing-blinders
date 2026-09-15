`timescale 1ns / 1ps


module clk_div_mux(
    clk,
    rst,
    sel,
    clk_out
    );

input clk;
input rst;
input [1:0] sel;

output reg clk_out;

reg [2:0] clk_div;

wire clk_div2;
wire clk_div4;
wire clk_div8;


always @(posedge clk)
begin
    if(rst)
        clk_div <= 3'b000;
    else
        clk_div <= clk_div + 1'b1;
end


assign clk_div2 = clk_div[0];
assign clk_div4 = clk_div[1];
assign clk_div8 = clk_div[2];


always @(*)
begin

    case(sel)

        2'b00: clk_out = clk;
        2'b01: clk_out = clk_div2;
        2'b10: clk_out = clk_div4;
        2'b11: clk_out = clk_div8;

        default: clk_out = clk;

    endcase

end


endmodule
