#!/usr/bin/env python3
"""Re-render the bake-off comparison from bakeoff.json, excluding named arms.

An arm is excluded when it was never actually measured -- the free-tier daily
quota ran out after one call, say -- not when it scored badly. Those are
opposite situations and only one of them is honest to drop: a model that
attempted three targets and closed none is a result, and belongs in the table;
a model that attempted one target and was then cut off by a rate limit has no
accept rate to report, and printing "0/3" for it publishes a number the run
never measured.

So an exclusion is never silent. Every excluded arm is listed under the table
with the reason, and bakeoff.json itself is left untouched -- this only changes
what the comparison renders, so the raw record of all four arms survives.

    usage: scripts/bakeoff_table.py --bakeoff DIR --exclude ARM=REASON ...
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bench" / "scripts"))
import bakeoff  # noqa: E402


def harness_losses(bakeoff_dir: Path) -> dict[str, tuple[int, int]]:
    """Per arm: (calls lost to a truncated reply, total rows).

    A reply that spends its whole token budget on thinking comes back with no
    text block at all, and an empty reply is indistinguishable downstream from
    an unparseable one -- so it was recorded as a refusal and the target was
    abandoned. Two of the four v2 arms lost more than half their targets that
    way while a third, on a different provider, lost none. Comparing accept
    rates across those arms without saying so would credit the harness's
    failure to the models: the arm that "proposed less" was cut off, not
    reticent. This is read from history.jsonl rather than bakeoff.json because
    it is a property of the individual calls, which the summary does not carry.
    """
    out: dict[str, tuple[int, int]] = {}
    for arm in sorted(bakeoff_dir.iterdir()):
        hist = arm / "history.jsonl"
        if not hist.exists():
            continue
        lost = total = 0
        for line in hist.read_text().splitlines():
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("module") is None:
                continue
            total += 1
            if (rec.get("verdict") == "TRUNCATED"
                    or str(rec.get("detail") or "") == "unparseable reply"):
                lost += 1
        if total:
            out[arm.name] = (lost, total)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bakeoff", default="artifacts/bakeoff_v2")
    ap.add_argument("--exclude", nargs="*", default=[],
                    metavar="ARM=REASON",
                    help="arm substring and why it was not measured")
    ap.add_argument("--out", help="write markdown here (default: stdout)")
    a = ap.parse_args()

    data = json.loads((Path(a.bakeoff) / "bakeoff.json").read_text())
    rows = data["arms"]

    drops = []
    for spec in a.exclude:
        if "=" not in spec:
            sys.exit(f"--exclude wants ARM=REASON, got {spec!r}")
        name, reason = spec.split("=", 1)
        hit = [r for r in rows if name in r["arm"]]
        if not hit:
            sys.exit(f"no arm matching {name!r} in {a.bakeoff}/bakeoff.json")
        for r in hit:
            drops.append((r["arm"], reason, r))
        rows = [r for r in rows if name not in r["arm"]]

    if not rows:
        sys.exit("every arm was excluded -- nothing left to compare")

    md = bakeoff.markdown(rows, data.get("golden", "bench/rtl_v2"))
    if drops:
        md += "\n\n**Not measured** (excluded from the comparison above, "
        md += "raw records retained in `bakeoff.json`):\n\n"
        for arm, reason, r in drops:
            md += (f"- `{arm}` -- {reason}. Reached {r['proposals']} "
                   f"proposal(s) before stopping; no accept rate is "
                   f"computable from that.\n")
    losses = harness_losses(Path(a.bakeoff))
    hit = {k: v for k, v in losses.items() if v[0]}
    if hit:
        md += ("\n\n**Calls lost to the harness, not to the models.** These "
               "targets were never really attempted: the reply spent its "
               "whole token budget before emitting any text, and an empty "
               "reply was recorded as a refusal, which abandoned the target. "
               "Accept rates below are per arm as run, so an arm with losses "
               "here is not comparable to one without:\n\n")
        for arm, (lost, total) in sorted(hit.items()):
            md += f"- `{arm}` -- {lost} of {total} calls lost\n"
        clean = [k for k, v in losses.items() if not v[0]]
        if clean:
            md += ("\nUnaffected: " + ", ".join(f"`{c}`" for c in sorted(clean))
                   + ".\n")

    if a.out:
        Path(a.out).write_text(md + "\n")
        print(f"wrote {a.out}")
    else:
        print(md)


if __name__ == "__main__":
    main()
