module timer(clk,rst,addr,addr_valid,read_write,data_in,data_out,int_out_timer);


input clk,rst,addr_valid,read_write;
input [31:0]addr,data_in;

output int_out_timer;
output reg [31:0]data_out;

/// wire



//// regs

reg [31:0]timer_current_value;
reg [31:0]timer_compare_value;
reg [31:0]timer_control_reg;
reg [31:0]timer_status_reg;
// Rate conversion. Software writes a scale factor to 0x10 and reads the
// converted tick count back from 0x14; the product is registered so the
// multiply sits on a clk_s1 register-to-register path.
reg [31:0]timer_scale_reg;
reg [31:0]timer_scaled_reg;
//reg [31:0]timer_counter_reg;

//reg complete;
///constants  


wire [63:0] timer_scaled_product;

mult_array_32 timer_rate_mul(
    .a       (timer_current_value),
    .b       (timer_scale_reg),
    .product (timer_scaled_product)
);

//// all assignments
assign int_out_timer = timer_status_reg[0]&timer_control_reg[1];

// Combinational match. The counter has to be frozen by THIS, not by
// timer_status_reg, or it overshoots the compare value by one: status is a
// flop, so it is still 0 on the edge where the match happens and the counter
// takes one more increment before the stop condition is visible.
wire timer_match = timer_control_reg[0] &&
                   (timer_current_value == timer_compare_value);

// Write-1-to-clear of the status flag, at the same offset it reads from.
wire status_clear = addr_valid && read_write &&
                    (addr[7:0] == 8'h0c) && data_in[0];
/// sequential 

///counter 
always@(posedge clk)
begin
     if(rst) timer_current_value <=  32'd0; 
     // Clearing the status flag re-arms the one shot: without this the counter
     // sits on the compare value for ever and the timer can only fire once
     // per reset.
     else if(status_clear)                            timer_current_value <=  32'd0;
     else if(timer_control_reg[0]==1'b1 && !timer_match) timer_current_value <=  timer_current_value + 32'd1;
     

end

/// reg update

always@(posedge clk)
begin
     if(rst)
     begin
   //       timer_current_value  <=32'd0;
          timer_compare_value  <=32'd0;
          timer_control_reg    <=32'd0;
          timer_scale_reg      <=32'd0;
     //     data_out             <=32'd0; 
          
      end
      
      else if(addr_valid == 1'b1)
          begin
              
               case(addr[7:0])
             
                 8'h04: if(read_write) timer_compare_value <= data_in ;                     
                 8'h08:  if(read_write) timer_control_reg  <= data_in ;
                 8'h10:  if(read_write) timer_scale_reg    <= data_in ;
                                                                                                                                                           
               default: ;  // unmapped address: no register written
               endcase
          
          end
      
end



//// read 
always@(*)
begin
data_out = 32'd0;


  if(addr_valid == 1'b1 && read_write == 1'b0)
    begin  
     case(addr[7:0])
                 8'h00: data_out  = timer_current_value;           
                 8'h04: data_out = timer_compare_value;                                               
                 8'h08: data_out = timer_control_reg;                               
                 8'h0c: data_out = timer_status_reg;     
                 8'h10: data_out = timer_scale_reg;
                 8'h14: data_out = timer_scaled_reg;
                 default: data_out = 32'd0;                                                                          
               endcase
    end
end

//// rate conversion result
//
// Registering the low word here is what puts mult_array_32 on a real
// register-to-register path in the clk_s1 domain: timer_current_value and
// timer_scale_reg are flops, timer_scaled_reg is a flop, and the whole
// 32-adder array sits between them.
always@(posedge clk)
begin
     if(rst) timer_scaled_reg <= 32'd0;
     else    timer_scaled_reg <= timer_scaled_product[31:0];
end

//// compare and interrupt

always@(posedge clk)
begin
     // Sticky: set on the match, held until software writes 1 to bit 0 of
     // 0x0c. It used to be re-evaluated every cycle, which made it a
     // one-cycle pulse -- the interrupt was a blip, the counter never stopped,
     // and a polling read of 0x0c essentially never caught the flag.
     if(rst)               timer_status_reg <= 32'd0;
     else if(status_clear) timer_status_reg <= 32'd0;
     else if(timer_match)  timer_status_reg <= 32'd1;
    
end    


// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     addr[31:8],
                     // Only the low word of the 64-bit product is exposed at
                     // 0x14; the high word is left for a future 0x18.
                     timer_scaled_product[63:32],
                     1'b0};

endmodule
