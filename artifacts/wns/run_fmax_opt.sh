#!/bin/bash
cd /Users/shubhanshu/Desktop/Nebula/digital
source orfs/env.sh
F=orfs/flow/results/sky130hd/nebula_bench/opt
exec python3 bench/scripts/fmax.py \
  --odb $F/6_final.odb --sdc $F/6_final.sdc \
  --out artifacts/metrics/fmax_opt.json
