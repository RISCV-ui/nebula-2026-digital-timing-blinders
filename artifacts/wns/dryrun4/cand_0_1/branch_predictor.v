`timescale 1ns / 1ps

module branch_predictor(clk, rst, pc_ex, branch_addr_ex, branch_result_ex, opcode_ex,
                        pc_current, hit_wire, prediction_value_wire, branch_addr_out_wire);

input clk, rst, branch_result_ex;
input [6:0] opcode_ex;
input [31:0] pc_ex, branch_addr_ex, pc_current;

output wire hit_wire, prediction_value_wire;
output wire [31:0] branch_addr_out_wire;

reg [31:0] pc_table[0:15];
reg [31:0] branch_table[0:15];
reg [1:0]  prediction_table[0:15];
reg        valid_table[0:15];
reg [3:0]  idx;
reg [3:0]  replacement_pointer;

reg [3:0]  hit_index;
reg        found;

reg        hit, prediction_value;
reg [31:0] branch_addr_out;

assign hit_wire            = hit;
assign prediction_value_wire = prediction_value;
assign branch_addr_out_wire  = branch_addr_out;

/////    finding any pc is there are not

integer i;
always @(*) begin
    hit       = 1'b0;
    hit_index = 4'd0;
    for (i = 0; i < 16; i = i + 1) begin
        if (valid_table[i] && pc_table[i] == pc_current) begin
            hit       = 1'b1;
            hit_index = i[3:0];
        end
    end
end


/////// output of thre branch table and the 


always @(*) begin
    if (hit && valid_table[hit_index]) begin
        prediction_value = prediction_table[hit_index][1]; 
        branch_addr_out  = prediction_table[hit_index][1] ? branch_table[hit_index] : 32'd0;
    end else begin
        prediction_value = 1'b0;
        branch_addr_out  = 32'd0;
    end
end


integer m;
always @(*) begin
    found = 1'b0;      
    idx   = 4'd0;
    for (m = 0; m < 16; m = m + 1) begin
        if (valid_table[m] && pc_table[m] == pc_ex) begin
            found = 1'b1;
            idx   = m[3:0];
        end
       
    end
end


integer j;
always @(posedge clk) 
begin
    if (rst) 
    begin
        replacement_pointer <= 4'd0;
        for (j = 0; j < 16; j = j + 1) begin
            pc_table[j]         <= 32'd0;
            branch_table[j]     <= 32'd0;
            prediction_table[j] <= 2'b01;   
            valid_table[j]      <= 1'b0;
        end
    end 
    else
    
     begin

        if (!found && (opcode_ex == 7'b1100011 || opcode_ex == 7'b1101111)) 
        begin
           
            pc_table[replacement_pointer]     <= pc_ex;
            branch_table[replacement_pointer] <= branch_addr_ex;
            valid_table[replacement_pointer]  <= 1'b1;
            prediction_table[replacement_pointer] <= branch_result_ex ? 2'b10 : 2'b01; 

            replacement_pointer <= (replacement_pointer == 4'b1111)? 4'd0 : replacement_pointer + 4'd1;

        end 
        else if (found) 
        begin
 
            if (branch_result_ex) begin
                if (prediction_table[idx] != 2'b11)
                    prediction_table[idx] <= prediction_table[idx] + 2'b01;
            end else begin
                if (prediction_table[idx] != 2'b00)       
                    prediction_table[idx] <= prediction_table[idx] - 2'b01;
                
            end
        end

    end
end

endmodule


















//`timescale 1ns / 1ps


//module branch_predictor(clk,rst,pc_ex,branch_addr_ex,branch_result_ex,opcode_ex,
//                        pc_current,hit_wire,prediction_value_wire,branch_addr_out_wire);
                        
//input clk,rst,branch_result_ex;
//input [6:0]opcode_ex;
//input [31:0]pc_ex,branch_addr_ex,pc_current;


//output wire hit_wire,prediction_value_wire;
//output wire [31:0]branch_addr_out_wire;

//reg [31:0]pc_table[0:15];
//reg [31:0]branch_table[0:15];
//reg [1:0]prediction_table[0:15];
//reg valid_table [0:15];
//reg [3:0]idx;
//reg [3:0]replacement_pointer;

////reg hit;
//reg [3:0] hit_index;
//reg found;

//reg hit,prediction_value;
//reg [31:0]branch_addr_out;


//assign hit_wire = hit;
//assign prediction_value_wire = prediction_value;
//assign branch_addr_out_wire  = branch_addr_out;


/////  current pc 

//integer i;

//always @(*) 
//    begin
//        hit = 0;
//        hit_index = 0;

//        for (i = 0; i < 16; i = i + 1) begin
//            if ( pc_table[i] == pc_current&& valid_table[i]== 1) begin
//                hit = 1;
//                hit_index = i;
//            end
//        end
//    end

//////

//always @(*) begin
//        if (hit) begin
//            if (prediction_table[hit_index][1]&& valid_table[hit_index] == 1) begin
//                prediction_value = 1;
//                branch_addr_out = branch_table[hit_index];
//            end else begin
//                prediction_value = 0;
//                branch_addr_out = 32'd0;
//            end
//        end else begin
//            prediction_value = 0;
//            branch_addr_out = 32'd0;
//        end
//    end



/////// finding is there is any pc if not then make entry

//integer j,k;

//always @(posedge clk)
//begin




//if (rst) 
//        begin
//         idx    <=4'b0;
//         found  <= 1'b0;
//         replacement_pointer <=4'b0000;
         
         
//           for (j = 0; j < 16; j = j + 1)
//             begin
//                 pc_table[j]         <= 32'd0;
//                 branch_table[j]     <= 32'd0;
//                 prediction_table[j] <= 2'b01;
                 
//                 valid_table[j]      <=1'b0;
                 
//             end
//        end
     

//else
//     begin 

        
//        for (k = 0; k < 16; k = k + 1)
//            begin
//                if(pc_table[k]==pc_ex && valid_table[k]== 1)
//                   begin
//                     idx <= k;
//                     found <= 1'b1;
//                   end   
//                 else
//                     begin
//                     idx <= 4'd0;
//                     found <= 1'b0;
//                     end  
                              
//            end      
                   
             
//                      if(!found &&(opcode_ex == 7'b1101111 || opcode_ex == 7'b1100011))
//                         begin
                         
//                           branch_table[replacement_pointer]   <= branch_addr_ex;     
//                           pc_table [replacement_pointer]      <= pc_ex;
//                           valid_table[replacement_pointer]    <=1'b1; 
//                           found                               <=1'b0;                         
                               
                         
//                              if(branch_result_ex)
//                                 begin
//                                      prediction_table[replacement_pointer] <= 2'b10;
//                                      if( replacement_pointer != 4'b1111)
//                                         begin
//                                          replacement_pointer <= replacement_pointer +4'd1;  
//                                         end
//                                    else
//                                        begin
//                                          replacement_pointer <=4'd0;
//                                        end                        
                                      
    
//                                 end  
                                           
//                              else
//                                 begin
//                                      prediction_table[replacement_pointer] <= 2'b00;
//                                      if( replacement_pointer != 4'b1111)
//                                         begin
//                                              replacement_pointer <= replacement_pointer +4'd1;  
//                                         end
//                                     else
//                                         begin
//                                          replacement_pointer <=4'd0;
//                                       end                        
                                                                            
//                                 end 
                                        
//                      end      
                                      
//                      else
//                          begin
//                               if(branch_result_ex == 1 && valid_table[idx]== 1)
//                                  begin
//                                       if(prediction_table[idx] != 2'b11)
//                                          begin
//                                          prediction_table[idx] <= prediction_table[idx]+ 2'b01;
//                                          end       
                                            
//                                   end         
//                                 else if(branch_result_ex == 0 && valid_table[idx]== 1)
                                 
//                                     begin
//                                           if(prediction_table[idx] != 2'b00)
//                                           begin
//                                           prediction_table[idx] <= prediction_table[idx] - 2'b01;
                                           
//                                           end 
                                           
//                                  else
//                                      begin
                                      
//                                           prediction_table[idx] <= 2'b10;
                                      
//                                      end         
               
                                  
//                                  end
//                          end
        
//               end      
                  
// end
                  
//endmodule
