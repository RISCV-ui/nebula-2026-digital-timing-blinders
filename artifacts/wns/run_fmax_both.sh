#!/bin/bash
cd /Users/shubhanshu/Desktop/Nebula/digital
source orfs/env.sh
R=orfs/flow/results/sky130hd/nebula_bench
for v in base opt; do
  echo "=== $v ==="
  python3 bench/scripts/fmax.py \
    --odb $R/$v/6_final.odb --sdc $R/$v/6_final.sdc --lo 0.05 \
    --out artifacts/metrics/fmax_${v}_lo05.json
done
