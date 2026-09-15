#!/usr/bin/env python3
"""Build reviewable RTL trees from the gate decisions in the v2 bake-off.

Same job as prepare_model_variants.py, and the same rule: PPA must start from
the frozen RTL and apply only edits a gate accepted, so a rejected rewrite can
never be measured as if it were real.

The difference is that nothing here is hardcoded. prepare_model_variants.py
carries a table naming each arm and the files it was expected to change, which
was fine when there were three arms and one target between them. v2 runs four
arms over three targets in three clock domains, and a table written by hand
ahead of the run would be a guess about what the models will do.

So the accepted set is derived twice and the two derivations must agree:

  - structurally, by diffing the arm's own accumulating tree against the
    frozen input, and
  - from the record, by reading every ACCEPTED row out of history.jsonl.

loop.py only splices a candidate into that tree after every gate has passed,
so the two should be identical. When they are not, something is wrong with the
run and this exits rather than shipping a variant nobody can account for.

    usage: scripts/prepare_variants_v2.py [--bakeoff DIR] [--out DIR]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "bench" / "rtl_v2"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def accepted_from_history(arm: Path) -> set[str]:
    """Every module an ACCEPTED row names, as a file name.

    A proposal may carry `submodules`, so one acceptance can legitimately
    change more than one file; those are read from the record too rather than
    inferred, which is what keeps this check independent of the diff.
    """
    hist = arm / "history.jsonl"
    if not hist.exists():
        return set()
    names: set[str] = set()
    for line in hist.read_text().splitlines():
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if rec.get("verdict") != "ACCEPTED":
            continue
        # `accepted_modules`, when the run recorded it, is the set loop.py
        # confirmed actually differed from the working tree at accept time.
        # Older runs predate the field and only have the proposal's own
        # claim about what it edited, which can name a module whose text it
        # left untouched; those fall back to the claim, and the diff check
        # below is what catches the difference.
        if rec.get("accepted_modules"):
            names.update(f"{m}.v" for m in rec["accepted_modules"])
            continue
        if rec.get("proposal_module"):
            names.add(f"{rec['proposal_module']}.v")
        for child in (rec.get("submodules") or []):
            names.add(f"{child}.v")
    return names


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bakeoff", default=str(ROOT / "artifacts" / "bakeoff_v2"),
                    help="directory holding one subdirectory per arm")
    ap.add_argument("--out", default=str(ROOT / "output" / "rtl_variants_v2"))
    a = ap.parse_args()

    bakeoff = Path(a.bakeoff)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    base_files = sorted(BASE.glob("*.v"))

    # The baseline is a variant like any other, with an empty accepted set. It
    # has to be built by the same code path as the rest: a PPA comparison in
    # which the baseline was produced differently from what it is compared
    # against is not a comparison.
    arms = [("baseline", None)]
    arms += sorted((d.name, d) for d in bakeoff.iterdir()
                   if d.is_dir() and (d / "rtl").is_dir())

    summary = {"baseline_rtl": str(BASE), "variants": []}
    for name, arm in arms:
        source = BASE if arm is None else arm / "rtl"
        target = out / name / "rtl"
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(BASE, target)

        changed = []
        for path in base_files:
            cand = source / path.name
            if cand.exists() and digest(cand) != digest(path):
                shutil.copy2(cand, target / path.name)
                changed.append(path.name)
        # A file the arm added that the frozen tree does not have is not a
        # legal outcome: the catalogue's transforms rewrite modules, they do
        # not introduce new ones, and a stray file would join the design
        # silently at synthesis.
        extra = sorted({p.name for p in source.glob("*.v")}
                       - {p.name for p in base_files})
        if extra:
            sys.exit(f"{name}: {source} has files not in the frozen tree: {extra}")

        if arm is not None:
            recorded = accepted_from_history(arm)
            if set(changed) != recorded:
                sys.exit(
                    f"{name}: the tree and the record disagree about what was "
                    f"accepted.\n  diff says:   {sorted(changed)}\n"
                    f"  history says: {sorted(recorded)}")

        summary["variants"].append({
            "name": name,
            "rtl": str(target),
            "accepted": sorted(changed),
            "source": str(source),
        })
        print(f"{name:<28} {len(changed)} accepted edit(s): "
              f"{', '.join(sorted(changed)) or '-'}")

    (out / "variants.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"\nwrote {out/'variants.json'}")


if __name__ == "__main__":
    main()
