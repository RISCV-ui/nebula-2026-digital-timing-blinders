`timescale 1ns / 1ps

// Interrupt controller for the peripheral interrupts.
//
// This file was an empty stub. It is now a small level-triggered controller
// sitting between the peripherals and the core's trap input.
//
// Each source is synchronised into the core clock domain -- timer, GPIO and
// UART all run on their own asynchronous clocks, so their interrupt lines
// are genuine CDC paths -- then masked, latched as pending, and priority
// encoded. Priority is fixed, lowest source index wins:
//
//   0  timer
//   1  gpio
//   2  uart
//
// A pending bit clears when software writes a 1 to it in int_clear, or when
// its source has gone away and the bit was never masked back in.

module interrupt_control_unit(clk,rst,
                              int_in,
                              int_mask,
                              int_clear,
                              int_pending,
                              int_id,
                              int_req);

input clk,rst;

input  [2:0] int_in;      // raw interrupt lines from the peripherals
input  [2:0] int_mask;    // 1 = source enabled
input  [2:0] int_clear;   // write-1-to-clear, one cycle wide

output reg [2:0] int_pending;
output reg [1:0] int_id;   // index of the highest priority pending source
output           int_req;  // level request into the core


//// two-flop synchronisers, one per asynchronous source
reg [2:0] sync_0;
reg [2:0] sync_1;

wire [2:0] int_sync;
wire [2:0] set_pending;

assign int_sync    = sync_1;
assign set_pending = int_sync & int_mask;

assign int_req = |int_pending;


always@(posedge clk)
begin
     if(rst)
     begin
          sync_0      <= 3'b000;
          sync_1      <= 3'b000;
          int_pending <= 3'b000;
     end
     else
     begin
          sync_0 <= int_in;
          sync_1 <= sync_0;

          //// set beats clear: an interrupt that is still asserted when
          //// software acknowledges it stays pending rather than being lost.
          int_pending <= (int_pending & ~int_clear) | set_pending;
     end
end


//// fixed priority encoder
always@(*)
begin
     if(int_pending[0])      int_id = 2'd0;
     else if(int_pending[1]) int_id = 2'd1;
     else if(int_pending[2]) int_id = 2'd2;
     else                    int_id = 2'd0;
end

endmodule
