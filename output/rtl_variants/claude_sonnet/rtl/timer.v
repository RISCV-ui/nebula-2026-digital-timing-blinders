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
//reg [31:0]timer_counter_reg;

//reg complete;
///constants  


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
     //     data_out             <=32'd0; 
          
      end
      
      else if(addr_valid == 1'b1)
          begin
              
               case(addr[7:0])
             
                 8'h04: if(read_write) timer_compare_value <= data_in ;                     
                 8'h08:  if(read_write) timer_control_reg  <= data_in ;
                                                                                                                                                           
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
                 default: data_out = 32'd0;                                                                          
               endcase
    end
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
                     1'b0};

endmodule
