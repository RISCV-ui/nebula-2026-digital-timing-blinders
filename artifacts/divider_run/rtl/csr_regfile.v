`timescale 1ns/1ps



module csr_regfile (
    input         clk,
    input         rst,
    input  [11:0] csr_addr,
    input         csr_we,
    input  [1:0]  csr_op,
    input  [31:0] csr_wdata,
    output [31:0] csr_rdata,
    input         trap,
    input  [31:0] trap_pc,
    input  [31:0] trap_cause,
    input         mret,
    input         instret,
    output [31:0] mtvec_out,
    output [31:0] mepc_out,
    output        mie_out
);

    reg [31:0] mcycle    ;
    reg [31:0] minstret  ;
    reg [31:0] mstatus   ;
    reg [31:0] mtvec     ;
    reg [31:0] mepc      ;
    reg [31:0] mcause    ;
    reg [31:0] mscratch  ;
    reg [31:0] mie       ;

    assign mtvec_out = mtvec;
    assign mepc_out  = mepc;
    assign mie_out   = mstatus[3];

    reg [31:0] csr_rdata_r;
    assign csr_rdata = csr_rdata_r;

    always @(*) begin
        case (csr_addr)
            12'h300: csr_rdata_r = mstatus;
            12'h304: csr_rdata_r = mie;
            12'h305: csr_rdata_r = mtvec;
            12'h340: csr_rdata_r = mscratch;
            12'h341: csr_rdata_r = mepc;
            12'h342: csr_rdata_r = mcause;
            12'hB00: csr_rdata_r = mcycle;
            12'hB02: csr_rdata_r = minstret;
            default: csr_rdata_r = 32'd0;
        endcase
    end

    function [31:0] apply_csr_op;
        input [31:0] old_val, wdata;
        input [1:0]  op;
        case (op)
            2'b00: apply_csr_op = wdata;
            2'b01: apply_csr_op = old_val |  wdata;
            2'b10: apply_csr_op = old_val & ~wdata;
            default: apply_csr_op = old_val;
        endcase
    endfunction

    always @(posedge clk) begin
        if (rst) mcycle <= 0;
        else     mcycle <= mcycle + 1;
    end

    always @(posedge clk) begin
        if (rst)          minstret <= 0;
        else if (instret) minstret <= minstret + 1;
    end

    always @(posedge clk) begin
        if (rst)
            mstatus <= 0;
        else if (trap)
            mstatus <= {mstatus[31:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};
        else if (mret)
            mstatus <= {mstatus[31:8], 1'b1, mstatus[6:4], mstatus[7], mstatus[2:0]};
        else if (csr_we && csr_addr == 12'h300)
            mstatus <= apply_csr_op(mstatus, csr_wdata, csr_op);
    end

    always @(posedge clk) begin
        if (rst)
            mepc <= 0;
        else if (trap)
            mepc <= trap_pc;
        else if (!trap && csr_we && csr_addr == 12'h341)
            mepc <= apply_csr_op(mepc, csr_wdata, csr_op);
    end

    always @(posedge clk) begin
        if (rst)       mcause <= 0;
        else if (trap) mcause <= trap_cause;
    end

    always @(posedge clk) begin
        if (rst) mtvec <= 0;
        else if (csr_we && csr_addr == 12'h305)
            mtvec <= apply_csr_op(mtvec, csr_wdata, csr_op);
    end

    always @(posedge clk) begin
        if (rst) mie <= 0;
        else if (csr_we && csr_addr == 12'h304)
            mie <= apply_csr_op(mie, csr_wdata, csr_op);
    end

    always @(posedge clk) begin
        if (rst) mscratch <= 0;
        else if (csr_we && csr_addr == 12'h340)
            mscratch <= apply_csr_op(mscratch, csr_wdata, csr_op);
    end

endmodule




