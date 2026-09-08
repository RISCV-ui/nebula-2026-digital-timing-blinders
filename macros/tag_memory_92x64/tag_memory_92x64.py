word_size = 92
num_words = 64
tech_name = "sky130"

nominal_corner_only = True
process_corners = ["TT"]
supply_voltages = [1.8]

num_rw_ports = 1
num_r_ports = 1

check_lvsdrc = True
run_drc = False
run_lvs = True
# We already run everything inside a working `nix develop` shell (see
# run_openram.sh), so all DRC/LVS tools are already on PATH. OpenRAM's
# run_script() re-wraps every external tool call in ANOTHER `nix develop`
# with cwd=openram_temp, which has no flake.nix and fails to resolve.
# Disabling use_nix skips that redundant (and broken, in this setup) rewrap.
use_nix = False
# Preserve OPTS.openram_temp instead of deleting it at the end, so the real
# LVS report files survive for inspection instead of being wiped.
keep_temp = True

output_path = "openram_output/tag_memory_92x64"
output_name = "tag_memory_92x64"
num_spare_cols = 1
num_spare_rows = 2
words_per_row = 4
# Use the analytical (elmore) model instead of ngspice simulation-based
# characterization -- gives delay AND dynamic/leakage power estimates
# without needing a multi-hour spice transient run.
analytical_delay = True
load_scales = [1]
slew_scales = [1]
