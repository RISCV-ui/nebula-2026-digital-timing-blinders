`timescale 1ns / 1ps



module execution_stage(clk,rst,pc_plus4_id,pc_id,opcode_id,src_reg_1_id,src_reg_2_id,
                        rs2_reg_id,data_cliper,
                        alu_operation_id,start_mul_id,mulh_mul_id,alu_out_sel_id,pc4_sel_id,
                        alu_out_ex,branch_result_ex,
                        opcode_ex,pc_ex,
                        mul_done_ex,mul_busy_ex,
                        rs2_for_mem_ex,
                        alu_output_forwd
                         );

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
output reg mul_done_ex,mul_busy_ex;
output reg [31:0]rs2_for_mem_ex;
output reg [31:0]alu_output_forwd;

wire [31:0] alu_out_wire;
wire        branch_result_wire;
wire [31:0] mul_out_wire;
wire [31:0] rs2_for_mem_wire;
wire        mul_done_wire, mul_busy_wire;

alu alu_ex (
    .clk(clk),
    .rst(rst),
    .src_a(src_reg_1_id),
    .src_b(src_reg_2_id),
    .alu_control(alu_operation_id),
    .alu_result(alu_out_wire),
    .zero(branch_result_wire)
);

multiplier_pipelined mul_unit_ex (
    .clk(clk),
    .rst(rst),
    .start_mul_id(start_mul_id),
    .src_reg_1_id(src_reg_1_id),
    .src_reg_2_id(src_reg_2_id),
    .mulh_mul_id(mulh_mul_id),
    .mul_busy_ex(mul_busy_wire),
    .mul_done_ex(mul_done_wire),
    .mul_out_wire(mul_out_wire)
);

data_clipper data_clip_ex (
    .rs2_reg_id(rs2_reg_id),
    .data_cliper(data_cliper),
    .rs2_for_mem_ex(rs2_for_mem_wire)
);

wire [31:0] alu_pcp4_wire;
assign alu_pcp4_wire = alu_out_sel_id ? mul_out_wire : alu_out_wire;
wire [31:0] alu_out_ex_wire;
assign alu_out_ex_wire = pc4_sel_id ? pc_plus4_id : alu_pcp4_wire;
wire [31:0] alu_output_forwd_wire;
assign alu_output_forwd_wire = alu_pcp4_wire;

always @(posedge clk) begin
    alu_out_ex <= alu_out_ex_wire;
    branch_result_ex <= branch_result_wire;
    opcode_ex <= opcode_id;
    pc_ex <= pc_id;
    mul_done_ex <= mul_done_wire;
    mul_busy_ex <= mul_busy_wire;
    rs2_for_mem_ex <= rs2_for_mem_wire;
    alu_output_forwd <= alu_output_forwd_wire;
end

endmodule
