module arbiter(clk,rst,req_cpu,req_dam,grant,clear_cpu,clear_dma);

input clk,rst,req_cpu,req_dam,clear_cpu,clear_dma;
output reg grant;


always@(posedge clk)
begin
     if(rst)grant <=1'b0;
     else if(clear_cpu || clear_dma ) grant <=1'b0;
     // Once the DMA owns this slave it keeps it until the transaction on that
     // slave completes and clear_* fires. The old term
     //   req_dam & (~grant | ~req_cpu)
     // re-evaluated the winner every cycle, so with both masters requesting
     // the same slave grant toggled 1,0,1,0 -- the DMA's address and data were
     // switched out from under it in the middle of a transfer.
     else if(grant) grant <= 1'b1;
     // The CPU owns the bus by default and does not need a grant, so the DMA
     // may only take a slave the CPU is not asking for this cycle.
     else   grant <= req_dam & ~req_cpu;



end

endmodule
