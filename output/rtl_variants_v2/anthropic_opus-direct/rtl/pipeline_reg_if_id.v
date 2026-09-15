`timescale 1ns / 1ps

module pipeline_reg_if_id(clk,rst,flush_if_id,en_if_id,    /// reg control signals
                           pc_pluse4_in,pc_in,instruction_in, /// in 
                           pc_pluse4_out, pc_out,instruction_out); /// out 

input wire clk,rst,flush_if_id,en_if_id;
input wire [31:0]pc_pluse4_in,pc_in, instruction_in;
output reg [31:0]pc_pluse4_out,pc_out;
output reg [31:0]instruction_out;


// instruction_out was a self-referential continuous assign
//   assign instruction_out = flush ? 0 : en ? instruction_out : instruction_in;
// which is a combinational loop, not a pipeline register, and left the
// instruction unregistered (arriving a cycle ahead of its own pc_out).
// It is now a flop in the block below, with the same reset/flush/stall
// semantics as pc_out and pc_pluse4_out.


always @(posedge clk) 
begin
        if (rst) 
        begin
            pc_pluse4_out       <= 32'd0;
            pc_out              <= 32'd0;
            instruction_out     <= 32'd0;
 
        end
        else if (flush_if_id)
         begin
            pc_pluse4_out       <= 32'd0;
            pc_out              <= 32'd0;
            instruction_out     <= 32'd0;
      
        end
        else if (!en_if_id)    /// active low enable  en 0 --> out<= in
                                            /////    en 1 --> out<= out  // stall 
        begin
            pc_pluse4_out       <= pc_pluse4_in;
            pc_out              <= pc_in;
            instruction_out     <= instruction_in;
      
        end
    end


                           
endmodule


