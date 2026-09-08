#!/bin/bash
cd /Users/shubhanshu/Desktop/Nebula/digital
exec python3 bench/scripts/loop.py \
  --targets artifacts/paths/baseline.json \
  --rtl artifacts/wns/golden \
  --out artifacts/wns/dryrun4 \
  --backend mock --mock-dir bench/mock_proposals \
  --clock clk_s5 --max-targets 3 --retries 2 --g1-timeout 2400 --g1c-depth 16
