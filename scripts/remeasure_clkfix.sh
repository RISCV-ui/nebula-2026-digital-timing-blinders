#!/usr/bin/env bash
# Re-measure PPA after the clock-structure fix.
#
# clk_gate became a latch-based ICG and clk_div_mux became a glitch-free
# handover mux. Both sit in the clock path of every peripheral domain, so
# every PnR number measured before them describes RTL that no longer exists.
# The accepted edits themselves did not change, so the loop is not re-run --
# what is re-run is the measurement, for the baseline and for both arms whose
# edit was accepted, all three against the same clock RTL and the same SDC.
#
# Sequential on purpose. Three concurrent routes on a 12-core box with the
# netlist EQY shards still running is how a run reports numbers that reflect
# machine contention instead of the design.
set -uo pipefail
ROOT=/Users/shubhanshu/Desktop/Nebula/digital
cd "$ROOT"

OUT_ROOT="$ROOT/artifacts/model_ppa_v2_clkfix"
mkdir -p "$OUT_ROOT"

# Wait for the equivalence shards to finish before starting. They are
# CPU-bound and already running; overlapping them with a route slows both and
# leaves the timing numbers dependent on who finished first.
#
# Bounded, because "wait for something else to finish" is how a chain stops
# without failing. Each shard has its own per-strategy timeout, so an overrun
# past this bound means one is wedged, and the measurement is worth more than
# the last two unproven modules -- it proceeds and says so.
waited=0
while pgrep -qf "scripts/eqy_netlist.py"; do
  if [ "$waited" -ge 5400 ]; then
    echo "WARNING: eqy shards still running after 90 min; starting anyway"
    break
  fi
  sleep 120
  waited=$((waited + 120))
done

# Stall watchdog. ORFS writes to its step logs continuously; a run whose whole
# log tree stops growing for 45 minutes is stuck, not slow. Without this the
# chain waits forever on one wedged detail route and nothing downstream --
# metrics, the report, the PDF -- ever runs.
#
# Progress is measured as the newest mtime anywhere under the run directory.
# `find -newermt` is not portable here (this box's find is bfs and rejects
# relative timestamps), and a plain file count never shrinks, so neither is a
# usable stall signal.
watchdog() {
  local tag="$1" dir="$2" pid="$3" last=0 now quiet=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 300
    now=$(find "$dir" -type f -exec stat -f %m {} + 2>/dev/null \
          | sort -n | tail -1)
    now=${now:-0}
    if [ "$now" -le "$last" ]; then
      quiet=$((quiet + 300))
    else
      quiet=0
    fi
    last=$now
    if [ "$quiet" -ge 2700 ]; then
      echo "WATCHDOG: $tag produced no output for 45 min -- killing it"
      pkill -f "FLOW_VARIANT=$tag" 2>/dev/null
      kill -TERM "$pid" 2>/dev/null
      sleep 10
      kill -KILL "$pid" 2>/dev/null
      return
    fi
  done
}

echo "=== [0/4] clock audit and runt simulation (must be clean first) ==="
python3 bench/scripts/clockcheck.py --rtl bench/rtl_v2 \
  --out artifacts/clockcheck_v2.json || exit 1
python3 scripts/run_clock_sim.py --out artifacts/clocksim.json || exit 1

echo "=== [1/4] rebuild variant trees from the frozen RTL ==="
python3 scripts/prepare_variants_v2.py || exit 1

i=2
for V in baseline anthropic_sonnet-direct openrouter_nemotron-ultra; do
  echo "=== [$i/4] PnR $V ==="
  date
  mkdir -p "$OUT_ROOT/pnr_$V"
  scripts/run_variant_pnr.sh "$V" "$OUT_ROOT" nebula_bench_v2 \
      "$ROOT/output/rtl_variants_v2" > "$OUT_ROOT/$V.log" 2>&1 &
  pnr_pid=$!
  watchdog "$V" "$OUT_ROOT/pnr_$V" "$pnr_pid" &
  wd_pid=$!
  wait "$pnr_pid"
  rc=$?
  kill "$wd_pid" 2>/dev/null
  echo "$V rc=$rc $(date)"
  # A failed variant does not stop the chain: the baseline plus one arm is
  # still a comparison, and the metrics step skips whatever has no routed
  # database. Stopping here would throw away the runs that did finish.
  [ "$rc" -eq 0 ] || echo "WARNING: $V did not finish -- see $OUT_ROOT/$V.log"
  i=$((i + 1))
done

echo "=== [5/6] metrics from the routed databases ==="
STAMP=$(date +%Y%m%d_%H%M)
MET="$ROOT/artifacts/metrics_v2_$STAMP"
mkdir -p "$MET"
for v in "$OUT_ROOT"/pnr_*; do
  [ -d "$v" ] || continue
  name=$(basename "$v" | sed 's/^pnr_//')
  r="$v/results/sky130hd/nebula_bench_v2/$name"
  odb=$(ls "$r"/6_*.odb "$r"/5_route.odb 2>/dev/null | tail -1)
  sdc=$(ls "$r"/6_*.sdc "$r"/5_route.sdc 2>/dev/null | tail -1)
  [ -n "$odb" ] || { echo "$name: no routed odb, skipping"; continue; }
  python3 bench/scripts/metrics.py --odb "$odb" --sdc "$sdc" \
    --logs "$v/logs/sky130hd/nebula_bench_v2/$name" \
    --tag "$name" --out "$MET/$name.json" || echo "$name: metrics failed"
done

for f in "$MET"/*.json; do
  name=$(basename "$f" .json)
  [ "$name" = baseline ] && continue
  [ -f "$MET/baseline.json" ] || { echo "no baseline metrics"; break; }
  python3 bench/scripts/ppa_report.py --before "$MET/baseline.json" \
    --after "$f" --out "$ROOT/artifacts/ppa_v2_${STAMP}_$name" 2>&1 | tail -3
done

echo "=== [6/6] regenerate every number in the report ==="
# build_report.py picks the newest artifacts/metrics_v2_* directory, so this
# is what actually moves the report onto the re-measured numbers.
python3 scripts/build_report.py
python3 scripts/build_figures.py || true
(cd report && pdflatex -interaction=nonstopmode nebula_report.tex >/dev/null 2>&1 \
  && pdflatex -interaction=nonstopmode nebula_report.tex >/dev/null 2>&1)

echo "=== done ==="
date
