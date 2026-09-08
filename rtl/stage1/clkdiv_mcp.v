// Stage 1 exercise — generated clock + multicycle path
//
// clk_div2 is a real generated clock, toggle-FF divide-by-2 off `clk`.
// acc_out is a wide accumulator whose combinational adder is deliberately
// too slow for one clk_div2 cycle, but is allowed 2 cycles via
// set_multicycle_path (accept sends a new operand only every other cycle).

module clkdiv_mcp (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] operand,
    input  wire        accept,      // new operand valid, pulses once every 2 clk_div2 cycles
    output wire [31:0] acc_out,
    output wire        clk_div2_out // exposed as a port so SDC can target a stable name
);

    // ---- generated clock: divide-by-2 toggle flop ----
    reg clk_div2 = 1'b0;   // sim-only init; real reset logic below is unchanged
    always @(posedge clk) begin
        if (!rst_n)
            clk_div2 <= 1'b0;
        else
            clk_div2 <= ~clk_div2;
    end

    assign clk_div2_out = clk_div2;

    // ---- wide accumulator on the divided clock, multicycle path ----
    reg [31:0] acc = 32'd0;   // sim-only init; real reset logic below is unchanged
    wire [31:0] sum_wide;

    // deliberately deep combinational adder tree (multi-stage ripple-ish
    // chain) to model a datapath op that genuinely needs 2 clk_div2 cycles
    assign sum_wide = (acc ^ operand) + (acc & operand) + (acc | operand) + operand;

    always @(posedge clk_div2) begin
        if (!rst_n)
            acc <= 32'd0;
        else if (accept)
            acc <= sum_wide;
    end

    assign acc_out = acc;

endmodule
