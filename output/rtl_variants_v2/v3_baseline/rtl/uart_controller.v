`timescale 1ns / 1ps

// 8N1 UART, memory-mapped peripheral.
//
// Same shape as timer.v / gpio_controller.v / dma_controller.v: a flat
// register file addressed by {addr, addr_valid, read_write}, with
// read_write == 1 meaning write and 0 meaning read, so it drops straight
// into the axi_lite_* wrapper pattern used by the other peripherals.
//
// Register map (byte offsets, all 32-bit accesses):
//   0x00  DATA     write: push a byte into the transmitter (bits [7:0])
//                  read : pop the received byte (bits [7:0]); clears RX_VALID
//   0x04  DIVIDER  baud rate divider, in clk cycles per bit, minus 1.
//                  bit period = (DIVIDER[15:0] + 1) clk cycles
//   0x08  STATUS   read only
//                    [0] TX_BUSY     transmitter shifting a frame out
//                    [1] TX_READY    transmitter can accept a new byte
//                    [2] RX_VALID    a received byte is waiting in DATA
//                    [3] RX_OVERRUN  a byte arrived while RX_VALID was set
//                    [4] FRAME_ERR   stop bit was not 1 on the last frame
//                  writing 1 to [3] or [4] clears that sticky flag
//   0x0c  CONTROL   [0] TX_EN       enable the transmitter
//                   [1] RX_EN       enable the receiver
//                   [2] TX_INT_EN   interrupt when the transmitter goes idle
//                   [3] RX_INT_EN   interrupt when a byte is received
//
// Frame format is fixed 8N1: one start bit (0), eight data bits LSB first,
// one stop bit (1), no parity.

module uart_controller(clk,rst,addr,addr_valid,read_write,data_in,data_out,
                       uart_rx,uart_tx,int_out_uart);

input clk,rst,addr_valid,read_write;
input [31:0]addr,data_in;
input uart_rx;

output uart_tx;
output int_out_uart;
output reg [31:0]data_out;


//// registers

reg [31:0]uart_divider_reg;
reg [31:0]uart_control_reg;

reg [7:0] rx_data_reg;
reg       rx_valid;
reg       rx_overrun;
reg       frame_err;


//// transmitter

reg [9:0]  tx_shift;      // {stop, data[7:0], start}, shifted out LSB first
reg [3:0]  tx_bit_cnt;    // bits still to shift, 10 down to 0
reg [15:0] tx_cnt;        // baud counter
reg        tx_busy;


//// receiver

reg [1:0]  rx_sync;       // 2-flop synchronizer on the async serial input
reg [7:0]  rx_shift;
reg [3:0]  rx_bit_cnt;    // 0 = start bit, 1..8 = data bits, 9 = stop bit
reg [15:0] rx_cnt;
reg        rx_busy;


//// wires

wire [15:0] baud_div;
wire        tx_start;
wire        data_read;
wire        rx_bit;
wire [15:0] rx_target;


assign baud_div  = uart_divider_reg[15:0];

// A write to DATA starts a frame, but only when the transmitter is enabled
// and idle; a write while busy is dropped rather than corrupting the frame.
assign tx_start  = addr_valid &&  read_write && (addr[7:0] == 8'h00) &&
                   uart_control_reg[0] && !tx_busy;

// A read of DATA pops the receive holding register.
assign data_read = addr_valid && !read_write && (addr[7:0] == 8'h00);

assign rx_bit    = rx_sync[1];

// The start bit is sampled half a bit period in, to land in the middle of
// the eye; every bit after that is a full period later.
assign rx_target = (rx_bit_cnt == 4'd0) ? {1'b0, baud_div[15:1]} : baud_div;

// Idle line is high. The stop bit is already the MSB of tx_shift, so once
// the shifter has drained it holds 1 on its own.
assign uart_tx = (tx_busy) ? tx_shift[0] : 1'b1;

assign int_out_uart = (uart_control_reg[2] && !tx_busy) ||
                      (uart_control_reg[3] && rx_valid);


//// register writes

always@(posedge clk)
begin
     if(rst)
     begin
          uart_divider_reg <= 32'd0;
          uart_control_reg <= 32'd0;
     end
     else if(addr_valid == 1'b1 && read_write == 1'b1)
     begin
          case(addr[7:0])
            8'h04: uart_divider_reg <= data_in;
            8'h0c: uart_control_reg <= data_in;
            default: ;  // unmapped address: no register written
          endcase
     end
end


//// register reads

always@(*)
begin
data_out = 32'd0;
  if(addr_valid == 1'b1 && read_write == 1'b0)
    begin
     case(addr[7:0])
                 8'h00: data_out = {24'd0, rx_data_reg};
                 8'h04: data_out = uart_divider_reg;
                 8'h08: data_out = {27'd0, frame_err, rx_overrun, rx_valid,
                                    ~tx_busy, tx_busy};
                 8'h0c: data_out = uart_control_reg;
                 default: data_out = 32'd0;
     endcase
    end
end


//// transmitter

always@(posedge clk)
begin
     if(rst)
     begin
          tx_shift   <= 10'h3ff;
          tx_bit_cnt <= 4'd0;
          tx_cnt     <= 16'd0;
          tx_busy    <= 1'b0;
     end
     else if(tx_start)
     begin
          tx_shift   <= {1'b1, data_in[7:0], 1'b0};
          tx_bit_cnt <= 4'd10;
          tx_cnt     <= 16'd0;
          tx_busy    <= 1'b1;
     end
     else if(tx_busy)
     begin
          if(tx_cnt == baud_div)
          begin
               tx_cnt   <= 16'd0;
               tx_shift <= {1'b1, tx_shift[9:1]};
               if(tx_bit_cnt == 4'd1)
               begin
                    tx_bit_cnt <= 4'd0;
                    tx_busy    <= 1'b0;
               end
               else tx_bit_cnt <= tx_bit_cnt - 4'd1;
          end
          else tx_cnt <= tx_cnt + 16'd1;
     end
end


//// receiver

always@(posedge clk)
begin
     if(rst)
     begin
          rx_sync     <= 2'b11;
          rx_shift    <= 8'd0;
          rx_bit_cnt  <= 4'd0;
          rx_cnt      <= 16'd0;
          rx_busy     <= 1'b0;
          rx_data_reg <= 8'd0;
          rx_valid    <= 1'b0;
          rx_overrun  <= 1'b0;
          frame_err   <= 1'b0;
     end
     else
     begin
          rx_sync <= {rx_sync[0], uart_rx};

          //// sticky flag clear, and the DATA read that pops the byte
          if(addr_valid && read_write && (addr[7:0] == 8'h08))
          begin
               if(data_in[3]) rx_overrun <= 1'b0;
               if(data_in[4]) frame_err  <= 1'b0;
          end

          if(data_read) rx_valid <= 1'b0;

          if(!rx_busy)
          begin
               //// falling edge on an idle line is a start bit
               if(uart_control_reg[1] && !rx_bit)
               begin
                    rx_busy    <= 1'b1;
                    rx_cnt     <= 16'd0;
                    rx_bit_cnt <= 4'd0;
               end
          end
          else if(rx_cnt == rx_target)
          begin
               rx_cnt <= 16'd0;

               if(rx_bit_cnt == 4'd0)
               begin
                    //// mid start bit: if the line came back high it was a glitch
                    if(rx_bit) rx_busy <= 1'b0;
                    else       rx_bit_cnt <= 4'd1;
               end
               else if(rx_bit_cnt <= 4'd8)
               begin
                    rx_shift   <= {rx_bit, rx_shift[7:1]};   // LSB first
                    rx_bit_cnt <= rx_bit_cnt + 4'd1;
               end
               else
               begin
                    //// stop bit
                    rx_busy   <= 1'b0;
                    frame_err <= frame_err | ~rx_bit;
                    if(rx_bit)
                    begin
                         rx_data_reg <= rx_shift;
                         rx_valid    <= 1'b1;
                         //// arriving byte lands on top of one never read
                         if(rx_valid && !data_read) rx_overrun <= 1'b1;
                    end
               end
          end
          else rx_cnt <= rx_cnt + 16'd1;
     end
end


// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     addr[31:8], data_in[31:8], uart_divider_reg[31:16],
                     uart_control_reg[31:4], rx_sync[0],
                     1'b0};

endmodule
