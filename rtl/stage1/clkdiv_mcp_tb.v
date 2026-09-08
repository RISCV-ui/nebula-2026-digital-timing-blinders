`timescale 1ns/1ps

module clkdiv_mcp_tb;

    reg         clk = 0;
    reg         rst_n = 0;
    reg  [31:0] operand = 0;
    reg         accept = 0;
    wire [31:0] acc_out;
    wire        clk_div2_out;

    clkdiv_mcp dut (
        .clk(clk), .rst_n(rst_n),
        .operand(operand), .accept(accept),
        .acc_out(acc_out), .clk_div2_out(clk_div2_out)
    );

    always #1 clk = ~clk; // 2ns period, 500MHz

    initial begin
        $dumpfile("clkdiv_mcp.vcd");
        $dumpvars(0, clkdiv_mcp_tb);

        rst_n = 0;
        operand = 0;
        accept = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // drive one accept pulse every 2 clk_div2 edges (4 clk edges),
        // matching the multicycle budget given to the accumulator
        operand = 32'h0000_0001; accept = 1;
        repeat (4) @(posedge clk); accept = 0;
        repeat (4) @(posedge clk);

        operand = 32'h0000_0010; accept = 1;
        repeat (4) @(posedge clk); accept = 0;
        repeat (4) @(posedge clk);

        operand = 32'hDEAD_0000; accept = 1;
        repeat (4) @(posedge clk); accept = 0;
        repeat (8) @(posedge clk);

        $display("final acc_out = %h", acc_out);
        $finish;
    end

endmodule
