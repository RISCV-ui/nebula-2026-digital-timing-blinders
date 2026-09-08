#!/bin/bash
cd /Users/shubhanshu/Desktop/Nebula/digital
exec python3 bench/scripts/g1_equiv.py \
  --golden bench/rtl --candidate artifacts/wns/rtl \
  --module fp4_dot_unit --latency 4 --enable en --reset rst \
  --timeout 7200 --out artifacts/wns/g1_fp4_dot_unit.json
