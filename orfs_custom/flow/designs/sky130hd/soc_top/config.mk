# ===================================================================
#  soc_top -- Nebula 2026 digital track benchmark, sky130hd
#
#  Differs from the older nebula_soc design in three ways:
#    * the two OpenRAM SRAMs are hard macros, not flop arrays
#    * hierarchy is preserved for every module (no flattening)
#    * the fsm pass is off, so state encodings survive synthesis
#  Those last two are what make the post-synthesis netlist checkable
#  module by module against the RTL (scripts/eqy_netlist.py).
# ===================================================================

export DESIGN_NICKNAME = soc_top
export DESIGN_NAME     = soc_top
export PLATFORM        = sky130hd

# The RTL lives outside the ORFS tree; NEBULA_ROOT is the digital/ repo root.
export NEBULA_ROOT     ?= $(abspath $(DESIGN_HOME)/../../..)
export NEBULA_RTL      = $(NEBULA_ROOT)/Design-and-Implementation-of-a-Multi-Clock-Domain-RISC-V-SoC-Subsystems
export NEBULA_MACROS   = $(NEBULA_ROOT)/macros

# Every RTL file except the two OpenRAM simulation models. Those models
# declare the same module names as the macros; the liberty/LEF view is
# what the silicon actually is, so the stub file is read instead and the
# macros come in as black boxes.
export VERILOG_FILES = \
    $(filter-out $(NEBULA_RTL)/id_memory_256x64.v $(NEBULA_RTL)/tag_memory_92x64.v, \
                 $(sort $(wildcard $(NEBULA_RTL)/*.v))) \
    $(NEBULA_MACROS)/macro_blackbox_stubs.v

export SYNTH_BLACKBOXES = id_memory_256x64 tag_memory_92x64

# Design-local copy of book/sdc/nebula.sdc with the hierarchical clock-pin
# lookups made flatten-proof -- see the header of that file.
export SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc

# -------------------------------------------------------------------
# Macro views
# -------------------------------------------------------------------
export ADDITIONAL_LEFS = \
    $(NEBULA_MACROS)/id_memory_256x64/id_memory_256x64.lef \
    $(NEBULA_MACROS)/tag_memory_92x64/tag_memory_92x64.lef
export ADDITIONAL_LIBS = \
    $(NEBULA_MACROS)/id_memory_256x64/id_memory_256x64_TT_1p8V_25C.lib \
    $(NEBULA_MACROS)/tag_memory_92x64/tag_memory_92x64_TT_1p8V_25C.lib

# The OpenRAM GDS was generated on the WSL box and is not in this repo.
# Until it is copied in, let the final GDS merge treat the two macros as
# empty cells rather than fail. Drop GDS_ALLOW_EMPTY and uncomment
# ADDITIONAL_GDS once the .gds files land in macros/*/.
# export ADDITIONAL_GDS = $(NEBULA_MACROS)/id_memory_256x64/id_memory_256x64.gds \
#                         $(NEBULA_MACROS)/tag_memory_92x64/tag_memory_92x64.gds
export GDS_ALLOW_EMPTY = (id_memory_256x64|tag_memory_92x64)

# -------------------------------------------------------------------
# Synthesis: hierarchy true for all modules, no fsm re-encoding
# -------------------------------------------------------------------
export SYNTH_HIERARCHICAL = 1
export SYNTH_ARGS         = -nofsm

# Inferred memories stay as flop arrays. The largest is dmem at 8192 bits;
# the default 4096-bit ceiling exists to catch memories that should have
# been macros. dmem is on that list -- see the notes on future macro
# candidates -- but for now it is deliberately synthesised as flops.
export SYNTH_MEMORY_MAX_BITS = 16384

# keep_hierarchy on every RTL module. Without this list ORFS calls the
# keep_hierarchy pass, which decides for itself which modules survive;
# the equivalence check needs all of them by name.
export SYNTH_KEEP_MODULES ?= \
  alu alu_src_a_mux alu_src_b_mux arbiter asynchronous_fifo_gen \
  axi_interconnect_2m_8s axi_lite_dma_config axi_lite_dot axi_lite_gpio \
  axi_lite_master axi_lite_timer axi_lite_uart branch_comp_decoder \
  branch_comprator branch_predictor clk_div_mux clk_gate control_unit \
  csr_regfile data_clipper data_extender data_forwarding_unit dma_controller \
  dmem execution_stage fp4_dot_unit fp4_mul fp8_adder gpio_controller \
  hazard_detection_unit i_rom_32x256 id_memory_256x64_wrap \
  immediate_generator instruction_decode_stage instruction_fetch_stage \
  interrupt_control_unit l1_cache_axi_master l1_d_cache_8kb l1_i_cache_8kb \
  mem_axi_slave memory_stage multiplier_pipelined pipeline_reg_ex_mem \
  pipeline_reg_id_ex pipeline_reg_if_id pipeline_reg_mem_wb processor_top \
  read_buffer_d_cache read_buffer_i_cache register_file tag_memory_92x64_wrap \
  timer uart_controller write_back_stage

# OPENROAD_HIERARCHICAL is deliberately OFF. It keeps the hierarchy inside
# OpenROAD's database, which is a different thing from keeping it in the
# Yosys netlist -- and it is the netlist that the module-by-module
# equivalence check reads, so nothing is lost by flattening in odb.
# OpenROAD itself warns the -hier flow is in development, and it segfaults
# here: TritonCTS::writeDataToDb -> dbITerm::connect -> dbNetwork::direction
# crashes with signal 11 after building all five clock trees.
export OPENROAD_HIERARCHICAL = 0

# -------------------------------------------------------------------
# Floorplan
#
# Five macros are instantiated (one l1_d_cache_8kb: 4 x id_memory_256x64
# at 2228.76 x 226.435 um plus 1 x tag_memory_92x64 at 1530.38 x 234.245),
# so 2.38e6 um2 of the die is macro before a single standard cell is
# placed. The hierarchical no-fsm synth reports 82458 cells and 5.81e6 um2
# total, i.e. ~3.43e6 um2 of standard cell on top of the macros. A 3550 um
# square core is 1.26e7 um2, putting utilisation near 46%.
#
# Note on the two macro LEFs: each declares one more data bit than its
# liberty does (dout0[256] on the id macro, dout1[92] on the tag macro).
# That is OpenRAM's spare column, which the .lib does not model and the
# RTL does not connect, so OpenROAD warns ORD-2001 once per spare pin and
# leaves them unconnected. Expected, not a wiring bug.
# -------------------------------------------------------------------
export DIE_AREA  = 0 0 5200 5200
export CORE_AREA = 25 25 5175 5175

# Every signal pin on both OpenRAM macros sits on the bottom edge (the LEF
# puts din0/dout0/addr0 rects at y = 0.0 to 0.38), and the macro obstructs
# met1 through met3 across its whole area. So each macro needs a wide open
# channel under it or the 256-bit cache buses have nowhere to land: the
# first routing attempt failed GRT-0116 with the congestion report full of
# "capacity:0" tiles on d_cache_0/* and i_cache_0/* nets, i.e. routing
# pushed into gcells the macros had already blocked. Halo and channel are
# both wide for that reason, not out of caution.
# Macro positions are fixed by macro_placement.tcl, so the halo no longer
# has to buy the auto-placer room -- it only keeps std cells off the macro
# edge. Keep it small: the 168 um channel under each macro is where the
# cache datapath is meant to sit, and a 60 um halo would eat most of it.
export MACRO_PLACEMENT_TCL = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/macro_placement_r90.tcl
export MACRO_PLACE_HALO    = 10 10
export MACRO_PLACE_CHANNEL = 120 120

# No explicit PLACE_DENSITY: with the macros pinned to the left column the
# std cells have ~12.2e6 um2 to sit in for ~1.1e6 um2 of logic, and forcing
# a low target only pulls cells away from the macro they talk to.

export PLACE_DENSITY_LB_ADDON = 0.20

# Run 4. Runs 2 and 3 both died with GRT-0116, and the final congestion report
# says exactly where: of 167,419 total congestion, met2 carries 119,223 -- 71%
# -- and 17,022 of the 20,000 reported hot tiles have "capacity:0", i.e. global
# routing was pushed into gcells a macro had already blocked. met1 is at 23,060
# and met3 at 9,759, both with plenty of headroom.
#
# met2 is the VERTICAL layer in sky130hd (met1 H, met2 V, met3 H, met4 V,
# met5 H). Unrotated, each macro is 2228 um wide and 226 um tall, so it blocks
# vertical routing across its full 2228 um width -- the worst possible shape
# for the one layer that is short. Rotated R90 it is 226 um wide and 2229 um
# tall, blocking vertical routing over only 226 um and trading the pressure
# onto met1/met3, which have the headroom. Both LEFs declare SYMMETRY X Y R90.
#
# The die also grows 4200 -> 5200 so the ten macros (5.03e6 um2 of blockage)
# drop from 29% of the core to 19%, and so the R90 band leaves a clear
# 5150 x 2894 um block above it for logic.
#
# GRT's congestion loop was also diverging, not converging: hot tiles went
# 12,427 at iteration 10 -> 12,917 at 20 -> 20,000 (the report cap) at 30,
# while burning 3h21m. Cap it at 15 so a failing run reports back sooner.
# -verbose and the iteration-step reports are what produce the GRT-0096
# layer table and the per-iteration congestion-N.rpt files; without them a
# failing run tells you almost nothing. The iteration cap is the actual
# change: GRT's congestion loop was diverging, not converging (hot tiles
# 12,427 at iteration 10 -> 12,917 at 20 -> 20,000, the report cap, at 30)
# while burning 3h21m, so there is nothing to buy past ~15.
export GLOBAL_ROUTE_ARGS = -congestion_report_iter_step 5 -verbose \
                           -congestion_iterations 15

# met2/met3 carry no power grid; give them back most of the platform's
# flat 20% capacity derate. See the header of fastroute.tcl.
export FASTROUTE_TCL = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/fastroute.tcl

export REMOVE_ABC_BUFFERS = 1

# The macros' power pins are vccd1/vssd1, which no platform pin pattern
# matches. See the header of this pdn.tcl.
export PDN_TCL = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/pdn.tcl
