module dmem (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,     
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);

    
    reg [31:0] mem [0:63];   // 64 words (was 256)
  /////  reg [31:0]read_reg;

    wire [5:0] word_addr;
    assign word_addr = addr[7:2];   // 64-word array; addr[1:0] are byte offsets

always @(posedge clk) begin

        if (we)
        begin
            mem[word_addr] <= wdata;
        end
        
            rdata <= mem[word_addr];    
 end

////assign rdata  = read_reg;



// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     addr[31:10], addr[1:0],
                     1'b0};

endmodule



