module dma_controller(clk,rst, 
                      addr,addr_valid,read_write,
                      data_in,data_out,
                      addr_src_dma,addr_valid_src_dma,read_req_valid_src_dma,data_in_src_dma,
                      addr_dest_dma,addr_valid_dest_dma,write_req_valid_dest_dma,write_ack_dest_dma,data_out_dest_dma,
                      int_out_dma,dma_bus_req,dam_bus_req_burst,dma_bus_grant
         
                      );
                                            
input clk,rst;

input [31:0]addr,data_in_src_dma,data_in;
input addr_valid,read_req_valid_src_dma,read_write;

output wire [31:0]addr_src_dma;
output  wire addr_valid_src_dma ;
output reg [31:0] data_out;                   

// write_req_valid_dest_dma is the DMA's write REQUEST to the bus wrapper
// (mirroring addr_valid_dest_dma); write_ack_dest_dma is the wrapper's
// completion acknowledge. These were originally one net used for both
// directions, which left the request side undriven.
input write_ack_dest_dma,dma_bus_grant;

output wire[31:0]addr_dest_dma,data_out_dest_dma;
output wire addr_valid_dest_dma;
output wire write_req_valid_dest_dma;

output wire  int_out_dma,dma_bus_req,dam_bus_req_burst;





/// wirea
wire [32:0]size_m4_dma;
wire done_burst_transfer;

////regs
reg [31:0] src_address_dma;
reg [31:0] dest_address_dma;
reg [31:0] size_dma;
reg [31:0] control_dma;
reg [31:0] status_dma;
reg [31:0] burst_length_dma;

reg [31:0] src_addr_counter_dma;
reg [31:0] dest_addr_counter_dma;
reg [31:0]burst_addr_counter_dam;
reg burst_counter_reset;

reg [2:0]pr_state,nxt_state;

reg dma_src_valid_internal;
reg dma_dest_valid_internal;

reg [31:0]buffer_dma;
reg [31:0]size_counter_dma;

reg update_src_addr;
reg update_dest_addr;
reg done_transfer;

reg bus_req_dma_mode;
reg bus_req_dma_burst_mode;

reg load_src_dest_addr;
reg update_burst_counter;
reg update_size_counter;


//// parameters 

parameter idle = 3'b000;
parameter req_bus =3'b001;
parameter read_data = 3'b011;
parameter write_data = 3'b010;
parameter update_addrs =3'b110;


/// all assign ment

// src side
assign addr_src_dma       =  (dma_src_valid_internal)? src_addr_counter_dma: 32'd0;
assign addr_valid_src_dma =  (dma_src_valid_internal)? 1'b1: 1'd0;

// dest side

assign addr_dest_dma       =     (dma_dest_valid_internal)? dest_addr_counter_dma : 32'd0;
assign data_out_dest_dma   =     (dma_dest_valid_internal)? buffer_dma :32'd0;
assign addr_valid_dest_dma =     (dma_dest_valid_internal)? 1'b1: 1'd0;
assign write_req_valid_dest_dma= (dma_dest_valid_internal)? 1'b1: 1'd0;

//// interrupt 
// status_dma[0], not done_transfer. done_transfer is a combinational pulse
// that is high for the single update_addrs cycle of the last beat, so the
// interrupt was one cycle wide and a level-sensitive controller could miss it
// entirely. status_dma[0] is the sticky version of the same event.
assign int_out_dma = control_dma[3]&status_dma[0];

// A write to the control register with the start bit set re-arms the engine.
// idle only leaves for req_bus when status_dma[0] is 0, and status_dma[0] was
// set on completion and never cleared -- so the controller ran exactly one
// transfer per reset and then sat in idle for ever.
wire start_write = addr_valid && read_write &&
                   (addr[7:0] == 8'h4c) && data_in[0];

//// bus req dam and burest mode 
assign dma_bus_req = bus_req_dma_mode;
assign dam_bus_req_burst = bus_req_dma_burst_mode;

/// requried for last addr , src addr + size * 4 -4,
assign size_m4_dma = ({size_dma[29:0],2'b00} + 32'hffff_fffc);

///
assign done_burst_transfer = (burst_length_dma == burst_addr_counter_dam);


//// sequential 

/// dff
always@(posedge clk)
begin
     if(rst)pr_state <= 3'd0;
     else pr_state   <= nxt_state ;
end


/// next_state and output logic

//wire start;
always@(*)
begin
nxt_state               = 3'd0;
dma_src_valid_internal  = 1'b0;
dma_dest_valid_internal = 1'b0;
update_src_addr         = 1'b0;
update_dest_addr        = 1'b0;
load_src_dest_addr      = 1'b0;
done_transfer           = 1'b0;
//done_burst_transfer     = 1'b0;
bus_req_dma_mode        = 1'b0;
bus_req_dma_burst_mode  = 1'b0;
burst_counter_reset     = 1'b0;
update_burst_counter    = 1'b0;
update_size_counter     = 1'b0;

     case(pr_state)
           
            idle:     begin
                             nxt_state    = (control_dma[0]== 1'b1 && status_dma[0]==1'b0 )? req_bus : idle;
                             load_src_dest_addr = (control_dma[0]== 1'b1 && done_transfer==1'b0 )?1'b1 :1'b0;
                             bus_req_dma_mode       = 1'b0;
                             bus_req_dma_burst_mode = 1'b0;

                       end


            req_bus:    begin
                             nxt_state   = (dma_bus_grant)? read_data :  req_bus;
                             bus_req_dma_mode       = 1'b1;
                             bus_req_dma_burst_mode = control_dma[4];
                             load_src_dest_addr = 1'b0;                             

                          
                        end 
                         
            read_data : begin
                         
                              nxt_state   =    (read_req_valid_src_dma)? write_data : read_data;
                              dma_src_valid_internal =  1'b1;
                              bus_req_dma_mode       = 1'b1;
                              bus_req_dma_burst_mode = control_dma[4];
                             
                         end
            write_data : begin
            
                              nxt_state =  (write_ack_dest_dma)?  update_addrs : write_data; 
                              dma_dest_valid_internal = 1'b1;
                              bus_req_dma_mode       = 1'b1;
                              bus_req_dma_burst_mode = control_dma[4];
                              
                         end    
                  
            update_addrs : begin
                                
                                update_src_addr   =  1'b1;
                                update_dest_addr  =  1'b1;
                                update_burst_counter = 1'b1;
                                update_size_counter = 1'b1;
                                bus_req_dma_burst_mode = control_dma[4];
                                
                                // size_m4_dma alone: size*4-4 is the byte offset of the
                                // last beat, and size_counter_dma counts bytes moved from
                                // zero. Adding src_address_dma made the transfer length
                                // depend on where the source happened to live -- src 0x20
                                // with size 4 moved 12 words instead of 4.
                                done_transfer     =  (size_m4_dma[31:0]== size_counter_dma)? 1'b1: 1'b0;
                          
                                bus_req_dma_mode  = 1'b0;
                                
                                
                                if (burst_length_dma  == burst_addr_counter_dam)
                                    begin
                                     //    done_burst_transfer = 1'b1;
                                         burst_counter_reset = 1'b1;
                                         bus_req_dma_burst_mode = 1'b0;
                                    end
                                
                                    if(done_transfer) nxt_state = idle;
                                    else if(!done_burst_transfer && control_dma[4] )nxt_state = read_data;
                                    else nxt_state = req_bus;
                                             
                           end    
      
     
              default : nxt_state = idle;
     
     
     
     
     endcase
     



end

//////  buffering the input data

always@(posedge clk)
begin
     if(rst) buffer_dma <= 32'd0;
     else if(dma_src_valid_internal)buffer_dma <= data_in_src_dma;
        
end

///src increment 
always@(posedge clk)
begin
     if(rst) src_addr_counter_dma <= 32'd0;
     else if(load_src_dest_addr)src_addr_counter_dma <= src_address_dma;
     else if(update_src_addr && control_dma[1])src_addr_counter_dma <= src_addr_counter_dma + 32'd4;     
end

///dest increment 
always@(posedge clk)
begin
     if(rst) dest_addr_counter_dma <= 32'd0;
     else if(load_src_dest_addr)dest_addr_counter_dma <= dest_address_dma;
     else if(update_dest_addr && control_dma[2] )dest_addr_counter_dma <= dest_addr_counter_dma + 32'd4;     
end



///size  increment 
always@(posedge clk)
begin
     if(rst) size_counter_dma <= 32'd0;
     // Reloaded with the src/dest counters. It used to persist across
     // transfers, so even once the engine could be restarted the second
     // transfer's done comparison was already satisfied.
     else if(load_src_dest_addr) size_counter_dma <= 32'd0;
     else if(update_size_counter && control_dma[0] )size_counter_dma <= size_counter_dma + 32'd4;     
end


///burst counter 
always@(posedge clk)
begin
     if(rst) burst_addr_counter_dam <= 32'd1; 
     else if(burst_counter_reset) burst_addr_counter_dam <= 32'd1;
     else if(control_dma[4]&&update_burst_counter )burst_addr_counter_dam <= burst_addr_counter_dam + 32'd1;     
end

//// status updatea
always@(posedge clk)
if(rst)               status_dma        <=32'd0;    
else if(start_write)  status_dma        <=32'd0;
else if(done_transfer)status_dma   <= {{29{1'b0}}, control_dma[3], ~done_transfer & control_dma[0],1'b1  };

//// read write to registers


always@(posedge clk)
begin
     if(rst)
     begin
          src_address_dma          <=32'd0;
          dest_address_dma         <=32'd0;
          size_dma                 <=32'd0;
          control_dma              <=32'd0; 
          burst_length_dma         <=32'd0;    
       
       
       end      
      
      else if(addr_valid == 1'b1)
          begin
              
              
               case(addr[7:0])
                 8'h40:if(read_write) src_address_dma <= data_in ;
                 8'h44: if(read_write) dest_address_dma <= data_in ;                 
                 8'h48:  if(read_write) size_dma <= data_in ;      
                 8'h4c: if(read_write) control_dma <= data_in ;            
                 8'h54: if(read_write) burst_length_dma <= data_in ;              
                                                          
        
               default: ;  // unmapped address: no register written
               endcase
          
          end
      
end

always@(*)
begin
data_out = 32'd0;
   if(addr_valid == 1'b1 && read_write == 1'b0)
     begin
     case(addr[7:0])
                 8'h40: data_out   = src_address_dma;                 
                 8'h44: data_out   = dest_address_dma;                    
                 8'h48: data_out   = size_dma;                     
                 8'h4c: data_out   = control_dma;                  
                 8'h50: data_out   = status_dma;                  
                 8'h54: data_out   = burst_length_dma;                           
                 default: data_out =32'd0;

                              

        endcase
     end
end






// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     addr[31:8], size_m4_dma[32],
                     1'b0};

endmodule
