#!/bin/bash
# Smoke test for the native Anthropic provider. Costs a few hundred tokens.
# Reads the key from ~/.config/nebula/env; never echoes it.
set -e
cd /Users/shubhanshu/Desktop/Nebula/digital
source ~/.config/nebula/env
if [ -z "$ANTHROPIC_API_KEY" ]; then echo "ANTHROPIC_API_KEY not set"; exit 1; fi
python3 - <<'PY'
import sys; sys.path.insert(0, "bench/scripts")
import llm
b = llm.get("anthropic:opus-direct")
print("backend:", b.name, "model:", b.model)
r = b.propose("Reply with a single JSON object and nothing else.",
              'Reply exactly {"ok": true}')
print("raw:", r[:200])
print("parsed:", llm.extract_json(r))
print("calls:", getattr(b, "calls", "?"))
PY
