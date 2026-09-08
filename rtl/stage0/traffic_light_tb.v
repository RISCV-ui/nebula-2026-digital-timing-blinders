`timescale 1ns/1ps

module traffic_light_tb;

    reg clk = 0;
    reg rst_n = 0;
    wire red, yellow, green;

    traffic_light dut (
        .clk(clk),
        .rst_n(rst_n),
        .red(red),
        .yellow(yellow),
        .green(green)
    );

    always #5 clk = ~clk;   // 100 MHz

    integer i;
    initial begin
        $dumpfile("traffic_light.vcd");
        $dumpvars(0, traffic_light_tb);

        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            $display("t=%0t state R=%b G=%b Y=%b", $time, red, green, yellow);
        end

        $finish;
    end

endmodule
