`timescale 1ns / 1ps

// Single-block read buffer in front of l1_i_cache_8kb.
//
// The cache returns a whole 256-bit block per access, but the fetch stage
// only ever wants one 32-bit word out of it. This buffer holds the most
// recently fetched block so that sequential fetches inside the same block
// -- the common case for straight-line code -- are served in a single cycle
// without touching the cache at all.
//
// Address split, matching the way l1_i_cache_8kb decodes addr_cpu_in:
//   addr[31:3]  29-bit tag, held in buf_tag
//   addr[2:0]   3-bit offset, selects one of the 8 words in the block
//
// On a hit the selected word is driven out combinationally. On a miss the
// buffer requests the block from the cache and reloads all 8 words, then
// replays the access out of the buffer.

module read_buffer_i_cache(clk,rst,
                           addr_cpu_in,addr_valid_in,
                           data_out,data_valid_out,hit_out,
                           addr_l1,addr_valid_l1,
                           data_in_l1,data_valid_l1);

input clk,rst;

/// cpu side
input  [31:0] addr_cpu_in;
input         addr_valid_in;
output [31:0] data_out;
output        data_valid_out;
output        hit_out;

/// l1 i-cache side
output [31:0] addr_l1;
output        addr_valid_l1;
input  [255:0]data_in_l1;
input         data_valid_l1;


//// parameters
parameter idle = 2'b01;
parameter fill = 2'b10;


//// regs
reg [28:0] buf_tag;
reg        buf_valid;
reg [31:0] buf_data [0:7];
reg [1:0]  pr_state;
reg [31:0] addr_hold;   // address that missed, replayed once the fill lands

integer    i;


//// wires
wire [28:0] req_tag;
wire [2:0]  req_off;
wire        tag_match;


assign req_tag   = addr_cpu_in[31:3];
assign req_off   = addr_cpu_in[2:0];

assign tag_match = buf_valid && (buf_tag == req_tag);

// A hit is only meaningful while the buffer is idle: during a fill the block
// held in buf_data is the previous one, not the one being requested.
assign hit_out        = tag_match && (pr_state == idle);
assign data_valid_out = hit_out && addr_valid_in;
assign data_out       = buf_data[req_off];

// Miss: ask the cache for the block. addr_hold keeps the request stable for
// the whole fill, so a changing CPU address cannot retarget it mid-flight.
assign addr_valid_l1 = (pr_state == fill);
assign addr_l1       = addr_hold;


always@(posedge clk)
begin
     if(rst)
     begin
          buf_tag   <= 29'd0;
          buf_valid <= 1'b0;
          addr_hold <= 32'd0;
          pr_state  <= idle;
          for(i = 0; i < 8; i = i + 1) buf_data[i[2:0]] <= 32'd0;
     end
     else
     begin
          case(pr_state)

            idle: begin
                       if(addr_valid_in && !tag_match)
                       begin
                            addr_hold <= addr_cpu_in;
                            pr_state  <= fill;
                       end
                  end

            fill: begin
                       if(data_valid_l1)
                       begin
                            for(i = 0; i < 8; i = i + 1)
                                buf_data[i[2:0]] <= data_in_l1[i[2:0]*32 +: 32];
                            buf_tag   <= addr_hold[31:3];
                            buf_valid <= 1'b1;
                            pr_state  <= idle;
                       end
                  end

            default: pr_state <= idle;

          endcase
     end
end

endmodule
