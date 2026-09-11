#!/usr/bin/env python3
"""
ppa_report.py -- before/after PPA and per-clock timing, as one report.

Deliverable 5 asks for a timing, frequency and PPA comparison. The numbers for
both sides already exist as `metrics.py` dumps; what was missing was the step
that puts them side by side without quietly flattering the result.

Three things this refuses to do, because each of them turns a real finding into
a better-looking table:

  * A clock whose `wns_ns` is `null` had no timing path reported for it at all.
    That is not zero slack and it is not a passing clock -- it usually means the
    domain is unconstrained or its paths were folded into another clock's
    group. Printing it as 0.000 would put five clean-looking rows in the table
    that no tool ever checked. It is printed as `no paths` and excluded from
    every aggregate.
  * Instance count is only comparable between two runs at the *same* flow
    stage. `5_1_grt` has 170,837 instances and `6_final` has 480,545 for the
    identical design -- the difference is filler and tap cells inserted after
    routing, not optimisation. Comparing across stages is refused outright.
  * Improvement is signed against what the metric wants. Smaller area is
    better, larger WNS is better, and a single "% change" column that does not
    know the difference reads backwards for half the rows.

    ppa_report.py --before artifacts/metrics/baseline_final.json \\
                  --after  artifacts/metrics/optimized_final.json
"""

import argparse, json, os, sys

# metric -> (label, unit, direction) where direction is +1 when larger is
# better and -1 when smaller is better.
METRICS = [
    ("instances",   "Instances",       "",     -1),
    ("area_um2",    "Cell area",       "um^2", -1),
    ("nets",        "Nets",            "",     -1),
    ("utilization_pct", "Utilisation", "%",     0),
    ("power_total_w", "Total power",   "W",    -1),
    ("wns",         "WNS (setup)",     "ns",   +1),
    ("tns",         "TNS (setup)",     "ns",   +1),
    ("wns_hold",    "WNS (hold)",      "ns",   +1),
    ("tns_hold",    "TNS (hold)",      "ns",   +1),
    ("drc_violations",     "DRC violations",     "", -1),
    ("antenna_violations", "Antenna violations", "", -1),
]


def stage_of(m):
    """Which ORFS stage the numbers came from, taken from the odb path."""
    p = m.get("odb") or ""
    return os.path.basename(p).replace(".odb", "") or "unknown"


def fmt(v, unit=""):
    if v is None:
        return "not reported"
    if isinstance(v, float):
        s = f"{v:,.4f}".rstrip("0").rstrip(".")
    else:
        s = f"{v:,}"
    return s + (f" {unit}" if unit else "")


def delta(before, after, direction):
    """(absolute change, percent change, verdict) -- None when incomparable."""
    if before is None or after is None:
        return None, None, "not reported"
    d = after - before
    pct = (d / abs(before) * 100.0) if before else None
    if direction == 0 or d == 0:
        return d, pct, "same" if d == 0 else "changed"
    return d, pct, ("better" if (d > 0) == (direction > 0) else "worse")


def fmax(period_ns, wns_ns):
    """
    A single-point Fmax estimate used only when no measured sweep is supplied.
    The clock only runs at its target if slack is non-negative, so 1/period is
    not an achievable frequency for a failing clock.
    """
    if wns_ns is None:
        return None
    eff = period_ns - wns_ns
    return 1000.0 / eff if eff > 0 else None


def clock_rows(b, a, fb=None, fa=None):
    names = sorted(set(b.get("clocks", {})) | set(a.get("clocks", {})))
    rows = []
    for n in names:
        cb = b.get("clocks", {}).get(n, {})
        ca = a.get("clocks", {}).get(n, {})
        wb, wa = cb.get("wns_ns"), ca.get("wns_ns")
        pb = cb.get("period_ns") or ca.get("period_ns")
        measured_b = (fb or {}).get("fmax", {}).get(n, {}).get("fmax_mhz")
        measured_a = (fa or {}).get("fmax", {}).get(n, {}).get("fmax_mhz")
        rows.append({
            "clock": n, "period_ns": pb,
            "wns_before": wb, "wns_after": wa,
            "fmax_before": (measured_b if fb is not None else
                            fmax(pb, wb) if pb else None),
            "fmax_after":  (measured_a if fa is not None else
                            fmax(pb, wa) if pb else None),
            "met_before": None if wb is None else wb >= 0,
            "met_after":  None if wa is None else wa >= 0,
            "delta_ns": None if (wb is None or wa is None) else wa - wb,
        })
    return rows


def markdown(b, a, rows, ppa):
    L = [f"# PPA and timing comparison", "",
         f"- **before:** `{b.get('tag')}` · stage `{stage_of(b)}` · {b.get('timestamp')}",
         f"- **after:**  `{a.get('tag')}` · stage `{stage_of(a)}` · {a.get('timestamp')}",
         "", "## Area, power, congestion", "",
         "| metric | before | after | change | |", "|---|---|---|---|---|"]
    for key, label, unit, _ in ppa["metrics"]:
        r = ppa["values"][key]
        ch = ("--" if r["abs"] is None else
              f"{r['abs']:+,.4f}".rstrip("0").rstrip(".") +
              (f" ({r['pct']:+.2f}%)" if r["pct"] is not None else ""))
        L.append(f"| {label} | {fmt(r['before'], unit)} | {fmt(r['after'], unit)} "
                 f"| {ch} | {r['verdict']} |")

    L += ["", "## Per-clock timing and achievable frequency", "",
          ("Fmax is measured by binary search over each clock's SDC period "
           "with extracted parasitics and propagated clocks."
           if ppa["frequency_method"] == "measured period sweep" else
           "Fmax is estimated as `1/(period - WNS)` because no measured period "
           "sweep was supplied."), "",
          "A **generated** clock's Fmax is the speed its own paths could stand, "
          "not a speed the design can be run at: it is divided down from a "
          "master, so it moves only when the master moves and is capped by the "
          "master's own slack. The design frequency is set by the master "
          "clocks; the generated rows are there to show where the slack sits, "
          "not to be quoted as headroom.", "",
          "| clock | period | WNS before | WNS after | ΔWNS | Fmax before | Fmax after |",
          "|---|---|---|---|---|---|---|"]
    for r in rows:
        def w(x):
            return "no paths" if x is None else f"{x:+.4f} ns"
        def f(x):
            return "--" if x is None else f"{x:.1f} MHz"
        d = "--" if r["delta_ns"] is None else f"{r['delta_ns']:+.4f}"
        L.append(f"| `{r['clock']}` | {r['period_ns']} ns | {w(r['wns_before'])} "
                 f"| {w(r['wns_after'])} | {d} | {f(r['fmax_before'])} "
                 f"| {f(r['fmax_after'])} |")

    s = ppa["clock_summary"]
    L += ["", f"**{s['met_after']} of {s['constrained']} constrained clocks meet "
          f"timing after optimisation** (was {s['met_before']}). "
          f"{s['unreported']} clocks reported no path and are excluded from that "
          f"count -- an unconstrained domain is an open question, not a pass.", ""]
    if s["regressed"]:
        L.append("Clocks whose slack got worse: "
                 + ", ".join(f"`{c}`" for c in s["regressed"]) + ".")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", required=True)
    ap.add_argument("--after", required=True)
    ap.add_argument("--fmax-before",
                    help="measured fmax.py JSON for the golden design")
    ap.add_argument("--fmax-after",
                    help="measured fmax.py JSON for the candidate design")
    ap.add_argument("--out", default="artifacts/ppa/report")
    ap.add_argument("--allow-stage-mismatch", action="store_true",
                    help="compare runs from different flow stages anyway")
    a_ = ap.parse_args()

    b = json.load(open(a_.before))
    a = json.load(open(a_.after))
    if bool(a_.fmax_before) != bool(a_.fmax_after):
        sys.exit("pass both --fmax-before and --fmax-after, or neither")
    fb = json.load(open(a_.fmax_before)) if a_.fmax_before else None
    fa = json.load(open(a_.fmax_after)) if a_.fmax_after else None

    sb, sa = stage_of(b), stage_of(a)
    if sb != sa and not a_.allow_stage_mismatch:
        sys.exit(
            f"refusing to compare stage {sb} against stage {sa}: instance and "
            f"area counts are not comparable across ORFS stages (filler and tap "
            f"cells land between them), so every row would be a flow artifact "
            f"rather than a result. Re-run metrics.py on the same stage for "
            f"both, or pass --allow-stage-mismatch if you know why you want it.")

    values = {}
    for key, label, unit, direction in METRICS:
        d, pct, verdict = delta(b.get(key), a.get(key), direction)
        values[key] = {"before": b.get(key), "after": a.get(key),
                       "abs": d, "pct": pct, "verdict": verdict}

    rows = clock_rows(b, a, fb, fa)
    con = [r for r in rows if r["wns_after"] is not None]
    summary = {
        "constrained": len(con),
        "unreported": len(rows) - len(con),
        "met_before": sum(1 for r in rows if r["met_before"]),
        "met_after": sum(1 for r in rows if r["met_after"]),
        "regressed": [r["clock"] for r in rows
                      if r["delta_ns"] is not None and r["delta_ns"] < 0],
    }
    ppa = {"metrics": METRICS, "values": values, "clock_summary": summary,
           "frequency_method": ("measured period sweep" if fb is not None
                                else "single-point slack estimate")}

    os.makedirs(os.path.dirname(a_.out) or ".", exist_ok=True)
    md = markdown(b, a, rows, ppa)
    open(a_.out + ".md", "w").write(md + "\n")
    json.dump({"before": b.get("tag"), "after": a.get("tag"), "stage": sa,
               "ppa": values, "clocks": rows, "clock_summary": summary,
               "frequency_method": ppa["frequency_method"],
               "fmax_before": a_.fmax_before, "fmax_after": a_.fmax_after},
              open(a_.out + ".json", "w"), indent=2)

    print(md)
    print(f"\nwrote {a_.out}.md and {a_.out}.json")
    # Non-zero when the optimisation made any constrained clock worse: that is
    # the condition a flow should stop on, not a bad area number.
    return 1 if summary["regressed"] else 0


if __name__ == "__main__":
    sys.exit(main())
