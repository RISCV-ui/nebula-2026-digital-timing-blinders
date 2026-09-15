`timescale 1ns / 1ps


module data_extender(data_in,control,data_out);
input [31:0]data_in;
input [2:0]control;
output reg [31:0]data_out;


always@(*)

begin
      case(control)
      
      3'b000:data_out = data_in; ///000 load
      3'b001:data_out = {{16{data_in[15]}},data_in[15:0]}; //// lh  
      3'b010:data_out = {{24{data_in[7]}},data_in[7:0]}; //// lb         
      3'b011:data_out = {16'd0,data_in[15:0]}; //// lhu  
      // LBU: zero extend the low BYTE. This was a copy of the lhu line above
      // it, so every lbu returned the low halfword instead -- any byte load of
      // an address whose upper byte in the word was non-zero read back wrong.
      3'b100:data_out = {24'd0,data_in[7:0]}; //// lbu    
      
      default :data_out = data_in; ///000 load
      
      


        endcase
end


endmodule
