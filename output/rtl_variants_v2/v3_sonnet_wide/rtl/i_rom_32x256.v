`timescale 1ns / 1ps

// Block-wide instruction ROM sitting behind l1_i_cache_8kb.
//
// This replaces the old i_mem, which the fetch stage read directly as a
// 256x32 synchronous array. The L1 i-cache refills a whole 256-bit block per
// miss, so the backing store is organised as 32 blocks of 8 words rather than
// 256 individual words. The program image is unchanged; only the read width
// and the request/valid handshake are different.
//
// Address: addr_l2 is a WORD address, block aligned (l1_i_cache_8kb drives
// {addr_cpu_in[31:3],3'b000}), so addr_l2[7:3] selects one of the 32 blocks.
//
// Timing: one cycle of read latency, with data_valid_l2 asserted alongside the
// data, matching what l1_i_cache_8kb's req_higher_level state waits for.
//
// Treated as a macro for synthesis (blackboxed), like i_mem was.

module i_rom_32x256(clk,rst,
                    addr_l2,addr_l2_valid,
                    data_l2,data_valid_l2);

input         clk,rst;
input  [31:0] addr_l2;
input         addr_l2_valid;
output reg [255:0] data_l2;
output reg         data_valid_l2;

reg [31:0] mem [0:63];   // 8 blocks x 8 words (was 32 blocks)

wire [2:0] blk;
assign blk = addr_l2[5:3];

integer i;

always @(posedge clk)
begin
     if(rst)
     begin
          data_l2       <= 256'd0;
          data_valid_l2 <= 1'b0;
     end
     else if(addr_l2_valid && !data_valid_l2)
     begin
          data_l2       <= {mem[{blk,3'd7}], mem[{blk,3'd6}],
                            mem[{blk,3'd5}], mem[{blk,3'd4}],
                            mem[{blk,3'd3}], mem[{blk,3'd2}],
                            mem[{blk,3'd1}], mem[{blk,3'd0}]};
          data_valid_l2 <= 1'b1;
     end
     else
     begin
          data_valid_l2 <= 1'b0;
     end
end

// Program image, carried over verbatim from i_mem.v.
initial begin
    for (i = 0; i < 64; i = i + 1)
        mem[i] = 32'b000000000000_00000_000_00000_0010011;   // nop

    mem[0] = 32'b000000000100_00000_000_00001_0010011;   // addi x1,x0,4
    mem[1] = 32'b000000001100_00000_000_00010_0010011;   // addi x2,x0,12
    mem[2] = 32'b0000000_00010_00001_000_00011_0110011;  // add  x3,x1,x2
    mem[3] = 32'b11110000000000010000_11111_0110111;     // lui  x31,0xF0010
    mem[4] = 32'b111111110000_11111_000_11111_0010011;   // addi x31,x31,-16
    mem[5] = 32'b000000000000_00000_000_00000_0010011;   // nop
    mem[6] = 32'b000000000000_00000_000_00000_0010011;   // nop
    mem[7] = 32'b0100000_00001_00010_000_00100_0110011;  // sub  x4,x2,x1
    mem[8] = 32'b0000000_00010_00001_001_00111_0110011;  // sll  x7,x1,x2
    mem[9] = 32'b0000000_00001_00010_101_01000_0110011;  // srl  x8,x2,x1
    mem[10]= 32'b0000000_00010_00000_010_10000_0100011;  // sw   x2,16(x0)
    mem[11]= 32'b0000000_00001_00011_000_01000_1100011;  // beq  x3,x1,+8
    mem[12]= 32'b0000000_00011_00000_010_11000_0100011;  // sw   x3,24(x0)
    mem[13]= 32'b000000000100_00010_010_01001_0000011;   // lw   x9,4(x2)
    mem[14]= 32'b000000010000_00100_010_01100_0000011;   // lw   x12,16(x4)
    mem[15]= 32'b1011_0000_0000_00000_001_01111_1110011; // csrrw x15,mcycle
    mem[16]= 32'b1011_0000_0010_00000_001_01110_1110011; // csrrw x14,minstret
end

// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     addr_l2[31:6], addr_l2[2:0],
                     1'b0};

endmodule
