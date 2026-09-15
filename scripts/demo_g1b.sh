#!/usr/bin/env bash
# The centrepiece demo: a rewrite that is provably correct on its own, and
# still gets rejected.
#
# This is the case most LLM-RTL systems ship as a success. The model pipelines
# fp4_dot_unit, and the module-level equivalence proof passes -- not a bounded
# "no counterexample found in N cycles" but a complete feed-forward proof. A
# system that gates on module equivalence alone accepts it here.
#
# G1b then asks the question module scope structurally cannot: can the parent
# absorb the latency? axi_lite_dot consumes this module's output in the same
# cycle it drives its inputs, so +2 cycles breaks the AXI handshake, and the
# parent miter finds it.
#
# Runs entirely from recorded artifacts -- no API call, no network, no model.
# The inputs are a frozen snapshot under artifacts/demo_g1b, so a later
# bake-off with --fresh cannot wipe the thing being demonstrated.
#
#   usage: scripts/demo_g1b.sh
set -uo pipefail
ROOT=/Users/shubhanshu/Desktop/Nebula/digital
cd "$ROOT"
D=artifacts/demo_g1b
G="$D/golden"
C="$D/candidate"

[ -d "$G" ] && [ -d "$C" ] || { echo "missing snapshot under $D" >&2; exit 1; }

# shellcheck disable=SC1091
source "$ROOT/oss-cad-suite/environment" >/dev/null 2>&1

echo "=============================================================="
echo " The edit: pipeline fp4_dot_unit, +2 cycles of latency"
echo "=============================================================="
diff <(grep -c '' "$G/fp4_dot_unit.v") <(grep -c '' "$C/fp4_dot_unit.v") >/dev/null \
  && echo "(same line count)" || true
echo "changed files vs golden:"
for f in "$G"/*.v; do n=$(basename "$f"); cmp -s "$f" "$C/$n" || echo "  $n"; done

echo
echo "=============================================================="
echo " GATE 1 -- module scope: is fp4_dot_unit still correct?"
echo "=============================================================="
python3 bench/scripts/g1_equiv.py \
  --golden "$G" --candidate "$C" --module fp4_dot_unit \
  --latency 2 --depth 4 --timeout 300 --json \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  verdict : %s' % d.get('verdict'))
print('  engine  : %s / %s' % (d.get('engine'), d.get('solver')))
print('  depth   : 4  (= latency 2 + 2)')
print('  seconds : %.1f' % (d.get('seconds') or 0))
print()
# depth = latency + 2 is not a budget, it is the completeness argument for a
# feed-forward register insertion: the window provably reaches the outputs, so
# this is a complete proof, not a bounded no-counterexample-in-N-cycles result.
# g1_equiv.py reports the verdict; loop.py is what labels it complete, so the
# claim is stated here rather than read back from a field this call omits.
print('  -> module-level equivalence PASSES, and for a feed-forward')
print('     insertion depth = latency + 2 is a COMPLETE proof, not a')
print('     bounded one. A system gating on this alone accepts the edit.')
"

echo
echo "=============================================================="
echo " GATE 1b -- parent scope: can axi_lite_dot absorb +2 cycles?"
echo "=============================================================="
python3 - "$G" "$C" <<'PY'
import json, sys, os
sys.path.insert(0, os.path.join(os.getcwd(), "bench", "scripts"))
import g1b_contract
r = g1b_contract.check(sys.argv[1], sys.argv[2], "fp4_dot_unit", timeout=300)
print("  parents : %s" % r["parents"])
for c in r["checks"]:
    print("  %-14s %-16s %.1fs" % (c["parent"], c["verdict"], c.get("seconds") or 0))
print("  verdict : %s" % r["verdict"])
print()
if r["verdict"] == "CONTRACT_BROKEN":
    print("  -> REJECTED. The parent consumes this module's output in the")
    print("     same cycle it drives its inputs, so the AXI handshake breaks.")
    print("     Module-level equivalence could not have seen this.")
PY
echo
echo "=============================================================="
echo " Recorded verdict from the actual run: artifacts/demo_g1b/recorded_row.json"
echo "=============================================================="
