`timescale 1ns / 1ps

// Block <-> AXI-lite bridge for the L1 caches.
//
// l1_d_cache_8kb (and l1_i_cache_8kb) talk to the next level down over a
// wide native port: one 256-bit block per request, with read_write_l2
// selecting refill or write back. The interconnect below is AXI-lite, which
// moves 32 bits per transaction. This module sits between them and turns
// each block request into 8 sequential AXI-lite beats.
//
// Addressing: addr_l2 counts in 32-bit words -- the caches build it as
// {tag, set, 3'b000}, where the low 3 bits are the word offset inside the
// block. The AXI side is byte addressed, so the beat address is
// {addr_l2[28:0], beat, 2'b00}.
//
// This is deliberately a simple sequential bridge, one outstanding beat at
// a time: correctness and a clean critical path first, throughput later.

module l1_cache_axi_master(clk,rst,
                           addr_l2,addr_l2_valid,read_write_l2,
                           data_out_l2_write,data_in_l2,data_valid_l2,
                           m_ar_addr,m_ar_valid,m_ar_ready,
                           m_aw_addr,m_aw_valid,m_aw_ready,
                           m_dr_data,m_dr_valid,m_dr_ready,
                           m_dw_data,m_dw_valid,m_dw_ready,
                           m_b_ready,m_b_valid,m_b_resp);

input clk,rst;

/// cache side
input  [31:0]  addr_l2;
input          addr_l2_valid;
input          read_write_l2;        // 1 = write back, 0 = refill
input  [255:0] data_out_l2_write;
output [255:0] data_in_l2;
output reg     data_valid_l2;

/// axi-lite master side
output reg [31:0] m_ar_addr;
output reg        m_ar_valid;
input             m_ar_ready;

output reg [31:0] m_aw_addr;
output reg        m_aw_valid;
input             m_aw_ready;

input      [31:0] m_dr_data;
input             m_dr_valid;
output reg        m_dr_ready;

output reg [31:0] m_dw_data;
output reg        m_dw_valid;
input             m_dw_ready;

output reg        m_b_ready;
input             m_b_valid;
input      [1:0]  m_b_resp;


//// parameters
parameter idle     = 3'b000;
parameter read_ar  = 3'b001;
parameter read_dr  = 3'b010;
parameter write_aw = 3'b011;
parameter write_dw = 3'b100;
parameter write_b  = 3'b101;
parameter done     = 3'b110;


//// regs
reg [2:0]   pr_state;
reg [2:0]   beat;
reg [31:0]  addr_hold;
reg [255:0] block_r;      // assembled refill data
reg [255:0] block_w;      // block being written back


//// wires
wire [31:0] beat_addr;

// Byte address of the current beat. addr_hold is a WORD address (the cache
// hierarchy below is word-addressed), so a beat step is +1 word = +4 bytes.
// This used to shift left by 3 and add beat*8, i.e. it scaled by 8: word
// address 0x4 went out on the bus as 0x20 instead of 0x10.
wire [31:0] beat_word;
assign beat_word  = addr_hold + {29'd0, beat};
assign beat_addr  = {beat_word[29:0], 2'b00};

assign data_in_l2 = block_r;


always@(posedge clk)
begin
     if(rst)
     begin
          pr_state      <= idle;
          beat          <= 3'd0;
          addr_hold     <= 32'd0;
          block_r       <= 256'd0;
          block_w       <= 256'd0;
          data_valid_l2 <= 1'b0;
          m_ar_addr     <= 32'd0;
          m_ar_valid    <= 1'b0;
          m_aw_addr     <= 32'd0;
          m_aw_valid    <= 1'b0;
          m_dr_ready    <= 1'b0;
          m_dw_data     <= 32'd0;
          m_dw_valid    <= 1'b0;
          m_b_ready     <= 1'b0;
     end
     else
     begin
          data_valid_l2 <= 1'b0;

          case(pr_state)

            idle: begin
                       beat <= 3'd0;
                       // !data_valid_l2 is what stops the SAME request being
                       // taken twice. done sets data_valid_l2 and drops into
                       // idle on the same edge, so for one cycle this state is
                       // live while the block is still being handed back -- and
                       // the cache above only drops addr_l2_valid on the edge
                       // AFTER it sees data_valid_l2. Without this guard idle
                       // sampled that trailing request and re-ran the whole
                       // 8-beat refill; the duplicate block then answered the
                       // NEXT miss, so every miss after the first returned the
                       // previously fetched block's data to the CPU.
                       if(addr_l2_valid && !data_valid_l2)
                       begin
                            addr_hold <= addr_l2;
                            if(read_write_l2)
                            begin
                                 block_w  <= data_out_l2_write;
                                 pr_state <= write_aw;
                            end
                            else pr_state <= read_ar;
                       end
                  end

            //// refill: address beat
            read_ar: begin
                       m_ar_addr  <= beat_addr;
                       m_ar_valid <= 1'b1;
                       if(m_ar_valid && m_ar_ready)
                       begin
                            m_ar_valid <= 1'b0;
                            m_dr_ready <= 1'b1;
                            pr_state   <= read_dr;
                       end
                  end

            //// refill: data beat
            read_dr: begin
                       if(m_dr_valid && m_dr_ready)
                       begin
                            block_r[beat*32 +: 32] <= m_dr_data;
                            m_dr_ready <= 1'b0;
                            if(beat == 3'd7) pr_state <= done;
                            else
                            begin
                                 beat     <= beat + 3'd1;
                                 pr_state <= read_ar;
                            end
                       end
                  end

            //// write back: address beat
            write_aw: begin
                       m_aw_addr  <= beat_addr;
                       m_aw_valid <= 1'b1;
                       if(m_aw_valid && m_aw_ready)
                       begin
                            m_aw_valid <= 1'b0;
                            m_dw_data  <= block_w[beat*32 +: 32];
                            m_dw_valid <= 1'b1;
                            pr_state   <= write_dw;
                       end
                  end

            //// write back: data beat
            write_dw: begin
                       if(m_dw_valid && m_dw_ready)
                       begin
                            m_dw_valid <= 1'b0;
                            m_b_ready  <= 1'b1;
                            pr_state   <= write_b;
                       end
                  end

            //// write back: response beat
            write_b: begin
                       if(m_b_valid && m_b_ready)
                       begin
                            m_b_ready <= 1'b0;
                            // A finished write back goes straight back to idle
                            // WITHOUT passing through done, because done pulses
                            // data_valid_l2 and data_valid_l2 means exactly one
                            // thing to l1_d_cache_8kb: "the refill block you
                            // asked for is on data_in_l2".
                            //
                            // The cache does not wait for a write back to
                            // finish -- it drops block_removing_true as soon as
                            // it has handed the victim over and immediately
                            // starts requesting the refill. So the pulse this
                            // used to emit at the end of the write back landed
                            // while the cache was waiting for the refill, and
                            // the cache installed whatever stale contents
                            // block_r happened to hold. Every dirty eviction
                            // came back as garbage.
                            if(beat == 3'd7) pr_state <= idle;
                            else
                            begin
                                 beat     <= beat + 3'd1;
                                 pr_state <= write_aw;
                            end
                       end
                  end

            //// one cycle of data_valid_l2 hands the block back to the cache
            done: begin
                       data_valid_l2 <= 1'b1;
                       pr_state      <= idle;
                  end

            default: pr_state <= idle;

          endcase
     end
end


// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     addr_hold[31:29], beat_word[31:30], m_b_resp,
                     1'b0};

endmodule
