module gpio_controller(clk,rst, 
                       addr,addr_valid,read_write,data_in,data_out,
                       gpio_en,gpio_write,gpio_read,
                       int_out_gpio);
                       
input clk,rst;
input addr_valid, read_write;
input [31:0]addr, data_in;    
output reg [31:0]data_out;

output wire [31:0] gpio_en, gpio_write;
input wire  [31:0] gpio_read;
output wire int_out_gpio;


//// wire


/// regs

reg [31:0]direction_reg_gpio;   /// w 
reg [31:0]read_reg_gpio;       // r
reg [31:0]write_reg_gpio;      // w
reg [31:0]set_reg_gpio;        // w
reg [31:0]clr_reg_gpio;        // w
reg [31:0]int_mask_reg_gpio;   // w 
reg [31:0]int_set_reg_gpio;    // w 
reg [31:0]int_clr_reg_gpio;    // w
reg [31:0]int_status_reg_gpio; // r 
reg [31:0]int_level_edge_mode_reg_gpio; ///w 


reg [31:0]direction_reg;
reg [31:0]write_reg;
reg [31:0]read_reg;

reg [31:0]synch_reg1,synch_reg2;
reg [31:0]edge_trigger_int_reg;
reg [31:0]level_trigger_int_reg;
reg [31:0] mux4_1_out;
reg [31:0] mux_2_1_out;
reg [31:0]mux_2_1_mode;
// Magnitude of the sampled pin word, reported at 0x38. read_reg is a
// flop and magnitude_reg is a flop, so the square root sits on a
// clk_s2 register-to-register path.
reg [31:0]magnitude_reg;
wire [15:0] pin_magnitude;
wire [16:0] pin_magnitude_rem;

isqrt_restoring_32 gpio_magnitude(
    .radicand (read_reg),
    .root     (pin_magnitude),
    .rem_out  (pin_magnitude_rem)
);

///assign

assign gpio_en    = direction_reg;
assign gpio_write = write_reg;

assign int_out_gpio = |int_status_reg_gpio;

///sequential 

/// direction and write reg 
always@(posedge clk)
begin
     if(rst)
     begin
          direction_reg <= 32'd0;
          write_reg     <= 32'd0;
          read_reg      <= 32'd0;
          synch_reg1    <= 32'd0;
          synch_reg2    <= 32'd0; 
          read_reg_gpio <= 32'd0; 
          int_status_reg_gpio <= 32'd0;
          edge_trigger_int_reg <= 32'd0;
          level_trigger_int_reg <= 32'd0;
          
     end
 
     else
     begin
           direction_reg <=  direction_reg_gpio;
           write_reg     <=  (write_reg_gpio | set_reg_gpio)&(~clr_reg_gpio);
           synch_reg1    <=  gpio_read;
           
           ///read synch
           synch_reg2    <= synch_reg1;
           read_reg      <= synch_reg2;
           read_reg_gpio <= read_reg;
           
           /// int_status   
           
           edge_trigger_int_reg  <= synch_reg2 & int_mask_reg_gpio;
           level_trigger_int_reg <= synch_reg2 & int_mask_reg_gpio;
           
               
           int_status_reg_gpio <= ((int_mask_reg_gpio & mux_2_1_mode )|(int_set_reg_gpio))&(~int_clr_reg_gpio);
       
         
        
        
     end    

end

/// read 

// Interrupt mode muxing: purely combinational intermediates. Previously
// computed with blocking assignments inside the posedge-clk block above,
// which Verilator flags as BLKSEQ. Behaviour is unchanged -- they were
// read only by int_status_reg_gpio, whose non-blocking update still sees
// the same values.
always@(*)
begin
               case(int_level_edge_mode_reg_gpio[4:3])
                    2'b11:mux4_1_out = synch_reg2^edge_trigger_int_reg;  /// both_edge trigger 
                    2'b01:mux4_1_out = synch_reg2&(~edge_trigger_int_reg) ; ///  +ve 
                    2'b10:mux4_1_out = edge_trigger_int_reg&(~synch_reg2) ; /// - ve 
                    default: mux4_1_out =32'd0;
               endcase  
           
           
           
               case(int_level_edge_mode_reg_gpio[2:1]) 
                  2'b01: mux_2_1_out = ~ level_trigger_int_reg; /// 0 int 
                  2'b10: mux_2_1_out =  level_trigger_int_reg; /// 1 int trigger 
                  default: mux_2_1_out= 32'd0;
               
               endcase
           
               case(int_level_edge_mode_reg_gpio[0]) ///  mode
                  1'b0: mux_2_1_mode = mux_2_1_out;   //  level
                  1'b1: mux_2_1_mode =  mux4_1_out;   //  edge 
                  default: mux_2_1_mode = 32'd0;
               
               endcase
end

always@(*)
begin
data_out = 32'd0;
      if(addr_valid)
      begin
           case(addr[7:0])
                 8'h10:data_out   = direction_reg_gpio;  
                                     
                 8'h14: data_out  = read_reg_gpio ;  
                             
                              
                              
                 8'h18: data_out  =write_reg_gpio ;  
                              
                 8'h1c: data_out  = set_reg_gpio;    
 
                                            
                                            
                8'h20:data_out  = clr_reg_gpio;  
                             
                8'h24:data_out  = int_mask_reg_gpio;    
                             
                8'h28: data_out = int_set_reg_gpio;    
                                            
                                        
                8'h2c:data_out = int_clr_reg_gpio;    
                                           
                              
                8'h30:  data_out = int_status_reg_gpio;    
                                         
                                        
                8'h34:data_out   = int_level_edge_mode_reg_gpio;

                8'h38:data_out   = magnitude_reg;
                             
                default : data_out = 32'd0;  
                  
                  endcase

             end


end

//write regs 
always@(posedge clk)
begin
     if(rst)
     begin
          direction_reg_gpio            <=32'd0;                                   
          write_reg_gpio                <=32'd0;                   
          set_reg_gpio                  <=32'd0;                     
          clr_reg_gpio                  <=32'd0;                     
          int_mask_reg_gpio             <=32'd0;                
          int_set_reg_gpio              <=32'd0;                 
          int_clr_reg_gpio              <=32'd0;                                                       
          int_level_edge_mode_reg_gpio  <=32'd0;     
     end

     
    else if(addr_valid == 1'b1)
          begin
              
              
               case(addr[7:0])
                 8'h10:
                              begin
                                    if(read_write) direction_reg_gpio <= data_in ;
                                     
                              end         
                 8'h18:
                              begin
                                    if(read_write) write_reg_gpio  <= data_in ;
                                    
                              end
                              
                                           
                              
                 8'h1c:
                              begin
                                    if(read_write) set_reg_gpio    <= data_in ;
                                    
                              end  
                                            
                                            
                8'h20:
                              begin
                                    if(read_write) clr_reg_gpio    <= data_in ;
                                    
                              end    
                             
                8'h24:
                              begin
                                    if(read_write) int_mask_reg_gpio <= data_in ;
                                    
                              end  
                             
                8'h28:
                              begin
                                    if(read_write) int_set_reg_gpio <= data_in ;
                                    
                              end               
                                        
                8'h2c:
                              begin
                                    if(read_write) int_clr_reg_gpio <= data_in ;
                                 
                              end              
                                            
                                          
                8'h34:
                              begin
                                    if(read_write) int_level_edge_mode_reg_gpio <= data_in ;
                              
                                         
                          
                              end
                              
                              
              
                  
                  default: ;  // unmapped address: no register written
                  endcase
                  
          end


end

//// sampled-pin magnitude
always@(posedge clk)
begin
     if(rst) magnitude_reg <= 32'd0;
     else    magnitude_reg <= {16'd0, pin_magnitude};
end

// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     addr[31:8],
                     // Only the root is reported; the residue would tell
                     // software how far off a perfect square the sample was,
                     // which nothing asks for yet.
                     pin_magnitude_rem,
                     1'b0};

endmodule
