// Blackbox declarations for the two OpenRAM hard macros.
//
// Read with `read_verilog -lib` on BOTH sides of an equivalence check, and by
// any tool that must know the macro's ports without knowing (or being allowed
// to invent) its contents. Port widths and directions here are taken from the
// macros' liberty files, which are the authority on what the silicon has --
// not from OpenRAM's behavioural .v, which shipped an extra spare column that
// does not exist in the .lib or .lef.
//
// Because the macro is identical on the gold and gate side of every check, the
// prover treats it as an uninterpreted function: the check proves the logic
// AROUND the SRAM is unchanged, and says nothing about the SRAM itself. The
// SRAM's own correctness is a vendor/DRC/LVS question, not a synthesis one.

(* blackbox *)
module id_memory_256x64(clk0, csb0, web0, addr0, din0, dout0,
                        clk1, csb1, addr1, dout1);
    input          clk0;
    input          csb0;
    input          web0;
    input  [6:0]   addr0;
    input  [255:0] din0;
    output [255:0] dout0;
    input          clk1;
    input          csb1;
    input  [6:0]   addr1;
    output [255:0] dout1;
endmodule

(* blackbox *)
module tag_memory_92x64(clk0, csb0, web0, addr0, din0, dout0,
                        clk1, csb1, addr1, dout1);
    input          clk0;
    input          csb0;
    input          web0;
    input  [6:0]   addr0;
    input  [91:0]  din0;
    output [91:0]  dout0;
    input          clk1;
    input          csb1;
    input  [6:0]   addr1;
    output [91:0]  dout1;
endmodule
