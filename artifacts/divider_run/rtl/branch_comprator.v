`timescale 1ns / 1ps


module branch_comprator (
    input  wire [31:0] rs1,
    input  wire [31:0] rs2,
    input  wire [2:0]  funct3,
    output reg         branch_taken
);
    always @(*) begin
    
    
        case (funct3)
            3'b000: branch_taken = (rs1 == rs2);
            3'b001: branch_taken = (rs1 != rs2);
            3'b100: branch_taken = ($signed(rs1) < $signed(rs2));
            3'b101: branch_taken = ($signed(rs1) >= $signed(rs2));
            3'b110: branch_taken = (rs1 < rs2);
            3'b111: branch_taken = (rs1 >= rs2);
            3'b011: branch_taken = 1'b1;   /// for unconditional branch
            default: branch_taken = 1'b0;
        endcase
    end
endmodule
