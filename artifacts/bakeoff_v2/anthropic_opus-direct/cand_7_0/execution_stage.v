`timescale 1ns / 1ps



module execution_stage(clk,rst,pc_plus4_id,pc_id,opcode_id,src_reg_1_id,src_reg_2_id,//// input 
                        rs2_reg_id,data_cliper,           //// input 
                        alu_operation_id,start_mul_id,mulh_mul_id,alu_out_sel_id,pc4_sel_id, // ex stage control 
                        alu_out_ex,branch_result_ex,///output of ex stage
                        opcode_ex,pc_ex,
                        mul_done_ex,mul_busy_ex,
                        rs2_for_mem_ex , 
                        alu_output_forwd /// 
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

output wire [31:0] alu_out_ex;  //// for mem stage 
output wire branch_result_ex;
output wire [6:0]opcode_ex;
output wire [31:0]pc_ex;
output wire mul_done_ex,mul_busy_ex;
output wire [31:0]rs2_for_mem_ex;  /// for mem stage 
output wire [31:0]alu_output_forwd;

///// all wire and reg decleretion 

wire [31:0]alu_out_wire;      // ALU result, now produced 32 cycles after its inputs
wire        alu_zero_wire;    // ALU branch flag, same 32 cycle latency
wire [31:0]mul_out_wire;
wire [31:0]rs2_clip_wire;
wire       mul_busy_wire;
wire       mul_done_wire;
wire [31:0]alu_pcp4_wire;

///  all modules instantiation 

/// alu  (internally pipelined: the 32 step restoring divide is one step per stage)

alu alu_ex(.clk        (clk),
           .src_a      (src_reg_1_id),
           .src_b      (src_reg_2_id),
           .alu_control(alu_operation_id),
           .alu_result (alu_out_wire),
           .zero       (alu_zero_wire)
           );

/// multiplier 

multiplier_pipelined mul_unit_ex(clk,
                                 rst,
                                 start_mul_id,
                                 src_reg_1_id,
                                 src_reg_2_id,
                                 mulh_mul_id,         
                                 mul_busy_wire,
                                 mul_done_wire,
                                 mul_out_wire
                                 );

//// data clipper 32 to 32 , 16 , 8 bits 

data_clipper data_clip_ex(rs2_reg_id,
                          data_cliper,
                          rs2_clip_wire 
                          );

//// every other output of this stage is delayed by the same 32 cycles as the ALU

reg [31:0] pcp4_d  [0:31];
reg [31:0] pc_d    [0:31];
reg [6:0]  op_d    [0:31];
reg [31:0] rs2_d   [0:31];
reg [31:0] mul_d   [0:31];
reg        pc4s_d  [0:31];
reg        alus_d  [0:31];
reg        mdone_d [0:31];
reg        mbusy_d [0:31];

integer k;
always @(posedge clk) begin
    pcp4_d[0]  <= pc_plus4_id;
    pc_d[0]    <= pc_id;
    op_d[0]    <= opcode_id;
    rs2_d[0]   <= rs2_clip_wire;
    mul_d[0]   <= mul_out_wire;
    pc4s_d[0]  <= pc4_sel_id;
    alus_d[0]  <= alu_out_sel_id;
    mdone_d[0] <= mul_done_wire;
    mbusy_d[0] <= mul_busy_wire;
    for (k = 1; k < 32; k = k + 1) begin
        pcp4_d[k]  <= pcp4_d[k-1];
        pc_d[k]    <= pc_d[k-1];
        op_d[k]    <= op_d[k-1];
        rs2_d[k]   <= rs2_d[k-1];
        mul_d[k]   <= mul_d[k-1];
        pc4s_d[k]  <= pc4s_d[k-1];
        alus_d[k]  <= alus_d[k-1];
        mdone_d[k] <= mdone_d[k-1];
        mbusy_d[k] <= mbusy_d[k-1];
    end
end

assign opcode_ex        = op_d[31];
assign pc_ex            = pc_d[31];
assign rs2_for_mem_ex   = rs2_d[31];
assign mul_done_ex      = mdone_d[31];
assign mul_busy_ex      = mbusy_d[31];
assign branch_result_ex = alu_zero_wire;

assign alu_pcp4_wire    = (alus_d[31]) ? mul_d[31]  : alu_out_wire;
assign alu_out_ex       = (pc4s_d[31]) ? pcp4_d[31] : alu_pcp4_wire;
assign alu_output_forwd = alu_pcp4_wire;

endmodule
