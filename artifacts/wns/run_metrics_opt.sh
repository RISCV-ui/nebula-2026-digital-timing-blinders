#!/bin/bash
cd /Users/shubhanshu/Desktop/Nebula/digital
source orfs/env.sh
F=orfs/flow/results/sky130hd/nebula_bench/opt
exec python3 bench/scripts/metrics.py \
  --odb $F/6_final.odb --sdc $F/6_final.sdc \
  --logs orfs/flow/logs/sky130hd/nebula_bench/opt \
  --tag opt_final --out artifacts/metrics/opt_final.json
