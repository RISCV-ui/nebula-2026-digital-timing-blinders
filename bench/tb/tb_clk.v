`timescale 1ns / 1ps

// Checks the two rewritten clock structures for the property they were
// rewritten to have: no pulse on their output is ever shorter than a pulse
// of the source that produced it. A runt is the failure mode, so the test
// measures pulse widths rather than eyeballing a waveform.
module tb_clk;

reg clk = 0;
reg rst = 1;
reg [1:0] sel = 2'b00;
reg en = 1;

always #5 clk = ~clk;          // 10 ns source

wire gated, muxed;

clk_gate    g0(clk, en, gated);
clk_div_mux m0(clk, rst, sel, muxed);

real t_last_g, t_last_m, w;
integer runts_g, runts_m, edges_g, edges_m;
integer rise_m;

// The narrowest legal pulse on either output is a half period of the
// undivided clock. Anything shorter is a chopped pulse.
localparam real MIN_W = 4.9;

always @(gated) begin
    w = $realtime - t_last_g;
    if (t_last_g > 0.0 && w < MIN_W) begin
        runts_g = runts_g + 1;
        $display("RUNT gate at %0t: %0.2f ns", $realtime, w);
    end
    t_last_g = $realtime;
    edges_g = edges_g + 1;
end

always @(muxed) begin
    w = $realtime - t_last_m;
    if (t_last_m > 0.0 && w < MIN_W) begin
        runts_m = runts_m + 1;
        $display("RUNT mux at %0t: %0.2f ns", $realtime, w);
    end
    t_last_m = $realtime;
    edges_m = edges_m + 1;
end

always @(posedge muxed) rise_m = rise_m + 1;

integer before;

task ratio(input [1:0] s, input integer settle, input integer meas,
           input integer expect_edges);
begin
    sel = s;
    #(settle);
    before = rise_m;
    #(meas);
    $display("sel=%b: %0d rising edges in %0d ns (expected %0d)",
             s, rise_m - before, meas, expect_edges);
    if (rise_m - before !== expect_edges)
        $display("RATIO MISMATCH at sel=%b", s);
end
endtask

initial begin : watchdog
    #50000;
    $display("WATCHDOG stop at %0t", $realtime);
    $finish;
end

initial begin
    t_last_g = 0.0; t_last_m = 0.0;
    runts_g = 0; runts_m = 0; edges_g = 0; edges_m = 0; rise_m = 0;
    #23 rst = 0;

    // Switch the ratio at deliberately awkward offsets -- mid-pulse, which
    // is exactly what a combinational select cannot survive.
    ratio(2'b00, 100, 400, 40);
    #3;
    ratio(2'b01, 200, 400, 20);
    #7;
    ratio(2'b10, 300, 800, 20);
    #1;
    ratio(2'b11, 400, 1600, 20);
    #2;
    ratio(2'b00, 200, 400, 40);

    // The switch that actually breaks a combinational mux: change `sel` 2 ns
    // after a rising edge, i.e. with the currently selected clock high, so the
    // old branch is cut mid-pulse. Walk every ratio this way, both directions.
    begin : stress
        integer i;
        for (i = 0; i < 12; i = i + 1) begin
            @(posedge clk); #2;
            sel = i[1:0];
            #137;
            @(posedge clk); #2;
            sel = (~i) & 2'b11;
            #211;
        end
    end
    sel = 2'b00; #200;

    // Toggle the clock enable at random phases too.
    en = 0; #13 en = 1; #7 en = 0; #3 en = 1; #50;

    $display("gate: %0d transitions, %0d runts", edges_g, runts_g);
    $display("mux : %0d transitions, %0d runts", edges_m, runts_m);
    if (runts_g == 0 && runts_m == 0)
        $display("RESULT PASS no runt pulses");
    else
        $display("RESULT FAIL");
    $finish;
end

endmodule
