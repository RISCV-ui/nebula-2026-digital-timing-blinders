`timescale 1ns / 1ps


module l1_i_cache_8kb(clk,rst,addr_cpu_in,addr_valid_in,data_l1_out,data_l1_valid_out,hit_l1_out,
                             addr_l2,addr_l2_valid,data_in_l2,data_valid_l2);

input clk,rst;

/// cpu l1 inteface 
input [31:0]addr_cpu_in;
input addr_valid_in;



output reg [255:0]data_l1_out;
output reg data_l1_valid_out;
output reg hit_l1_out;


/// l1 l2 interface 

output wire [31:0]addr_l2;
output wire addr_l2_valid;

input [255:0]data_in_l2;
input data_valid_l2;


//// parameters

parameter idle             =  5'b00001;
parameter tag_en           =  5'b00010;
parameter tag_check         = 5'b00100;
parameter req_higher_level  = 5'b01000;
parameter write_data        = 5'b10000;


//// regs 
reg [4:0]pr_state,nxt_state;
//reg [15:0]age_valid_dirty_mem[0:63];
reg hit; 
reg [1:0]way_id;

reg [255:0]data_l1;

reg read_write_mem_0_reg;
reg read_write_mem_1_reg;
reg read_write_mem_2_reg;
reg read_write_mem_3_reg;

reg mem_en_0_reg;
reg mem_en_1_reg;
reg mem_en_2_reg;
reg mem_en_3_reg;

reg mem_en_tag_reg;


reg [3:0]age_valid_dirty_0[0:7];
reg [3:0]age_valid_dirty_1[0:7];
reg [3:0]age_valid_dirty_2[0:7];
reg [3:0]age_valid_dirty_3[0:7];



reg [255:0]data_in_mem_0_reg;
reg [255:0]data_in_mem_1_reg;
reg [255:0]data_in_mem_2_reg;
reg [255:0]data_in_mem_3_reg;

reg [91:0]data_in_tag_mem_reg;
reg [91:0]data_in_tag_mem_buf;

reg tag_read_write;
reg [3:0]age_4_bit;
reg [3:0]valid_4_bit;



/// fsm regs 
reg lru_update;
reg write_en;
reg [1:0]way_selection;
reg l2_req;
//*reg en_tag_check;
reg read_data_fron_cache ; 
//reg data_l1_valid_out_reg;


/// wire decl
wire [2:0] set_id;   // 8 sets (was 64)
wire [22:0]tag; 
wire read_write;
wire [91:0]data_in_tag_mem,data_out_tag_mem;

wire mem_en_tag;

wire mem_en_0;
wire read_write_mem_0;
wire [255:0]data_in_mem_0,data_out_mem_0;


wire mem_en_1;
wire read_write_mem_1;
wire [255:0]data_in_mem_1,data_out_mem_1;

wire mem_en_2;
wire read_write_mem_2;
wire [255:0]data_in_mem_2,data_out_mem_2;

wire mem_en_3;
wire read_write_mem_3;
wire [255:0]data_in_mem_3,data_out_mem_3;


wire [1:0]age_w1,age_w2,age_w3,age_w0;

wire [5:0] unused;   // byte offset + unused set bits; deliberately unused
wire data_valid_tag_mem;
wire data_valid_mem_0;
wire data_valid_mem_1;
wire data_valid_mem_2;
wire data_valid_mem_3;


//// assign 
assign  set_id    = addr_cpu_in[8:6];   
assign  tag       = addr_cpu_in[31:9];
assign unused     = addr_cpu_in[5:0];

assign read_write = tag_read_write; 
assign mem_en_tag = mem_en_tag_reg;

assign  read_write_mem_0   =   read_write_mem_0_reg;
assign  read_write_mem_1   =   read_write_mem_1_reg;
assign  read_write_mem_2   =   read_write_mem_2_reg;
assign  read_write_mem_3   =   read_write_mem_3_reg;


assign  mem_en_0   =   mem_en_0_reg;
assign  mem_en_1   =   mem_en_1_reg;
assign  mem_en_2   =   mem_en_2_reg;
assign  mem_en_3   =   mem_en_3_reg;

assign  data_in_mem_0   =   data_in_mem_0_reg;
assign  data_in_mem_1   =   data_in_mem_1_reg;
assign  data_in_mem_2   =   data_in_mem_2_reg;
assign  data_in_mem_3   =   data_in_mem_3_reg;

assign data_in_tag_mem  =   data_in_tag_mem_reg ;

assign age_w0 = age_valid_dirty_0[set_id][3:2];
assign age_w1 = age_valid_dirty_1[set_id][3:2];
assign age_w2 = age_valid_dirty_2[set_id][3:2];
assign age_w3 = age_valid_dirty_3[set_id][3:2];

assign addr_l2         = (l2_req == 1'b1)?{addr_cpu_in[31:3],3'b000}:32'd0;
assign addr_l2_valid   = (l2_req == 1'b1)?1'b1:1'b0;


////// combo 

///////   tag identification

tag_memory_92x64_wrap  tag_mem_0(clk,rst,mem_en_tag,{29'd0,set_id},read_write,data_in_tag_mem,data_out_tag_mem,data_valid_tag_mem);

id_memory_256x64_wrap   i_mem_0(clk,rst,mem_en_0,{29'd0,set_id},read_write_mem_0,data_in_mem_0,data_out_mem_0,data_valid_mem_0);
id_memory_256x64_wrap   i_mem_1(clk,rst,mem_en_1,{29'd0,set_id},read_write_mem_1,data_in_mem_1,data_out_mem_1,data_valid_mem_1);
id_memory_256x64_wrap   i_mem_2(clk,rst,mem_en_2,{29'd0,set_id},read_write_mem_2,data_in_mem_2,data_out_mem_2,data_valid_mem_2);
id_memory_256x64_wrap   i_mem_3(clk,rst,mem_en_3,{29'd0,set_id},read_write_mem_3,data_in_mem_3,data_out_mem_3,data_valid_mem_3);


//// sequenttial 
/// buffer thj tag into reg 
always@(posedge clk)
if(rst)             data_in_tag_mem_buf <=92'd0;
else if(data_valid_tag_mem) data_in_tag_mem_buf <= data_out_tag_mem;

/// tage mem read 
always@(*)
begin
hit         = 1'b0;
way_id      = 2'd0;

//  if(en_tag_check == 1'b1)
//  begin
       if(tag == data_in_tag_mem_buf[22:0] && age_valid_dirty_0[set_id][1] == 1  )
         begin
              hit         = 1'b1;
              way_id      = 2'd0;
              
 
         end
      else if(tag == data_in_tag_mem_buf[45:23] && age_valid_dirty_1[set_id][1] == 1 )
         begin
              hit         = 1'b1;
              way_id      = 2'd1;
             
           
 
         end

      else if(tag == data_in_tag_mem_buf[68:46] && age_valid_dirty_2[set_id][1] == 1  )
         begin
              hit         = 1'b1;
              way_id      = 2'd2;
           
         end
      else if(tag == data_in_tag_mem_buf[91:69] && age_valid_dirty_3[set_id][1] == 1 )
         begin
              hit         = 1'b1;
              way_id      = 2'd3;
             
         end   
 
     end
//end

///// 

///// read the block if hit  


always@(*)
begin
    data_l1 = 256'd0 ;
      ///// data read if hit  = 1     
    ////  if(read_en == 1'b1)
    //     begin
    if(hit)
begin
      case(way_id)
          2'b00:data_l1 = data_out_mem_0;       
          2'b01:data_l1 = data_out_mem_1;   
          2'b10:data_l1 = data_out_mem_2;       
          2'b11:data_l1 = data_out_mem_3;
      endcase
    end
end

//// write  
integer i;


always@(posedge clk)
begin 
     
    if(rst)
    begin
        for(i=0;i<64;i=i+1)
         begin
               age_valid_dirty_0[i[5:0]] <= 4'b0000;
               age_valid_dirty_1[i[5:0]] <= 4'b0100;
               age_valid_dirty_2[i[5:0]] <= 4'b1000;
               age_valid_dirty_3[i[5:0]] <= 4'b1100;
         end
      end


     else
     begin
      
      
      if(lru_update == 1)
       begin
          case(way_id)
          2'b00: 
          begin
                
                age_valid_dirty_0[set_id][3:2] <= 2'b00;                       
                age_valid_dirty_1[set_id][3:2]<=  (age_w1 < age_w0)?(age_w1 + 2'b01):age_w1;                                              
                age_valid_dirty_2[set_id][3:2]<=  (age_w2 < age_w0)?(age_w2 + 2'b01):age_w2;                                             
                age_valid_dirty_3[set_id][3:2]<=  (age_w3 < age_w0)?(age_w3 + 2'b01):age_w3;
                                                  
          
          end
          
         2'b01: 
          begin
                age_valid_dirty_0[set_id][3:2] <= (age_w0 < age_w1)?(age_w0+2'b01):age_w0;//(age_w0 < age_w1)?(age_w0 + 1):age_w0;                        
                age_valid_dirty_1[set_id][3:2]<=  2'b00;                                                                
                age_valid_dirty_2[set_id][3:2]<= (age_w2 < age_w1)?(age_w2 + 2'b01):age_w2;                                               
                age_valid_dirty_3[set_id][3:2]<= (age_w3 < age_w1)?(age_w3 + 2'b01):age_w3;
         
          end
          
          2'b10: 
          begin
                age_valid_dirty_0[set_id][3:2] <= (age_w0 < age_w2)?(age_w0 + 2'b01):age_w0;                         
                age_valid_dirty_1[set_id][3:2]<= (age_w1 < age_w2)?(age_w1 + 2'b01):age_w1;                                                               
                age_valid_dirty_2[set_id][3:2]<=  2'b00;                                                                     
                age_valid_dirty_3[set_id][3:2]<= (age_w3 < age_w2)?(age_w3 + 2'b01):age_w3;
         
          end
          
          2'b11: 
          begin
                age_valid_dirty_0[set_id][3:2] <=(age_w0 < age_w3)?(age_w0 + 2'b01):age_w0;                        
                age_valid_dirty_1[set_id][3:2]<= (age_w1 < age_w3)?(age_w1 + 2'b01):age_w1;                                                               
                age_valid_dirty_2[set_id][3:2]<= (age_w2 < age_w3)?(age_w2 + 2'b01):age_w2;                                                                      
                age_valid_dirty_3[set_id][3:2]<= 2'b00;
          
          end
           
         endcase

      end

      else if(write_en == 1'b1) 
          begin
              case(way_selection)
              2'b00:begin
 
                         age_valid_dirty_0[set_id][1]    <= 1'b1;
                         age_valid_dirty_0[set_id][0]    <= 1'b0;
//                         tag_avd_memory_0[set_id][3:2]<=  2'b00;
                              
                              
                          
                    end
                    
              2'b01:begin

                         age_valid_dirty_1[set_id][1]    <= 1'b1;
                         age_valid_dirty_1[set_id][0]    <= 1'b0;
//                         tag_avd_memory_1[set_id][3:2]<=  2'b00;
                            
                             
                     end
                     
              2'b10:begin 
 
                         age_valid_dirty_2[set_id][1]    <= 1'b1;
                         age_valid_dirty_2[set_id][0]    <= 1'b0;
//                         tag_avd_memory_2[set_id][3:2]<=  2'b00;
               
                              
                             
                    end
                         
              2'b11:begin
      
                         age_valid_dirty_3[set_id][1]    <= 1'b1;
                         age_valid_dirty_3[set_id][0]    <= 1'b0; 
//                         tag_avd_memory_3[set_id][3:2]<=  2'b00;
                            
                              
                    end
              endcase
          end 
           

     end

end

always@(*)
begin 
mem_en_0_reg = 1'b0;
mem_en_1_reg = 1'b0;
mem_en_2_reg = 1'b0;
mem_en_3_reg = 1'b0;

read_write_mem_0_reg      = 1'b0;
read_write_mem_1_reg      = 1'b0;
read_write_mem_2_reg      = 1'b0;
read_write_mem_3_reg      = 1'b0;


tag_read_write  = 1'b0;

data_in_mem_0_reg    =  256'd0;
data_in_mem_1_reg    =  256'd0;
data_in_mem_2_reg    =  256'd0;
data_in_mem_3_reg    =  256'd0;

data_in_tag_mem_reg =92'd0;





    if(write_en == 1'b1 ) 
          begin
          tag_read_write  = 1'b1;
          
          
          
              case(way_selection)
              2'b00:begin
                         data_in_mem_0_reg         = data_in_l2;                                                
                         data_in_tag_mem_reg       = { data_in_tag_mem_buf[91:23], tag}; 
                         read_write_mem_0_reg      = 1'b1;
                         mem_en_0_reg              = 1'b1;
                     end
                     
              2'b01:begin 
                         data_in_mem_1_reg             = data_in_l2;
                         data_in_tag_mem_reg           = { data_in_tag_mem_buf[91:46], tag,data_in_tag_mem_buf[22:0]}; 
                         read_write_mem_1_reg          = 1'b1;
                         mem_en_1_reg                  = 1'b1;
                              
                             
                    end
                     
              2'b10:begin 
                         data_in_mem_2_reg             = data_in_l2;
                         data_in_tag_mem_reg           = { data_in_tag_mem_buf[91:69], tag,data_in_tag_mem_buf[45:0]}; 
                         read_write_mem_2_reg          = 1'b1;
                         mem_en_2_reg                  = 1'b1;
                              
                             
                    end
                         
              2'b11:begin
                         data_in_mem_3_reg         = data_in_l2;
                         data_in_tag_mem_reg       = {tag,data_in_tag_mem_buf[68:0]};
                         read_write_mem_3_reg      = 1'b1;
                         mem_en_3_reg              = 1'b1;
                              
                    end
              endcase
              
//              case(valid_4_bit)
//                         4'b0000:data_in_tag_mem_reg       = {69'd0, tag}; 
//                         4'b1000:data_in_tag_mem_reg       = {69'd0, tag}; 
//                         4'b1100:data_in_tag_mem_reg       = {46'd0,data_in_tag_mem_buf[45:23], tag}; 
//                         4'b1110:data_in_tag_mem_reg       = {23'd0,data_in_tag_mem_buf[68:23], tag}; 
//                         4'b1111:data_in_tag_mem_reg       = {data_in_tag_mem_buf[91:23], tag};
//                         default :data_in_tag_mem_reg       = {69'd0, tag};
//              endcase
              
          end 
           
        else if(read_data_fron_cache==1'b1)
        begin
             case(way_id)
                                2'b00: mem_en_0_reg              = 1'b1;     
                                2'b01: mem_en_1_reg              = 1'b1;  
                                2'b10: mem_en_2_reg              = 1'b1;   
                                2'b11: mem_en_3_reg              = 1'b1;
                               
                            endcase
            
        
        end
end

                                  
//// block selection logic for writing and removing


always@(*)
begin
way_selection = 2'b00; 


             ////  val 0 ,val 1,val 2 ,val 3
     valid_4_bit = {age_valid_dirty_0[set_id][1],age_valid_dirty_1[set_id][1],age_valid_dirty_2[set_id][1],age_valid_dirty_3[set_id][1]};
                 //// age 0, age 1,age 2,age 3
     age_4_bit = {
                   (age_valid_dirty_0[set_id][3:2] == 2'b11),
                   (age_valid_dirty_1[set_id][3:2] == 2'b11),
                   (age_valid_dirty_2[set_id][3:2] == 2'b11),
                   (age_valid_dirty_3[set_id][3:2] == 2'b11)
                 };
                 
     if( valid_4_bit == 4'b1111 )
     begin       
                           /////////   miss 
                case(age_4_bit)
                 4'b0001 : way_selection = 2'b11;
                 4'b0010 : way_selection = 2'b10;
                 4'b0100 : way_selection = 2'b01;
                 4'b1000 : way_selection = 2'b00;
                 default:  way_selection = 2'b00; 
          endcase
     end
     
     else
     begin                     /////// compulsary miss  
    
           case(valid_4_bit)           
                 4'b1110 : way_selection = 2'b11;
                 4'b1100 : way_selection = 2'b10;
                 4'b1000 : way_selection = 2'b01;
                 4'b0000 : way_selection = 2'b00;    
                 default : way_selection = 2'b00;          
           endcase
     end
end





/// fsm 

/// dff
always@(posedge clk )
begin
     if(rst)  pr_state <= 5'b00001;
     else     pr_state <= nxt_state;
end





// nxt state logic \
always@(*)
begin

data_l1_out       = 256'd0;
data_l1_valid_out = 1'b0;
hit_l1_out        = 1'b0;
write_en          = 1'b0;
lru_update        = 1'b0;
l2_req            = 1'b0;
mem_en_tag_reg    = 1'b0;
//en_tag_check     = 1'b0;
read_data_fron_cache = 1'b0;
nxt_state   =  idle ;
  
  
     case(pr_state)
     
     idle:    ///                     1   
     begin
          if(addr_valid_in)
          begin
               nxt_state   =  tag_en ;
               mem_en_tag_reg    = 1'b1;  
          end
          else      
          begin
                 nxt_state   =  idle ;
                 mem_en_tag_reg    = 1'b0;  
          end
               
     end 
 
     tag_en:      /////                       2   
     begin
                   
             
             if(data_valid_tag_mem == 1'b1)
             begin
                   nxt_state = tag_check;
                   
             end
             else
             begin                       
                   nxt_state = tag_en; 
                                      
             end
     end
     
     
  
     tag_check:
     begin     
            
              
                   
                if(hit == 1'b1 )
                begin
                         
                         hit_l1_out        = 1'b1;  //not using 
                         lru_update        = 1'b1; 
                         
                         data_l1_valid_out = data_valid_mem_0|data_valid_mem_1|data_valid_mem_2|data_valid_mem_3;
                         
                               begin
                                
                                    if(data_l1_valid_out == 1'b1)
                                    begin
                                         data_l1_out          = data_l1;
                                         read_data_fron_cache = 1'b0;
                                         nxt_state            = idle;
                                    
                                    end
                                    
                                    else
                                    begin
                                         data_l1_out         = 256'd0;
                                         read_data_fron_cache = 1'b0;
                                         nxt_state            = tag_check;  
                                         read_data_fron_cache = 1'b1;                               
                                    
                                    end
                                    
                               end
                 end                

                    
                 else
                    begin
                         nxt_state         = req_higher_level;
                         data_l1_out       = 256'd0;
                         data_l1_valid_out = 1'b0;
                         hit_l1_out        = 1'b0;
                         lru_update        = 1'b0;
                         
                    end      
              
                              
       end


     req_higher_level: 
     begin
     
         l2_req       = 1'b1; 
              if(data_valid_l2 == 1'b1 )
              begin   
                   write_en          = 1'b1; 
                   mem_en_tag_reg    = 1'b1;
                   nxt_state         = write_data;    
                    
              end
              
              else
              begin
                   nxt_state    = req_higher_level;    
             
              end
         end 
     
  
    write_data:
         begin
                  nxt_state  = tag_en;    
                  mem_en_tag_reg    = 1'b1;  
                  
                         
         end


     default : nxt_state  = idle;  
     endcase



end

endmodule 


