#!/usr/bin/env python3
"""Build reviewable RTL trees from the gate decisions in the bake-off.

Raw arm directories are audit records, so they may contain a rejected proposal
that was present when a later target ran.  PPA must start from the frozen RTL
and apply only accepted edits; otherwise a rejected rewrite silently receives
credit or blame in the model comparison.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "bench" / "rtl"
OUT = ROOT / "output" / "rtl_variants"

VARIANTS = {
    "baseline": {"status": "BASELINE", "source": BASE, "accepted": []},
    "nemotron_ultra": {
        "status": "TESTED",
        "source": ROOT / "artifacts/bakeoff_open/openrouter_nemotron-ultra/rtl",
        "accepted": ["fp8_adder.v"],
    },
    "nemotron_super": {"status": "TESTED_NO_ACCEPT", "source": BASE, "accepted": []},
    "nemotron_nano": {"status": "TESTED_NO_ACCEPT", "source": BASE, "accepted": []},
    "gemini_flash": {
        "status": "TESTED",
        "source": ROOT / "artifacts/bakeoff/gemini_gemini-flash/rtl",
        "accepted": ["axi_lite_dot.v"],
    },
    "gemma_free": {"status": "NOT_TESTED_HTTP_429", "source": BASE, "accepted": []},
    "gemini_pro": {"status": "NOT_TESTED_QUOTA", "source": BASE, "accepted": []},
    "claude_sonnet": {
        "status": "TESTED",
        "source": ROOT / "artifacts/bakeoff/anthropic_sonnet-direct/rtl",
        "accepted": ["fp8_adder.v"],
    },
    "combined_final": {
        "status": "FINAL_COMBINED",
        "source": ROOT / "artifacts/final_candidate/rtl",
        "accepted": ["axi_lite_dot.v", "fp4_dot_unit.v", "fp8_adder.v"],
        "copy_all": True,
    },
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    summary = {"baseline": str(BASE), "variants": []}
    baseline_files = sorted(BASE.glob("*.v"))
    for name, spec in VARIANTS.items():
        target = OUT / name / "rtl"
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(BASE, target)
        if spec.get("copy_all"):
            shutil.rmtree(target)
            shutil.copytree(spec["source"], target)
        else:
            for filename in spec["accepted"]:
                shutil.copy2(spec["source"] / filename, target / filename)

        changed = [
            path.name
            for path in baseline_files
            if digest(path) != digest(target / path.name)
        ]
        if sorted(changed) != sorted(spec["accepted"]):
            raise SystemExit(f"{name}: expected {spec['accepted']}, found {changed}")
        record = {
            "name": name,
            "status": spec["status"],
            "accepted_files": spec["accepted"],
            "changed_from_baseline": changed,
            "rtl_sha256": {
                path.name: digest(target / path.name) for path in baseline_files
            },
        }
        (OUT / name / "status.json").write_text(json.dumps(record, indent=2) + "\n")
        summary["variants"].append(record)

    (OUT / "manifest.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"wrote {len(VARIANTS)} verified RTL variants to {OUT}")


if __name__ == "__main__":
    main()
