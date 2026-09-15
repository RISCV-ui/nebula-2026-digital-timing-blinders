`timescale 1ns / 1ps

// Instruction fetch.
//
// The old fetch path read i_mem (a 256x32 synchronous array) directly. It is
// now the instruction-side cache hierarchy, entirely inside the processor and
// off the system bus -- an instruction fetch every cycle cannot be made to
// share a bus master with the data side without wrecking fetch bandwidth:
//
//   pc_reg -> read_buffer_i_cache -> l1_i_cache_8kb -> i_rom_32x256
//
// The read buffer holds one 256-bit block and drives the selected word out
// COMBINATIONALLY on a hit, so a warm fetch costs one cycle and the address
// and its instruction are valid in the same cycle. That removes the whole
// layer of skew compensation the old sync-read i_mem needed (the instr_hold /
// pc_d / pc_hold / redirect_d skid registers): pc_if is simply pc_reg again.
//
// A miss (cold block, or stepping past a block boundary) takes ~11 cycles.
// While it is outstanding the fetch presents a bubble downstream and raises
// ifetch_stall so the pc holds; the back end keeps draining.

module instruction_fetch_stage(clk,rst,pc_en
                        ,pc_ex,branch_addr_ex,branch_result_ex,opcode_ex,
                         pc_pluse4_if,pc_if,instruction_if,

                         trap_in,mret_in,
                         mepc_in_id,mtvect_in,
                         branch_pred_result,
                         ifetch_stall

                         );


input clk,rst,pc_en,branch_result_ex;
input [31:0] pc_ex,branch_addr_ex;
input [6:0] opcode_ex;
input trap_in,mret_in;
input [31:0]mepc_in_id,mtvect_in;

output wire [31:0]pc_pluse4_if,pc_if,instruction_if;
output wire  branch_pred_result;
output wire  ifetch_stall;


/// i-cache hierarchy wires
wire [31:0] ic_addr_word;      // word address presented to the read buffer
wire [31:0] ic_instr;
wire        ic_valid;
wire        ic_hit;

wire [31:0] rb_addr_l1;
wire        rb_addr_valid_l1;
wire [255:0]l1_data;
wire        l1_data_valid;
wire        l1_hit;

wire [31:0] l1_addr_l2;
wire        l1_addr_valid_l2;
wire [255:0]rom_data;
wire        rom_data_valid;

wire hit;
wire pred_valid;
wire [31:0]branch_pred_out;

//// pc reg
reg [31:0]pc_reg;
reg stage1;
reg pred_out;

reg        redirect_pend;
reg [31:0] redirect_pend_addr;


// The cache hierarchy is word addressed (read_buffer_i_cache splits the
// address into a 29-bit tag and a 3-bit word offset into the 256-bit block),
// the pc is byte addressed. Same conversion the data side does in soc_top.
assign ic_addr_word = {2'b00, pc_reg[31:2]};

read_buffer_i_cache i_read_buffer(clk,rst,
                                  ic_addr_word,1'b1,
                                  ic_instr,ic_valid,ic_hit,
                                  rb_addr_l1,rb_addr_valid_l1,
                                  l1_data,l1_data_valid);

l1_i_cache_8kb i_cache_0(clk,rst,
                         rb_addr_l1,rb_addr_valid_l1,
                         l1_data,l1_data_valid,l1_hit,
                         l1_addr_l2,l1_addr_valid_l2,
                         rom_data,rom_data_valid);

i_rom_32x256 instruction_rom(clk,rst,
                             l1_addr_l2,l1_addr_valid_l2,
                             rom_data,rom_data_valid);

assign ifetch_stall = !ic_valid;


// Redirect target and its priority, unchanged from the original pc block:
// mret beats trap, trap beats a resolved branch.
wire        redirect_req;
wire [31:0] redirect_addr;
assign redirect_req  = trap_in || mret_in || branch_result_ex;
assign redirect_addr = mret_in ? mepc_in_id :
                       trap_in ? mtvect_in  : branch_addr_ex;

// A redirect that arrives while the pc is frozen would otherwise be dropped.
// branch_result_ex is held for the whole of a downstream stall (ID/EX is
// frozen with it), but an instruction-fetch miss does NOT stall the back end
// -- it feeds it bubbles -- so EX walks on and branch_result_ex is a single
// pulse. Latch it and apply it on the first cycle the pc is free to move.
always @(posedge clk)
begin
     if(rst)
     begin
          redirect_pend      <= 1'b0;
          redirect_pend_addr <= 32'd0;
     end
     else if(redirect_req && pc_en)
     begin
          redirect_pend      <= 1'b1;
          redirect_pend_addr <= redirect_addr;
     end
     else if(!pc_en)
     begin
          redirect_pend      <= 1'b0;
     end
end


//// pc
always @(posedge clk)
begin
   if(rst)
     begin
     pc_reg<=32'd0;   // if rst pc == 0
     end

   else if(!pc_en)  /// active low enable en 0 -- > pc <-- pc+4 or branch addr
                                     //// en 1 --> pc<-- pc  /// stall
    begin
      if(redirect_pend)          pc_reg <= redirect_pend_addr;
      else if(trap_in || mret_in)pc_reg <= mret_in ? mepc_in_id : mtvect_in;
      else if(pred_valid)        pc_reg <= branch_pred_out;
      else if(branch_result_ex)  pc_reg <= branch_addr_ex;
      else                       pc_reg <= pc_reg+32'd4;
    end

end


// Prediction delay chain: branch_predictor_result_if must reach the hazard
// unit in the cycle the predicted branch is in EX, where it is XOR-ed against
// branch_result_ex. With the combinational read buffer the front end is one
// stage shallower than it was with the sync-read i_mem (pc and its instruction
// are now valid in the same cycle), so this chain is two deep, not three:
// pc_reg -> IF/ID -> ID/EX.
always @(posedge clk) begin
    if (rst) begin
        stage1   <= 1'b0;
        pred_out <= 1'b0;
    end else begin
        stage1   <= pred_valid;
        pred_out <= stage1;
    end
end


// On a miss there is no instruction to hand over; present a bubble and let the
// back end drain while ifetch_stall holds the pc.
assign instruction_if = ic_valid ? ic_instr : 32'd0;
assign pc_if          = pc_reg;
assign pc_pluse4_if   = pc_reg+32'd4;



branch_predictor branch_pred_if(clk,rst,
                             pc_ex,branch_addr_ex,branch_result_ex,opcode_ex,pc_reg,
                             hit,pred_valid,branch_pred_out);


assign branch_pred_result= pred_out;



// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     hit, ic_hit, l1_hit,
                     1'b0};

endmodule
