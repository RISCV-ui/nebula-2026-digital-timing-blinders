# Stage 5 — OpenROAD-flow-scripts (ORFS): Full RTL-to-GDS PPA Flow

## Goal
Run a design through the complete synthesis-to-layout flow (not just
STA on a hand-synthesized netlist like Stage 0/1) and get real PPA
(Power/Performance/Area) numbers: floorplan, placement, clock tree
synthesis (CTS), routing, and final area/power reports.

## The blocker this stage started with, and why native build was needed
First attempt used ORFS's official Docker image (`openroad/orfs:latest`).
That image is **amd64-only** (confirmed via `docker manifest inspect` — no
arm64 manifest exists). Running it on Apple Silicon means Docker silently
falls back to QEMU emulation, translating amd64 instructions to arm64 at
runtime. The flow crashed with **SIGILL (illegal instruction) during CTS**
— QEMU's translation doesn't correctly handle certain CPU-optimized
instructions (AVX2/BMI2-class) that OpenROAD's binaries use.

**Fix chosen (confirmed with user over two alternatives — patching QEMU CPU
flags, or deferring the issue): build ORFS natively for arm64.** Runs
real native Apple Silicon instructions, no emulation layer, no SIGILL risk.

## Building natively — full one-time dependency chain
This is a one-time compile. Once done, the binaries at
`tools/install/OpenROAD/bin/openroad` and `tools/install/yosys/bin/yosys`
are reused by every future `make` run — nothing here needs repeating unless
the repo is wiped or moved to a new machine.

### Homebrew dependencies
```bash
brew install or-tools qt@5 tcl-tk@8 swig libffi ruby python libomp \
  doxygen capnp bison flex spdlog zlib googletest yaml-cpp icu4c zstd
brew install The-OpenROAD-Project/lemon-graph/lemon-graph
```
`qt@5` and `tcl-tk@8` are specifically the VERSIONED formulas — plain `qt`/
`tcl-tk` are not sufficient. `lemon-graph` must come from OpenROAD's own tap
— the generic `brew install lemon` package doesn't ship CMake config files
`find_package(LEMON)` needs.

### CUDD (BDD package) — no Homebrew formula exists, build from source
```bash
git clone --depth=1 -b 3.0.0 https://github.com/The-OpenROAD-Project/cudd.git /tmp/cudd
cd /tmp/cudd
autoreconf
./configure --prefix=/Users/shubhanshu/Desktop/Nebula/orfs/dependencies
make -j10 install
```

### Full git submodule fetch (shallow fetch fails on pinned commits)
```bash
git submodule deinit -f .
git submodule update --init --recursive   # NOT --depth 1
```
Shallow (`--depth 1`) fails with "shallow file has changed since we read
it" / commit not found, because the pinned submodule commit isn't a branch
tip GitHub will serve at shallow depth.

### Anaconda contamination — must be scrubbed from every build invocation
If conda's `base` environment auto-activates in your shell (check
`CONDA_SHLVL`/`CONDA_PREFIX`), `/opt/anaconda3` ships its own `libfmt`,
Python3, and GTest CMake configs that CMake can resolve ahead of Homebrew's,
causing version/ABI mismatches. Every build command in this stage strips it:
```bash
CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v anaconda | tr '\n' ':' | sed 's/:$//')
env -u CONDA_PREFIX -u CONDA_SHLVL -u CONDA_DEFAULT_ENV -u CONDA_PROMPT_MODIFIER \
  PATH="$CLEAN_PATH" <build command>
```

### The actual configure + build command
```bash
cd orfs
cmake -B tools/OpenROAD/build tools/OpenROAD \
  -D CUDD_DIR=$(pwd)/dependencies \
  -D TCL_LIBRARY=/opt/homebrew/opt/tcl-tk@8/lib/libtcl8.6.dylib \
  -D TCL_INCLUDE_PATH=/opt/homebrew/opt/tcl-tk@8/include \
  -D FLEX_INCLUDE_DIR=/opt/homebrew/opt/flex/include \
  -D CMAKE_PREFIX_PATH=/opt/homebrew \
  -D CMAKE_IGNORE_PATH="/opt/anaconda3/lib;/opt/anaconda3/include;/opt/anaconda3/bin" \
  -D Python3_FIND_STRATEGY=LOCATION \
  -D Python3_ROOT_DIR=/opt/homebrew/opt/python3 \
  -D CMAKE_EXE_LINKER_FLAGS="-L/opt/homebrew/lib -L/opt/homebrew/opt/icu4c@78/lib" \
  -D CMAKE_SHARED_LINKER_FLAGS="-L/opt/homebrew/lib -L/opt/homebrew/opt/icu4c@78/lib" \
  -D CMAKE_CXX_FLAGS="-DBOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED" \
  -D CMAKE_INSTALL_PREFIX=$(pwd)/tools/install/OpenROAD

cmake --build tools/OpenROAD/build --target install -j 10
```

## Problems hit + fixes (in the order they appeared)

| # | Problem | Root cause | Fix |
|---|---|---|---|
| 1 | SIGILL during CTS | amd64 Docker image under QEMU translation on arm64 | switch to native arm64 build |
| 2 | Shallow submodule fetch fails | pinned commit not servable at shallow depth | full `git submodule update --init --recursive` |
| 3 | `brew --prefix or-tools` fails | not installed | `brew install or-tools` |
| 4 | `qt@5 not found` | plain `qt` insufficient, needs versioned formula | `brew install qt@5` |
| 5 | `tcl-tk@8 not found` | same, versioned formula required | `brew install tcl-tk@8` |
| 6 | `swig missing` | not installed | `brew install swig` |
| 7 | `find_package(LEMON)` fails | generic `lemon` formula lacks CMake config | `brew install The-OpenROAD-Project/lemon-graph/lemon-graph` |
| 8 | `CUDD_LIB NOTFOUND` | no Homebrew formula for CUDD exists at all | build from source into `orfs/dependencies`, pass `CUDD_DIR` |
| 9 | `FLEX_INCLUDE_DIR`/`TCL_LIBRARY` NOTFOUND | CMake couldn't auto-locate versioned Homebrew paths | pass explicit `-D` paths |
| 10 | `fmt::v11::vformat` link error (`fft_test`) + Python3/GTest resolving from `/opt/anaconda3` | conda base env auto-activated, shadowing Homebrew | scrub `/opt/anaconda3` from `PATH`, unset `CONDA_*`, pin `CMAKE_PREFIX_PATH=/opt/homebrew` + `CMAKE_IGNORE_PATH` |
| 11 | `no member named 'format' in namespace 'fmt'` in `AbstractFlowAnalysis.cpp` (persisted after fix #10) | genuine upstream vendoring bug: vendored fmt 11.2.1 needs `<fmt/format.h>` for `fmt::format()`, 10 slang source files only included `<fmt/core.h>` | patched all 10 files: `#include <fmt/core.h>` → `#include <fmt/format.h>` |
| 12 | `ld: library 'zstd' not found` | bare `-lzstd` linker flag with no `-L` path to Homebrew's lib dir | add `-L/opt/homebrew/lib` via `CMAKE_EXE_LINKER_FLAGS` |
| 13 | `ld: library 'icudata' not found` | `icu4c` is keg-only, not symlinked into `/opt/homebrew/lib` | add `-L/opt/homebrew/opt/icu4c@78/lib` |
| 14 | `Boost.Stacktrace requires _Unwind_Backtrace... Define _GNU_SOURCE` | boost::stacktrace's glibc-only guard doesn't recognize macOS's libunwind-based availability | `-DBOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED` in `CMAKE_CXX_FLAGS` |
| 15 | `yosys -c script.tcl`: "Option 'c' does not exist" | tried reusing OSS CAD Suite's mainline Yosys (0.67), which dropped `-c`; ORFS's own pinned/patched Yosys submodule still has it | build ORFS's own `tools/yosys` submodule separately, same fix set (`CMAKE_PREFIX_PATH`, `CMAKE_IGNORE_PATH`, linker `-L` paths, `BOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED`) |
| 16 | GDS export step: `Error: KLayout not found` | KLayout (GDS/DRC/LVS viewer+tool) not installed | non-blocking — only affects GDS/DRC/LVS targets, not synthesis/STA/PPA numbers; install KLayout separately if GDS output is needed later |

## Running the flow
```bash
cd orfs/flow
make DESIGN_CONFIG=./designs/sky130hd/gcd/config.mk YOSYS_EXE=<path to ORFS's own yosys>
```
`YOSYS_EXE`/`OPENROAD_EXE` resolve automatically to
`tools/install/{yosys,OpenROAD}/bin/...` if not found on `PATH`
(see `flow/scripts/variables.mk`), so this only needs to be set explicitly
if a different Yosys happens to be on `PATH` first (as OSS CAD Suite's was
in this case).

## What the flow actually does, stage by stage
```
1_synth   -- Yosys: RTL -> generic gates -> tech-mapped netlist (same idea
             as Stage 0's manual synth script, run via ORFS's own scripts)
2_floorplan -- define chip area, utilization, power grid (PDN)
3_place   -- global placement (approximate positions) then detailed
             placement (legalized, no overlaps)
4_cts     -- Clock Tree Synthesis: insert clock buffers to distribute the
             clock signal to every flop with minimal skew
5_route   -- global routing (coarse) then detailed routing (DRC-clean wires)
6_finish  -- final reports: timing (WNS/TNS), area, power, IR drop
```
Each stage writes reports to `flow/reports/<platform>/<design>/base/`,
named `N_<stage>.rpt` (or `_final`/`_check` variants), matching the
numbering above — read the report matching the number of the stage you
care about, e.g. `4_cts_final.rpt` for the post-CTS timing snapshot.

## Real results — `gcd` design, `sky130hd` platform
Constraint (`designs/sky130hd/gcd/constraint.sdc`): `clk_period = 1.1ns`
(deliberately aggressive, same "force a violation on purpose" idea as
Stage 0's traffic light).

| Stage | WNS (max) | TNS (max) |
|---|---|---|
| Post-CTS (`4_cts_final.rpt`) | -1.39 ns | -60.39 ns |
| Final, post-route (`6_finish.rpt`) | -1.47 ns | -65.72 ns |

Post-CTS clock skew: **0.01 ns setup skew** — tight, expected for a small
design with a straightforward clock tree.

Final area/power (`6_finish.rpt` cell report):
- **Design area**: 4977 um² at **85% utilization**
- **Total power**: 8.56 mW (`8.56e-03 W`)
- **Worst-case IR drop**: 1.26 mV on VDD (0.07%), 0.876 mV on VSS (0.05%) —
  both comfortably small relative to the 1.8V supply
- **Cell breakdown**: 839 total cells — 226 multi-input combinational, 171
  timing-repair buffers (inserted by the resizer to fix timing/DRC), 35
  sequential (flops), 75 tap cells, 7 clock buffers, 319 fill cells

**Reading this honestly**: WNS is still negative (-1.47ns) — this design
does NOT close timing at this aggressive 1.1ns period as-is. That's
expected and fine for validating the flow itself; timing closure via
RTL edits is exactly what Stage 8's LLM loop will attempt later, on the
Stage 6 benchmark design, using this same report format as its input.

## Command reference
```bash
# one-time native build (see full dependency list above)
cmake -B tools/OpenROAD/build tools/OpenROAD <all -D flags above>
cmake --build tools/OpenROAD/build --target install -j 10
cmake -B tools/yosys/build tools/yosys -DCMAKE_BUILD_TYPE=Release \
  -DYOSYS_SKIP_ABC_SUBMODULE_CHECK=ON -DCMAKE_INSTALL_PREFIX=$(pwd)/tools/install/yosys \
  <same CMAKE_PREFIX_PATH/CMAKE_IGNORE_PATH/linker/boost flags as OpenROAD build>
cmake --build tools/yosys/build --target install -j 10

# every future run, reusing the built binaries
cd orfs/flow
make DESIGN_CONFIG=./designs/sky130hd/gcd/config.mk

# read results
cat reports/sky130hd/gcd/base/6_finish.rpt      # final WNS/TNS/area/power
cat reports/sky130hd/gcd/base/4_cts_final.rpt   # post-CTS timing + skew
```
