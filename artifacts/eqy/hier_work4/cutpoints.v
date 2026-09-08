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

(* blackbox *)
module clk_div_mux(clk, rst, sel, clk_out);
    input clk;
    input rst;
    input [1:0] sel;
    output clk_out;
endmodule

(* blackbox *)
module interrupt_control_unit(clk, rst, int_in, int_mask, int_clear, int_pending, int_id, int_req);
    input clk;
    input rst;
    input [2:0] int_in;
    input [2:0] int_mask;
    input [2:0] int_clear;
    output [2:0] int_pending;
    output [1:0] int_id;
    output int_req;
endmodule

(* blackbox *)
module l1_cache_axi_master(clk, rst, addr_l2, addr_l2_valid, read_write_l2, data_out_l2_write, data_in_l2, data_valid_l2, m_ar_addr, m_ar_valid, m_ar_ready, m_aw_addr, m_aw_valid, m_aw_ready, m_dr_data, m_dr_valid, m_dr_ready, m_dw_data, m_dw_valid, m_dw_ready, m_b_ready, m_b_valid, m_b_resp);
    input clk;
    input rst;
    input [31:0] addr_l2;
    input addr_l2_valid;
    input read_write_l2;
    input [255:0] data_out_l2_write;
    output [255:0] data_in_l2;
    output data_valid_l2;
    output [31:0] m_ar_addr;
    output m_ar_valid;
    input m_ar_ready;
    output [31:0] m_aw_addr;
    output m_aw_valid;
    input m_aw_ready;
    input [31:0] m_dr_data;
    input m_dr_valid;
    output m_dr_ready;
    output [31:0] m_dw_data;
    output m_dw_valid;
    input m_dw_ready;
    output m_b_ready;
    input m_b_valid;
    input [1:0] m_b_resp;
endmodule

(* blackbox *)
module mem_axi_slave(clk, rst, mem_en, read_write, addr, data_out, data_in, hit, s1_ar_addr, s1_ar_valid, s1_ar_ready, s1_ar_len, s1_ar_size, s1_ar_burst, s1_aw_addr, s1_aw_valid, s1_aw_ready, s1_aw_len, s1_aw_size, s1_aw_burst, s1_dr_data, s1_dr_valid, s1_dr_ready, s1_dr_last, s1_dw_data, s1_dw_valid, s1_dw_ready, s1_dw_strb, s1_dw_last, s1_b_ready, s1_b_valid, s1_b_resp);
    input clk;
    input rst;
    output mem_en;
    output read_write;
    output [31:0] addr;
    input [31:0] data_out;
    output [31:0] data_in;
    input hit;
    input [31:0] s1_ar_addr;
    input s1_ar_valid;
    output s1_ar_ready;
    input [7:0] s1_ar_len;
    input [2:0] s1_ar_size;
    input [1:0] s1_ar_burst;
    input [31:0] s1_aw_addr;
    input s1_aw_valid;
    output s1_aw_ready;
    input [7:0] s1_aw_len;
    input [2:0] s1_aw_size;
    input [1:0] s1_aw_burst;
    output [31:0] s1_dr_data;
    output s1_dr_valid;
    input s1_dr_ready;
    output s1_dr_last;
    input [31:0] s1_dw_data;
    input s1_dw_valid;
    output s1_dw_ready;
    input [3:0] s1_dw_strb;
    input s1_dw_last;
    input s1_b_ready;
    output s1_b_valid;
    output [1:0] s1_b_resp;
endmodule

(* blackbox *)
module axi_lite_master(clk, rst, addr, addr_valid, data_out, read_write, data_in, done, m1_ar_addr, m1_ar_valid, m1_ar_ready, m1_aw_addr, m1_aw_valid, m1_aw_ready, m1_dr_data, m1_dr_valid, m1_dr_ready, m1_dr_resp, m1_dw_data, m1_dw_valid, m1_dw_ready, m1_dw_strb, m1_b_ready, m1_b_valid, m1_b_resp);
    input clk;
    input rst;
    input [31:0] addr;
    input addr_valid;
    input [31:0] data_out;
    input read_write;
    output [31:0] data_in;
    output done;
    output [31:0] m1_ar_addr;
    output m1_ar_valid;
    input m1_ar_ready;
    output [31:0] m1_aw_addr;
    output m1_aw_valid;
    input m1_aw_ready;
    input [31:0] m1_dr_data;
    input m1_dr_valid;
    output m1_dr_ready;
    input [1:0] m1_dr_resp;
    output [31:0] m1_dw_data;
    output m1_dw_valid;
    input m1_dw_ready;
    output [3:0] m1_dw_strb;
    output m1_b_ready;
    input m1_b_valid;
    input [1:0] m1_b_resp;
endmodule

(* blackbox *)
module dmem(clk, we, addr, wdata, rdata);
    input clk;
    input we;
    input [31:0] addr;
    input [31:0] wdata;
    output [31:0] rdata;
endmodule

(* blackbox *)
module clk_gate(clk_in, clk_en, clk_out);
    input clk_in;
    input clk_en;
    output clk_out;
endmodule
