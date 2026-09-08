`timescale 1ns / 1ps


module data_forwarding_unit(in_reg_1,in_reg_2,alu_out_src_1,alu_out_src_2,mem_out_src_1,mem_out_src_2,wb_src_1,wb_src_2, /// imput select
                            alu_out_data,mem_out_data,wb_out_data,   /// input data
                            data_out_src_1,data_out_src_2
                            );
                            
input alu_out_src_1,alu_out_src_2;
input mem_out_src_1,mem_out_src_2;
input wb_src_1,wb_src_2;
input [31:0]in_reg_1;
input [31:0]in_reg_2;
input [31:0]alu_out_data;
input [31:0]mem_out_data;
input [31:0]wb_out_data;

output reg [31:0]data_out_src_1,data_out_src_2;

always@(*)
begin


     if(alu_out_src_1)
     begin
     data_out_src_1 = alu_out_data;
     end
     
     else if(mem_out_src_1)
     begin
     
     data_out_src_1 = mem_out_data;
     
     end
     
     else if(wb_src_1)
     begin
     data_out_src_1 = wb_out_data;
     end

     else
     begin
     data_out_src_1 = in_reg_1;
     end

//     if(alu_out_src_2)
//     begin
//     data_out_src_2 = alu_out_data;
//     end
     
//     else if(mem_out_src_2)
//     begin
     
//     data_out_src_2 = mem_out_data;
     
//     end
     
//     else if(wb_src_2)
//     begin
//     data_out_src_2 = wb_out_data;
//     end

//     else
//     begin
//     data_out_src_2 = in_reg_2;
//     end













end



always@(*)
begin




     if(alu_out_src_2)
     begin
     data_out_src_2 = alu_out_data;
     end
     
     else if(mem_out_src_2)
     begin
     
     data_out_src_2 = mem_out_data;
     
     end
     
     else if(wb_src_2)
     begin
     data_out_src_2 = wb_out_data;
     end

     else
     begin
     data_out_src_2 = in_reg_2;
     end

end




                             
                            
endmodule
