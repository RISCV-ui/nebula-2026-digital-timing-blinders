module asynchronous_fifo_gen #(parameter  width = 36,parameter  logofdepth = 4)
                         (clk_1,rst_1,
                          clk_2,rst_2,
                          data_in_clk1,w_en_clk_1,
                          data_out_clk2,r_en_clk_2,
                          fifo_full, fifo_empty
                          );
                          
input  clk_1,clk_2,rst_1,rst_2,w_en_clk_1,r_en_clk_2;
input  [width -1: 0]data_in_clk1;
output  [width -1: 0 ]data_out_clk2;
output wire fifo_full, fifo_empty;


//// wire
wire [logofdepth : 0]counter_1_gray ;
wire [logofdepth : 0]counter_2_gray ;

/// regs 
reg [width -1: 0]mem[(1<<logofdepth)-1 : 0];
reg [logofdepth:0]counter_1;  
reg [logofdepth:0]counter_2;  


reg [logofdepth:0]synchronizers_1_clk_1;
reg [logofdepth:0]synchronizers_2_clk_1;
reg [logofdepth:0]synchronizers_1_clk_2;
reg [logofdepth:0]synchronizers_2_clk_2;

//// assign 
assign  data_out_clk2 = (r_en_clk_2 == 1'b1 && fifo_empty == 1'b0)? mem[counter_2[logofdepth-1:0]]:0; 

assign counter_1_gray = counter_1^{1'b0,counter_1[logofdepth:1]};
assign counter_2_gray = counter_2^{1'b0,counter_2[logofdepth:1]}; 

assign fifo_full = ( ((counter_1_gray[logofdepth] != synchronizers_2_clk_1[logofdepth]) &&
                      (counter_1_gray[logofdepth-1] != synchronizers_2_clk_1[logofdepth-1]) )&&
                            ( counter_1_gray[logofdepth-2:0]  == synchronizers_2_clk_1[logofdepth-2:0] )   );

assign  fifo_empty = ( counter_2_gray == synchronizers_2_clk_2)?1'b1:1'b0;
//// sequential

/// writeint to fifo 

always@(posedge clk_1)
begin
        
        if(w_en_clk_1 == 1'b1 && fifo_full == 1'b0 ) mem[counter_1[logofdepth-1:0]] <= data_in_clk1;  /// 
                
        if(rst_1)counter_1            <= 0; 
        else if(w_en_clk_1 == 1'b1 && fifo_full == 1'b0 ) counter_1 <= counter_1 + 1 ;   /// && fifo_full == 1'b0
        
     
        if(rst_1)
        begin    
 
          synchronizers_1_clk_1 <=  0;
          synchronizers_2_clk_1 <=  0;
        end
        
        else  
        begin
         synchronizers_1_clk_1 <= counter_2_gray;
         synchronizers_2_clk_1 <= synchronizers_1_clk_1;                           
         
                            
        
       end
     
       
      
      
end 

//// reading from fifo 
always@(posedge clk_2)
begin  
    
     
   if(rst_2)counter_2            <=  0;  
   else if(r_en_clk_2 == 1'b1 && fifo_empty == 1'b0 ) counter_2 <= counter_2 + 1 ;  ///
   
   if(rst_2)
      begin    
 
        synchronizers_1_clk_2 <=  0;
        synchronizers_2_clk_2 <=  0;
      end
      
      else  
      begin
       synchronizers_1_clk_2 <= counter_1_gray;
       synchronizers_2_clk_2 <= synchronizers_1_clk_2;                           
       
      
     end
     
     
end 



endmodule
