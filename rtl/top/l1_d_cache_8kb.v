`timescale 1ns / 1ps



module l1_d_cache_8kb(clk,rst,addr_cpu_in,addr_valid_in,read_write_in,data_l1_out,data_l1_in,data_l1_valid,
                             addr_l2,addr_l2_valid,read_write_l2,data_out_l2_write,data_in_l2,data_valid_l2);

input clk,rst;

/// cpu l1 inteface 
input [31:0]addr_cpu_in;
input addr_valid_in,read_write_in;
input [255:0] data_l1_in;


output reg [255:0]data_l1_out;
output reg data_l1_valid;



/// l1 l2 interface 

output reg [31:0]addr_l2;
output reg addr_l2_valid;
output reg [255:0]data_out_l2_write;
output reg read_write_l2;

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



reg read_write_mem_0_reg;
reg read_write_mem_1_reg;
reg read_write_mem_2_reg;
reg read_write_mem_3_reg;

reg mem_en_0_reg;
reg mem_en_1_reg;
reg mem_en_2_reg;
reg mem_en_3_reg;

reg mem_en_tag_reg;


reg [3:0]age_valid_dirty_0[0:63];
reg [3:0]age_valid_dirty_1[0:63];
reg [3:0]age_valid_dirty_2[0:63];
reg [3:0]age_valid_dirty_3[0:63];



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
reg [1:0]way_selection;

//*reg en_tag_check;

//reg data_l1_valid_out_reg;

reg block_removing_true;



//// fsm regs
reg set_dirty_bit     ;
reg write_en_on_hit   ;
reg en_mem_sel        ;
reg write_en_l1_to_l2 ;
reg read_write_to_l2  ;
reg clear_dirty_bit   ;
reg  write_en_l1     ; 
reg data_read_en_cpu;
reg data_l1_valid_out;

/// wire decl
wire [5:0] set_id;
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

wire unused;
wire data_valid_tag_mem;
wire data_valid_mem_0;
wire data_valid_mem_1;
wire data_valid_mem_2;
wire data_valid_mem_3;


//// assign 
assign  set_id    = addr_cpu_in[8:3];   
assign  tag       = addr_cpu_in[31:9];
assign unused     = addr_cpu_in[2:0];

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

                            


////// combo 

///////   tag identification

tag_memory_92x64  tag_mem_0(clk,rst,mem_en_tag,{26'd0,set_id},read_write,data_in_tag_mem,data_out_tag_mem,data_valid_tag_mem);

id_memory_256x64   i_mem_0(clk,rst,mem_en_0,{26'd0,set_id},read_write_mem_0,data_in_mem_0,data_out_mem_0,data_valid_mem_0);
id_memory_256x64   i_mem_1(clk,rst,mem_en_1,{26'd0,set_id},read_write_mem_1,data_in_mem_1,data_out_mem_1,data_valid_mem_1);
id_memory_256x64   i_mem_2(clk,rst,mem_en_2,{26'd0,set_id},read_write_mem_2,data_in_mem_2,data_out_mem_2,data_valid_mem_2);
id_memory_256x64   i_mem_3(clk,rst,mem_en_3,{26'd0,set_id},read_write_mem_3,data_in_mem_3,data_out_mem_3,data_valid_mem_3);


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
data_l1_out               = 256'd0 ;
    
data_out_l2_write   = 256'd0;
addr_l2_valid       = 1'b0;
read_write_l2       = 1'b0;
addr_l2             = 32'd0;


    if(data_read_en_cpu == 1'b1)
    begin
      case(way_id)
          2'b00:data_l1_out = data_out_mem_0;       
          2'b01:data_l1_out = data_out_mem_1;   
          2'b10:data_l1_out = data_out_mem_2;       
          2'b11:data_l1_out = data_out_mem_3;
      endcase
    end
    else if(write_en_l1_to_l2 == 1'b1)
    begin
         
 //        if(block_removing_true == 1'b1)
 //        begin
         
         
                 case(way_selection)
                      2'b00:
                      begin
                           data_out_l2_write = (read_write_to_l2)?data_out_mem_0:256'd0;  
                           addr_l2           = (read_write_to_l2)?({data_in_tag_mem_buf[22:0],addr_cpu_in[8:3],3'b000}):( {addr_cpu_in[31:3],3'b000} );
                           addr_l2_valid     = 1'b1;
                           read_write_l2     = (read_write_to_l2)?1'b1:1'b0;
                      end
                      
                      2'b01:
                      begin
                           data_out_l2_write = (read_write_to_l2)?data_out_mem_1:256'd0;   
                           addr_l2           = (read_write_to_l2)?({data_in_tag_mem_buf[45:23],addr_cpu_in[8:3],3'b000}):( {addr_cpu_in[31:3],3'b000} );
                           addr_l2_valid     = 1'b1;
                           read_write_l2     = (read_write_to_l2)?1'b1:1'b0;
                      end
                      
                      2'b10:
                      begin
                           data_out_l2_write = (read_write_to_l2)?data_out_mem_2:256'd0;  
                           addr_l2           = (read_write_to_l2)?({data_in_tag_mem_buf[68:46],addr_cpu_in[8:3],3'b000}):( {addr_cpu_in[31:3],3'b000} );
                           addr_l2_valid     = 1'b1;
                           read_write_l2     = (read_write_to_l2)?1'b1:1'b0;
                      end
                      
                      2'b11:
                      begin
                           data_out_l2_write = (read_write_to_l2)?data_out_mem_3:256'd0;  
                           addr_l2           = (read_write_to_l2)?({data_in_tag_mem_buf[91:69],addr_cpu_in[8:3],3'b000}):( {addr_cpu_in[31:3],3'b000} );
                           addr_l2_valid     = 1'b1;
                           read_write_l2     = (read_write_to_l2)?1'b1:1'b0;
                      end
                  
                 endcase
    
   //     end
        
        
    end
end



always@(*)
begin
block_removing_true = 1'b0;

 case(way_selection)
          2'b00:block_removing_true = age_valid_dirty_0[set_id][0];  
          2'b01:block_removing_true = age_valid_dirty_1[set_id][0];   
          2'b10:block_removing_true = age_valid_dirty_2[set_id][0];        
          2'b11:block_removing_true = age_valid_dirty_3[set_id][0];  
         endcase
  

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
                
                if(set_dirty_bit == 1'b1)        age_valid_dirty_0[set_id][0]    <=  1'b1;
                
                
                 
                                                  
          
          end
          
         2'b01: 
          begin
                age_valid_dirty_0[set_id][3:2] <= (age_w0 < age_w1)?(age_w0+2'b01):age_w0;//(age_w0 < age_w1)?(age_w0 + 1):age_w0;                        
                age_valid_dirty_1[set_id][3:2]<=  2'b00;                                                                
                age_valid_dirty_2[set_id][3:2]<= (age_w2 < age_w1)?(age_w2 + 2'b01):age_w2;                                               
                age_valid_dirty_3[set_id][3:2]<= (age_w3 < age_w1)?(age_w3 + 2'b01):age_w3;
                
                if(set_dirty_bit == 1'b1)        age_valid_dirty_1[set_id][0]    <=  1'b1;
         
          end
          
          2'b10: 
          begin
                age_valid_dirty_0[set_id][3:2] <= (age_w0 < age_w2)?(age_w0 + 2'b01):age_w0;                         
                age_valid_dirty_1[set_id][3:2]<= (age_w1 < age_w2)?(age_w1 + 2'b01):age_w1;                                                               
                age_valid_dirty_2[set_id][3:2]<=  2'b00;                                                                     
                age_valid_dirty_3[set_id][3:2]<= (age_w3 < age_w2)?(age_w3 + 2'b01):age_w3;
                
               if(set_dirty_bit == 1'b1)        age_valid_dirty_2[set_id][0]    <=  1'b1;
              
         
          end
          
          2'b11: 
          begin
                age_valid_dirty_0[set_id][3:2] <=(age_w0 < age_w3)?(age_w0 + 2'b01):age_w0;                        
                age_valid_dirty_1[set_id][3:2]<= (age_w1 < age_w3)?(age_w1 + 2'b01):age_w1;                                                               
                age_valid_dirty_2[set_id][3:2]<= (age_w2 < age_w3)?(age_w2 + 2'b01):age_w2;                                                                      
                age_valid_dirty_3[set_id][3:2]<= 2'b00;
          
                if(set_dirty_bit == 1'b1)        age_valid_dirty_3[set_id][0]    <=  1'b1;
              
                
          end
           
         endcase

      end
      
      
     else if (write_en_l1 == 1'b1) 
     begin
          case(way_selection)
              2'b00:age_valid_dirty_0[set_id][1]    <= 1'b1;
              2'b01:age_valid_dirty_1[set_id][1]    <= 1'b1;                
              2'b10:age_valid_dirty_2[set_id][1]    <= 1'b1;     
              2'b11:age_valid_dirty_3[set_id][1]    <= 1'b1;  
              endcase
     
     
     
     end


      else if(clear_dirty_bit == 1'b1) 
          begin
              case(way_selection)
              2'b00:age_valid_dirty_0[set_id][0]    <= 1'b0;               
              2'b01:age_valid_dirty_1[set_id][0]    <= 1'b0;                    
              2'b10:age_valid_dirty_2[set_id][0]    <= 1'b0;                           
              2'b11:age_valid_dirty_3[set_id][0]    <= 1'b0;  
              endcase
          end 
           

     end

end

always@(*)
begin 


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





    if(write_en_on_hit == 1'b1 ) 
          begin
               case(way_id)
                   2'b00: 
                    begin 
                          data_in_mem_0_reg         = data_l1_in;
                          read_write_mem_0_reg      = 1'b1; 
                    end
                   2'b01:
                   begin 
                          data_in_mem_1_reg         = data_l1_in;
                          read_write_mem_1_reg      = 1'b1; 
                    end
                   
                   2'b10: 
                   begin 
                          data_in_mem_2_reg         = data_l1_in;
                          read_write_mem_2_reg      = 1'b1; 
                    end
                   2'b11: 
                   begin 
                          data_in_mem_3_reg         = data_l1_in;
                          read_write_mem_3_reg      = 1'b1; 
                    end  
                       
               endcase
          end
               
          else if(write_en_l1 == 1'b1)
          begin
 
                tag_read_write  = 1'b1;
          
          
          
              case(way_selection)
              2'b00:begin
                         data_in_mem_0_reg         = data_in_l2;                                                
                         data_in_tag_mem_reg       = { data_in_tag_mem_buf[91:23], tag}; 
                         read_write_mem_0_reg      = 1'b1;
     
                     end
                     
              2'b01:begin 
                         data_in_mem_1_reg             =data_in_l2; 
                         data_in_tag_mem_reg           = { data_in_tag_mem_buf[91:46], tag,data_in_tag_mem_buf[22:0]}; 
                         read_write_mem_1_reg          = 1'b1;
             
                              
                             
                    end
                     
              2'b10:begin 
                         data_in_mem_2_reg             = data_in_l2; 
                         data_in_tag_mem_reg           = { data_in_tag_mem_buf[91:69], tag,data_in_tag_mem_buf[45:0]}; 
                         read_write_mem_2_reg          = 1'b1;
                    
                              
                             
                    end
                         
              2'b11:begin
                         data_in_mem_3_reg         =  data_in_l2; 
                         data_in_tag_mem_reg       = {tag,data_in_tag_mem_buf[68:0]};
                         read_write_mem_3_reg      = 1'b1;
                       
                              
                    end
              endcase
              

              
          end 
           

end

always@(*)
begin

mem_en_0_reg = 1'b0;
mem_en_1_reg = 1'b0;
mem_en_2_reg = 1'b0;
mem_en_3_reg = 1'b0;


     if(hit && !data_l1_valid_out)
     begin
           case(way_id)
                 2'b00: mem_en_0_reg              = 1'b1;     
                 2'b01: mem_en_1_reg              = 1'b1;  
                 2'b10: mem_en_2_reg              = 1'b1;   
                 2'b11: mem_en_3_reg              = 1'b1;
                
             endcase
                      
      end
      
      else if(en_mem_sel == 1'b1)
      begin                      
            case(way_selection)
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
                           /////////     conflict miss  
                      
                           
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


data_l1_valid_out = 1'b0;
lru_update        = 1'b0;
mem_en_tag_reg    = 1'b0;
nxt_state         =  idle ;
//read_write_l2     = 1'b0;  



set_dirty_bit     = 1'b0;
write_en_on_hit   = 1'b0;
en_mem_sel        = 1'b0;
write_en_l1_to_l2 = 1'b0;
read_write_to_l2  = 1'b0;
clear_dirty_bit   = 1'b0;
write_en_l1       = 1'b0;
data_read_en_cpu  = 1'b0;
data_l1_valid     = 1'b0;


  
     case(pr_state)
     
     idle:    ///                     1   
     begin
          if(addr_valid_in)
          begin
               nxt_state         =  tag_en ;
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
     
     
  
     tag_check:                                      ////4
     begin     
          case({hit,read_write_in})
          
          2'b00:
          begin
               nxt_state   =   req_higher_level;     
          end     
          
          2'b01:
          begin
               nxt_state   =   req_higher_level;   
          end     
          
          2'b10:
          begin
               
              
                     data_l1_valid_out = data_valid_mem_0|data_valid_mem_1|data_valid_mem_2|data_valid_mem_3; 
                        
                        if(data_l1_valid_out == 1'b1)
                        begin
                             data_read_en_cpu  = 1'b1;  
                             data_l1_valid     = 1'b1;
                             nxt_state         = idle;   
                             lru_update        = 1'b1;  
                        end
                        
                        else 
                        begin
                             nxt_state         =   tag_check;   
                             lru_update        =   1'b0;                    
                        end
      
                  
          end
          
          2'b11:
          begin
               nxt_state            = idle; 
               lru_update           = 1'b1;
               set_dirty_bit        = 1'b1; 
               write_en_on_hit      = 1'b1;
          
          end        
          endcase   
     end
         

     req_higher_level:                  ////                          8
     begin
          if(block_removing_true == 1'b1)     //// 
          begin
          //     mem_en_tag_reg     = 1'b1; 
               en_mem_sel    = 1'b1;
               nxt_state     =   req_higher_level;
               
               data_l1_valid_out = data_valid_mem_0|data_valid_mem_1|data_valid_mem_2|data_valid_mem_3; 
                 
                 if(data_l1_valid_out == 1'b1)
                 begin                
                      write_en_l1_to_l2  = 1'b1;
                      read_write_to_l2   = 1'b1; 
                      clear_dirty_bit    = 1'b1;       
                end                                     
          end
          
          else
          begin
               mem_en_tag_reg    = 1'b0; 
               en_mem_sel         = 1'b0;
               write_en_l1_to_l2  =   1'b1 ;
               read_write_to_l2   =   1'b0; 
                   
                   if(data_valid_l2 == 1'b1)
                   begin
                        nxt_state       = write_data;    
                        write_en_l1     = 1'b1;   
                        mem_en_tag_reg    = 1'b1;
                        en_mem_sel         = 1'b1;
                   end
                   
                   else 
                   begin 
                        nxt_state     = req_higher_level;
                        write_en_l1     = 1'b0; 
                       
                   end 
   
          
          end
                 
          
         
     end      
  
    write_data:     ///                                             16
         begin
                  nxt_state  = tag_en;    
                  mem_en_tag_reg    = 1'b1;  
                  
                         
         end


     default : nxt_state  = idle;  
     endcase



end


endmodule 


