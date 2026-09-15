`timescale 1ns / 1ps

// Single-block read/write buffer in front of l1_d_cache_8kb.
//
// Same block/tag/offset split as read_buffer_i_cache:
//   addr[31:3]  29-bit tag
//   addr[2:0]   3-bit offset into the 8 words of the block
//
// The data side differs from the instruction side in one way: the CPU can
// write. A write that hits updates the word in place and sets the dirty
// bit, so the buffer and the cache disagree from that point on. On a miss
// with dirty set, the buffer must first push its whole block back into the
// L1 d-cache, and only then pull in the newly requested block -- otherwise
// the written words are lost.
//
// The path from the cache out to main memory is AXI-lite; that conversion
// lives in l1_cache_axi_master, which drives one master port of
// axi_interconnect_2m_8s.

module read_buffer_d_cache(clk,rst,
                           addr_cpu_in,addr_valid_in,read_write_in,data_cpu_in,
                           data_out,data_valid_out,hit_out,
                           addr_l1,addr_valid_l1,read_write_l1,
                           data_out_l1,data_in_l1,data_valid_l1);

input clk,rst;

/// cpu side
input  [31:0] addr_cpu_in;
input         addr_valid_in;
input         read_write_in;      // 1 = write, 0 = read
input  [31:0] data_cpu_in;
output [31:0] data_out;
output        data_valid_out;
output        hit_out;

/// l1 d-cache side, one 256-bit block per access
output [31:0] addr_l1;
output        addr_valid_l1;
output        read_write_l1;      // 1 = write back, 0 = refill
output [255:0]data_out_l1;
input  [255:0]data_in_l1;
input         data_valid_l1;


//// parameters
parameter idle       = 3'b001;
parameter write_back = 3'b010;
parameter fill       = 3'b100;


//// regs
reg [28:0] buf_tag;
reg        buf_valid;
reg        buf_dirty;
reg [31:0] buf_data [0:7];
reg [2:0]  pr_state;
reg [31:0] addr_hold;

integer    i;


//// wires
wire [28:0] req_tag;
wire [2:0]  req_off;
wire        tag_match;


assign req_tag   = addr_cpu_in[31:3];
assign req_off   = addr_cpu_in[2:0];

assign tag_match = buf_valid && (buf_tag == req_tag);

assign hit_out        = tag_match && (pr_state == idle);
// Completion, not read-data-valid: the CPU handshake needs an answer for a
// write too. A write that hits commits into buf_data on this same edge, so
// the access is done in the cycle it hits, exactly as a read is. Qualifying
// this with !read_write_in left every store waiting forever.
assign data_valid_out = hit_out && addr_valid_in;
assign data_out       = buf_data[req_off];

assign addr_valid_l1 = (pr_state == write_back) || (pr_state == fill);
assign read_write_l1 = (pr_state == write_back);

// A write back targets the block currently held, which is buf_tag -- not the
// address that missed. A refill targets the address that missed.
assign addr_l1 = (pr_state == write_back) ? {buf_tag, 3'b000} : addr_hold;

assign data_out_l1 = {buf_data[7], buf_data[6], buf_data[5], buf_data[4],
                      buf_data[3], buf_data[2], buf_data[1], buf_data[0]};


always@(posedge clk)
begin
     if(rst)
     begin
          buf_tag   <= 29'd0;
          buf_valid <= 1'b0;
          buf_dirty <= 1'b0;
          addr_hold <= 32'd0;
          pr_state  <= idle;
          for(i = 0; i < 8; i = i + 1) buf_data[i[2:0]] <= 32'd0;
     end
     else
     begin
          case(pr_state)

            idle: begin
                       if(addr_valid_in && tag_match && read_write_in)
                       begin
                            //// write hit: update in place, block is now dirty
                            buf_data[req_off] <= data_cpu_in;
                            buf_dirty         <= 1'b1;
                       end
                       else if(addr_valid_in && !tag_match)
                       begin
                            addr_hold <= addr_cpu_in;
                            //// a dirty block has to reach the cache first
                            if(buf_valid && buf_dirty) pr_state <= write_back;
                            else                       pr_state <= fill;
                       end
                  end

            write_back: begin
                       if(data_valid_l1)
                       begin
                            buf_dirty <= 1'b0;
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
                            buf_dirty <= 1'b0;
                            pr_state  <= idle;
                       end
                  end

            default: pr_state <= idle;

          endcase
     end
end

endmodule
