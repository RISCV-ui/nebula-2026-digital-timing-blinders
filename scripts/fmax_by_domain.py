#!/usr/bin/env python3
"""Per-clock-domain Fmax and WNS, baseline against one or more variants.

The single global WNS this design reports is set by one path: a 32-deep
combinational restoring divider under `alu`, at -147 ns on clk1. That number
is real and it is reported, but quoting it alone as "the" result says nothing
about the other four master domains, whose paths a transform can actually
reach. A design with five asynchronous masters has five closure questions, and
collapsing them into one is a reporting choice that happens to hide every
result the run did produce.

Fmax here is 1/(period - WNS): the fastest this domain would close at, holding
everything else fixed. It is a per-domain figure and is not claimed to be the
chip's frequency -- the slowest domain still governs that, and it is printed
alongside so the two cannot be confused.

    usage: scripts/fmax_by_domain.py --before BASE.json --after V.json ...
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def fmax_mhz(period_ns: float, wns_ns: float | None) -> float | None:
    if wns_ns is None or period_ns is None:
        return None
    achievable = period_ns - wns_ns
    return 1000.0 / achievable if achievable > 0 else None


def unstable(period_ns: float, wns_ns: float | None) -> bool:
    """True when Fmax on this domain is too ill-conditioned to quote.

    Fmax is 1/(period - WNS), so a domain whose slack is nearly its whole
    period divides by a very small number and a hundredth of a nanosecond of
    ordinary placement variance moves it by hundreds of MHz. The gated clocks
    here sit exactly there -- clk_s1_gate has 23.1 ns of slack on a 25 ns
    period -- and quoting "+271 MHz" off a 0.63 ns slack change would be
    reporting the reciprocal's sensitivity as if it were an optimisation. The
    slack delta for those domains is real and is still printed; the frequency
    derived from it is not meaningful and is withheld.
    """
    if wns_ns is None or period_ns is None:
        return True
    return (period_ns - wns_ns) < 0.25 * period_ns


def load(path: str) -> dict:
    return json.loads(Path(path).read_text())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", required=True)
    ap.add_argument("--after", nargs="+", required=True)
    ap.add_argument("--out")
    a = ap.parse_args()

    base = load(a.before)
    variants = [(Path(p).stem, load(p)) for p in a.after]

    md = ["# Timing by clock domain", ""]
    md.append(f"Baseline: `{base.get('tag', a.before)}`. "
              f"Fmax is 1/(period - WNS) for that domain alone.")
    md.append("")

    for name, var in variants:
        md.append(f"## {name}")
        md.append("")
        md.append("| clock | period ns | WNS before | WNS after | "
                  "Fmax before | Fmax after | delta |")
        md.append("|---|---|---|---|---|---|---|")
        improved = []
        for clk, b in sorted((base.get("clocks") or {}).items()):
            v = (var.get("clocks") or {}).get(clk) or {}
            per = b.get("period_ns")
            wb, wa = b.get("wns_ns"), v.get("wns_ns")
            fb, fa = fmax_mhz(per, wb), fmax_mhz(per, wa)
            shaky = unstable(per, wb) or unstable(per, wa)
            if shaky:
                fb = fa = None
                d = "slack near period; Fmax not quoted"
            else:
                d = (f"{fa - fb:+.2f} MHz" if fb is not None and fa is not None
                     else "--")
                if fb is not None and fa is not None and fa - fb > 0.01:
                    improved.append((clk, fa - fb))
            md.append(
                f"| `{clk}` | {per if per is None else f'{per:.3f}'} | "
                f"{'--' if wb is None else f'{wb:.4f}'} | "
                f"{'--' if wa is None else f'{wa:.4f}'} | "
                f"{'--' if fb is None else f'{fb:.2f}'} | "
                f"{'--' if fa is None else f'{fa:.2f}'} | {d} |")
        md.append("")
        gw = var.get("wns") if var.get("wns") is not None else None
        bw = base.get("wns")
        md.append(f"Design WNS: {bw} -> {gw} ns (governed by the worst "
                  f"domain, not by the domains above).")
        if improved:
            md.append("")
            md.append("Domains that improved: " + ", ".join(
                f"`{c}` {d:+.2f} MHz" for c, d in improved) + ".")
        else:
            md.append("")
            md.append("No domain improved measurably.")
        md.append("")

    text = "\n".join(md)
    if a.out:
        Path(a.out).write_text(text + "\n")
        print(f"wrote {a.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
