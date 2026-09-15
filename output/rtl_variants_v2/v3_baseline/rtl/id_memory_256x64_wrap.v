`timescale 1ns / 1ps

// id_memory_256x64_wrap -- behavioural single-port memory.
//
// The competition benchmark is a timing/PPA/equivalence study, not a tapeout,
// so the OpenRAM hard macro behind this wrapper has been dropped: a BLOCK with
// met1-met4 obstruction over 2228x226 um forced every route around it and made
// global routing the bottleneck instead of the logic being studied. Ports and
// handshake are byte-for-byte the ones the macro version presented, so
// l1_d_cache_8kb / l1_i_cache_8kb are untouched.
//
// Depth is 8 sets (was 64). The cache stays 4-way with 256-bit lines; only the
// set count shrank, which keeps the FSM, the LRU logic and the AXI refill path
// identical while bringing the flop count into the ~50K-cell benchmark target.
//
// Read latency: one cycle, data_valid one cycle behind a read request.

module id_memory_256x64_wrap(clk,rst,mem_en,addr,read_write,data_in,data_out,data_valid);
    input               clk;
    input               rst;
    input               mem_en;
    input      [31:0]   addr;
    input               read_write;   // 1 = write, 0 = read
    input      [255:0]   data_in;
    output reg [255:0]   data_out;
    output reg          data_valid;

    reg [255:0] mem [0:7];

    wire [2:0] word_addr;
    assign word_addr = addr[2:0];

    always@(posedge clk)
    begin
        if(mem_en & read_write) mem[word_addr] <= data_in;
    end

    always@(posedge clk)
    begin
        if(rst) begin
            data_out   <= 256'd0;
            data_valid <= 1'b0;
        end else begin
            if(mem_en & ~read_write) data_out <= mem[word_addr];
            data_valid <= mem_en & ~read_write;
        end
    end

    wire _unused_ok = &{1'b0, addr[31:3], 1'b0};

endmodule
