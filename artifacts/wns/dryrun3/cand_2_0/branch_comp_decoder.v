`timescale 1ns / 1ps



module branch_comp_decoder(opcode,fun3,operation);
input [6:0]opcode;
input [2:0]fun3;

output reg [2:0]operation;



always@(*)
begin



     if(opcode==7'b1100011)
             begin
             
             operation = fun3;
             
             end
             
     // JAL and JALR are both unconditional. JALR used to fall through to the
     // else below and come out as 3'b010, which the comparator does not decode
     // -- so branch_taken stayed 0 and the fetch stage never redirected. Every
     // JALR, including every function return, fell through to pc+4.
     else if(opcode==7'b1101111 || opcode==7'b1100111)  
           begin
           
           operation = 3'b011;
            
           end      
             
             

       else
           begin
           
           operation = 3'b010;
           
           end


end



endmodule
