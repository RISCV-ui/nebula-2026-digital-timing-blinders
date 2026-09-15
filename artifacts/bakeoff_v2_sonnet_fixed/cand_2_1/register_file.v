`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.03.2026 00:24:09
// Design Name: 
// Module Name: register_file
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module register_file(
    input wire clk,
    input wire [4:0] A1,
    input wire [4:0] A2,
    input wire [4:0] A3,
    input wire [31:0] WD3,
    input wire WE3,
    output wire [31:0] RD1,
    output wire [31:0] RD2
    );

//Defining 32 registers for R32VI architecture with every register of 32 bits resulting in 32*32    
reg [31:0] register [31:0];

//If address is zero then output will always be zero as zeroth register is harwired to zero
assign RD1 = (A1 == 5'b00000) ? 32'h00000000 : register[A1];
assign RD2 = (A2 == 5'b00000) ? 32'h00000000 : register[A2];

//For writing data positive edge of clk is required along with write enable signal
always @(posedge clk) begin
    if (WE3 && (A3 != 5'b00000))
        register[A3] <= WD3;
end
endmodule
