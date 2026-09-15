`timescale 1ns / 1ps



module execution_stage(clk,rst,pc_plus4_id,pc_id,opcode_id,src_reg_1_id,src_reg_2_id,rs2_reg_id,data_cliper,alu_operation_id,start_mul_id,mulh_mul_id,alu_out_sel_id,pc4_sel_id,alu_out_ex,branch_result_ex,opcode_ex,pc_ex,mul_done_ex,mul_busy_ex,rs2_for_mem_ex,alu_output_forwd);

input wire clk,rst;
input wire [31:0]pc_plus4_id;
input wire [31:0]pc_id;
input wire [6:0] opcode_id;
input wire [31:0]src_reg_1_id;
input wire [31:0]src_reg_2_id;
input wire [31:0] rs2_reg_id;
input wire [1:0]data_cliper;
input wire [3:0] alu_operation_id;
input wire start_mul_id, mulh_mul_id;
input wire alu_out_sel_id;
input wire pc4_sel_id;

output reg [31:0] alu_out_ex;
output reg branch_result_ex;
output reg [6:0]opcode_ex;
output reg [31:0]pc_ex;
output wire mul_done_ex,mul_busy_ex;
output reg [31:0]rs2_for_mem_ex;
output reg [31:0]alu_output_forwd;

wire [31:0] alu_out_wire;
wire [31:0] mul_out_wire;
wire [31:0] alu_pcp4_wire;
wire        branch_result_wire;

assign opcode_ex = opcode_id;
assign pc_ex    = pc_id;

alu alu_ex (
    .clk           (clk),
    .rst           (rst),
    .src_a         (src_reg_1_id),
    .src_b         (src_reg_2_id),
    .alu_control   (alu_operation_id),
    .alu_result    (alu_out_wire),
    .zero          (branch_result_wire)
);

multiplier_pipelined mul_unit_ex (
    .clk       (clk),
    .rst       (rst),
    .start     (start_mul_id),
    .src_a     (src_reg_1_id),
    .src_b     (src_reg_2_id),
    .mulh      (mulh_mul_id),
    .busy      (mul_busy_ex),
    .done      (mul_done_ex),
    .result    (mul_out_wire)
);

data_clipper data_clip_ex (
    .data_in   (rs2_reg_id),
    .clip_sel  (data_cliper),
    .data_out  (rs2_for_mem_ex)
);

assign alu_pcp4_wire      = alu_out_sel_id ? mul_out_wire : alu_out_wire;
assign alu_output_forwd_n = alu_pcp4_wire;
assign alu_out_ex_n      = pc4_sel_id ? pc_plus4_id : alu_pcp4_wire;
assign branch_result_ex_n = branch_result_wire;

always @(posedge clk) begin
    if (rst) begin
        alu_out_ex        <= 32'd0;
        branch_result_ex  <= 1'b0;
        rs2_for_mem_ex    <= 32'd0;
        alu_output_forwd  <= 32'd0;
    end else begin
        alu_out_ex        <= alu_out_ex_n;
        branch_result_ex  <= branch_result_ex_n;
        rs2_for_mem_ex    <= rs2_for_mem_ex; // already registered in data_clipper? No, data_clipper is comb. Register here.
        alu_output_forwd  <= alu_output_forwd_n;
    end
end

// data_clipper is combinational, so register its output too
wire [31:0] rs2_for_mem_ex_comb;
data_clipper data_clip_ex_comb (
    .data_in  (rs2_reg_id),
    .clip_sel (data_cliper),
    .data_out (rs2_for_mem_ex_comb)
);

always @(posedge clk) begin
    if (rst) rs2_for_mem_ex <= 32'd0;
    else      rs2_for_mem_ex <= rs2_for_mem_ex_comb;
end

endmodule
