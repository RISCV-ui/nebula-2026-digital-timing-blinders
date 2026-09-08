#!/bin/bash
cd /Users/shubhanshu/Desktop/Nebula/digital
exec python3 bench/scripts/g1c_stream.py \
  --golden bench/rtl --candidate artifacts/wns/rtl \
  --latency 4 --depth 10 --timeout 7200 \
  --out artifacts/wns/g1c_stream.json
