`timescale 1ns / 1ps

module data_clipper(datain,sel,data_out);

input [31:0]datain;
input [1:0]sel;
output reg [31:0]data_out;

always@(*)
begin
data_out=32'd0;

     case(sel)
          2'b00: data_out = datain;
          2'b01: data_out = {16'd0,datain[15:0]};
          2'b10: data_out = {24'd0,datain[7:0]};
          default: data_out = datain;   

     endcase


end




  
endmodule
