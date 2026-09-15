`timescale 1ns / 1ps

// Memory stage.
//
// This stage used to instantiate its own dmem, so the core had a private
// data memory that bypassed the whole bus. The d-cache / AXI path built at
// the SoC level was therefore dead silicon: requests were presented on the
// master port but data_in_m_axi was never consumed, and every load actually
// returned from the local array. That also duplicated the 256x32 memory --
// once here, once behind mem_axi_slave -- for ~27.5K redundant cells.
//
// The local dmem is gone. Load data now arrives from the bus (mem_data_in,
// driven by the d-cache read buffer), and processor_top holds the pipeline
// until that data is valid. The single main memory now lives behind
// mem_axi_slave at the SoC level.

module memory_stage(alu_out_ex,
                    mem_data_in,
                    alu_dmem_sel_ex,
                    mem_stage_out_alu,
                    mem_stage_out_load,
                    alu_dmem_sel_wb
                    );

input [31:0] alu_out_ex;
input [31:0] mem_data_in;
input alu_dmem_sel_ex;

output wire [31:0] mem_stage_out_alu;
output wire [31:0] mem_stage_out_load;
output wire alu_dmem_sel_wb;

assign mem_stage_out_alu  = alu_out_ex;
assign mem_stage_out_load = mem_data_in;
assign alu_dmem_sel_wb    = alu_dmem_sel_ex;

endmodule
