`timescale 1ns / 1ps



module instruction_decode_stage(clk,rst,pc_plus4_if,pc_if,instruction_if,dest_reg_addr_wb,wb_data_wb,we_regfile_wb,inst_complete_wb,    /// input to id stage 
                                pc_plus4_id,pc_id,opcode_id,reg_1_data,reg_2_data,imm_ext_out,  /// ex stage data 
                                src_mux_sel_1,src_mux_sel_2,branch_operation_wire,
                                alu_operation,start_mul,mulh_mul,alu_out_sel,pc4_sel,     /// ex stage control signals 
                                extender_mem,dmem_en,dmem_wr,alu_dmem_sel, ///  meem stage control signal 
                                wen_reg_file,rd_reg_out,extend_wb, ///  wb stage control signals 
                                inst_complete_id ,   /// instruction count out from id stage 
                               
                                
                                trap_in_id,   /// to trap from vic                  
                                trap_cause_in_id,  //// cause of trap from vic      
                                mret_in_id,   /// make 1 when trap handling complete      
                                mepc_out_id, /// pc return                          
                                mtvec_out_id, /// hamdler address                   
                                mie_out_id ,/// global interrupt enable              
                                csr_rdata,
                                csr_hazard_id
                                
                                
                                
                                );

input clk,rst;                                
input [31:0] pc_plus4_if;                                 
input [31:0] pc_if;                                 
input [31:0] instruction_if;

// High while this instruction's rs1 is still in flight further down the
// pipeline. The csr file is read and written here in DECODE, out of reach of
// every forwarding path, so the write must not commit until the operand is
// real. The hazard unit holds the instruction in place meanwhile, and the
// write lands on the cycle the interlock releases.
input csr_hazard_id;
input [31:0] wb_data_wb;
input [4:0] dest_reg_addr_wb;
input we_regfile_wb;
input inst_complete_wb;

input trap_in_id;
input [31:0]trap_cause_in_id;
input mret_in_id;


output wire [31:0] pc_plus4_id;
output wire [31:0] pc_id;
output wire [6:0]  opcode_id;
output wire[31:0] reg_1_data;
output wire[31:0] reg_2_data;
output wire [31:0]imm_ext_out;
//output wire [31:0] rs2_reg;
output wire[3:0]  alu_operation;
output wire start_mul,mulh_mul;
output wire alu_out_sel,pc4_sel;
output wire [1:0] extender_mem;
output wire dmem_en,dmem_wr,alu_dmem_sel;
output wire wen_reg_file;
output wire [4:0] rd_reg_out;
output wire [2:0]extend_wb;
output wire inst_complete_id;


output wire [31:0]mepc_out_id;
output wire [31:0]mtvec_out_id;
output wire mie_out_id;
output wire [31:0]csr_rdata;

output wire [1:0]src_mux_sel_1,src_mux_sel_2;
output wire [2:0]branch_operation_wire;

///// alll wire and reg declerations

// instruction related
wire [6:0]opcode;
wire [6:0]fun7;
wire [2:0]fun3;
wire [4:0]reg_1_address;
wire [4:0]reg_2_address;
wire [4:0]reg_d_address;
 
// reg file wires 
////wire wen_reg_file;
//wire [31:0]reg_1_data;
//wire [31:0]reg_2_data;



/// csr 

wire [31:0] csr_read_id;



//// control unit output 

//wire [1:0]src_mux_sel_1; 
//wire [1:0]src_mux_sel_2;



/// immediate generator

//wire [31:0]imm_ext_out;

////  branch comp operation decoder

//wire [2:0]branch_operation_wire;


///////   csr wires

  wire [11:0] csr_addr;  //// selecting requried reg out of 7 
  wire  csr_we;    /// write we
  wire  csr_we_q;  /// ... qualified by the decode-stage operand interlock
  wire  [1:0]csr_op;    /// operation 00,01,10 - write,set,clear
  //wire  [31:0]csr_rdata;  //// read the data from csr reg , data will be visible after wb










//// assignment of all wire to its corresponding field

assign opcode     =     instruction_if[6:0];  
assign opcode_id  =     instruction_if[6:0];                ///
assign fun7       =     instruction_if[31:25];      ///
assign fun3       =     instruction_if[14:12];
assign reg_1_address =  instruction_if[19:15];
assign reg_2_address =  instruction_if[24:20];
assign reg_d_address =  instruction_if[11:7];   

 
assign csr_read_id = 32'd0;


//assign rs2_reg = reg_2_data;  /// making rs2 available in ex stage for memory


assign pc_plus4_id =   pc_plus4_if;// pc + 4 passing to next stage  
assign pc_id       =   pc_if;      /// pc   passing  to nexrt stage 



assign csr_addr =  instruction_if[31:20];

assign csr_we_q = csr_we && !csr_hazard_id;



//// all modules/ blocks instantiation


//// control unit 
control_unit control_unit_id(clk,rst,///in 
                           opcode,fun7,fun3,  // input
                           reg_d_address , /////   dest reg adddress
                           reg_2_address, /// src reg 2 adddresss 
                           csr_we,  /// csr write enable 
                           csr_op, //// csr operation 
                           src_mux_sel_1,src_mux_sel_2,start_mul,mulh_mul,  /// ex stage controlsignal
                           alu_out_sel, //// ex stage control signal 
                           alu_operation,//// ex stagge alu operation 
                           pc4_sel,     /// ex sstage 
                           extender_mem, /// 32 to 16 or 8 
                           dmem_en,dmem_wr,   /// mem stage control signal
                           alu_dmem_sel, ////   mem stge control to select alu out or mem out
                           wen_reg_file,  /// write back control 
                           rd_reg_out,   //// destination reg address  
                           extend_wb,   ///  to select 1 byte, 2byte , word data 000 is for word 
                           inst_complete_id  //// to count the instruction completed 
                           );


///// register file 
register_file reg_file_id( clk,
                           reg_1_address,
                           reg_2_address,
                           dest_reg_addr_wb,
                           wb_data_wb,
                           we_regfile_wb,
                           reg_1_data,
                           reg_2_data
                         );
                                
        
///// csr reg file 
                                  
csr_regfile  csr_regfile_id (
                              clk,
                              rst,
                              csr_addr,  //// selecting requried reg out of 7 
                              csr_we_q,  /// write we, held off while rs1 is in flight
                              csr_op,    /// operation 00,01,10 - write,set,clear
                              reg_1_data,  /// input from reg file 
                              csr_rdata,  //// read the data from csr reg , data will be visible after wb
                              trap_in_id,   ///  any exception /intrrupt
                              pc_id,    /// current pc address
                              trap_cause_in_id,  // who cause trap
                              mret_in_id, ///   make 1 when trap completed
                              inst_complete_wb, ///  make 1 when instruction completed 
                              mtvec_out_id, ///  handler addresss
                              mepc_out_id,///  returning
                              mie_out_id ///// global interrupt enable 
                            );



/// immediate generator
immediate_generator imm_gen_id(instruction_if,
                               imm_ext_out
                                  );



////// src mux 1 
//alu_src_a_mux  src_mx1(reg_1_data,  /// rs1 data
//                       pc_if,      /// pc 
//                       csr_rdata, /// csr reg file output data
//                       src_mux_sel_1, // select line
//                       src_reg_1 /// output to ex stage
//                       );

///// src mux 2 
//alu_src_b_mux  src_mx2(reg_2_data,  /// rs2
//                       imm_ext_out,  /// imm value 
//                       src_mux_sel_2, /// sel
//                       src_reg_2   /// output to alu 
//                        );

/////// branch comprator 

//branch_comprator branch_comp_id(reg_1_data,
//                                reg_2_data,
//                                branch_operation_wire,
//                                branch_result
//                                 );

//////  branch comprator opoeration decoder 

branch_comp_decoder branch_decoder(opcode,
                                   fun3,
                                   branch_operation_wire
                                   );
                                  
                                  
                                  
                                  
                                  
                                  
                                  

// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     csr_read_id,
                     1'b0};

endmodule
