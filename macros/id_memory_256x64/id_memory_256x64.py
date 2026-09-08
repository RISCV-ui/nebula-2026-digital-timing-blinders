word_size = 256
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
use_nix = False
keep_temp = True

output_path = "openram_output/id_memory_256x64"
output_name = "id_memory_256x64"
num_spare_cols = 1
num_spare_rows = 2
words_per_row = 2
# Use the analytical (elmore) model instead of ngspice simulation-based
# characterization -- gives delay AND dynamic/leakage power estimates
# without needing a multi-hour spice transient run.
analytical_delay = True
load_scales = [1]
slew_scales = [1]
