#!/usr/bin/env python3
"""Build the review package without copying multi-gigabyte tool workdirs."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT.parent / "Astera_Nebula_Digital_Timing_Blinders_20260911.zip"

ROOT_FILES = [
    ".gitignore",
    "CLAUDE.md",
    "WORKLOG.md",
    "SUBMISSION_PACKAGE_README.md",
    "demo.py",
    "Nebula 2026 Topics .pptx",
    "Nebula_Abstract.pdf",
    "benchmark.png",
    "domains.pdf",
    "flowx.drawio (1).png",
]

TREES = [
    "bench/rtl",
    "bench/constraints",
    "bench/scripts",
    "bench/mock_proposals",
    "docs",
    "scripts",
    "macros",
    "sta/sky130hd",
    "output/pdf",
    "artifacts/audit_20260910",
    "artifacts/submission_20260911",
    "artifacts/final_candidate/rtl",
    "artifacts/final_candidate/orfs_run/reports/sky130hd/nebula_bench/final_candidate",
    "artifacts/synth_report",
    "artifacts/bakeoff",
    "artifacts/bakeoff_open",
    "artifacts/bakeoff_signoff_nemotron_ultra_20260910",
    "artifacts/bakeoff_signoff_gemma_free_20260911",
    "artifacts/bakeoff_all_20260911",
    "artifacts/loop",
    "artifacts/loop_g1b",
    "artifacts/paths",
    "orfs/flow/designs/sky130hd/nebula_bench",
]

FILES = [
    "bench/DECISIONS.md",
    "bench/README.md",
    "orfs/env.sh",
    "artifacts/synth/soc_top_named.v",
    "artifacts/eqy/hier4.log",
    "artifacts/eqy/soc_top_hier4.json",
    "artifacts/eqy/report.md",
    "artifacts/eqy/report.json",
    "orfs/flow/reports/sky130hd/nebula_bench/base/6_finish.rpt",
    "orfs/flow/reports/sky130hd/nebula_bench/base/5_route_drc.rpt",
    "orfs/flow/reports/sky130hd/nebula_bench/base/drt_antennas.log",
    "orfs/flow/reports/sky130hd/nebula_bench/opt/6_finish.rpt",
    "orfs/flow/reports/sky130hd/nebula_bench/opt/5_route_drc.rpt",
    "orfs/flow/reports/sky130hd/nebula_bench/opt/drt_antennas.log",
]

FINAL_ROOT_GLOBS = ["*.json", "*.md", "*.txt", "soc_top_named.v", "driver_*.log"]
SKIP_NAMES = {".DS_Store", "__pycache__", ".pytest_cache"}
SECRET_PATTERNS = [
    re.compile(rb"(?:GEMINI|OPENROUTER|ANTHROPIC)_API_KEY\s*=[^\s]+"),
    re.compile(rb"sk-or-v1-[A-Za-z0-9_-]{20,}"),
    re.compile(rb"sk-ant-[A-Za-z0-9_-]{20,}"),
]


def add_tree(files: set[Path], rel: str) -> None:
    base = ROOT / rel
    if not base.exists():
        return
    for candidate in base.rglob("*"):
        if candidate.is_file() and not any(part in SKIP_NAMES for part in candidate.parts):
            files.add(candidate)


def collect() -> list[Path]:
    files: set[Path] = set()
    for rel in ROOT_FILES + FILES:
        candidate = ROOT / rel
        if not candidate.is_file():
            raise FileNotFoundError(rel)
        files.add(candidate)
    for rel in TREES:
        add_tree(files, rel)
    final_root = ROOT / "artifacts/final_candidate"
    for pattern in FINAL_ROOT_GLOBS:
        files.update(path for path in final_root.glob(pattern) if path.is_file())
    return sorted(files)


def check_secrets(files: list[Path]) -> None:
    hits: list[str] = []
    for candidate in files:
        data = candidate.read_bytes()
        if any(pattern.search(data) for pattern in SECRET_PATTERNS):
            hits.append(str(candidate.relative_to(ROOT)))
    if hits:
        raise RuntimeError("possible secret in: " + ", ".join(hits))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    files = collect()
    check_secrets(files)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for candidate in files:
            archive.write(candidate, Path("digital") / candidate.relative_to(ROOT))

    digest = hashlib.sha256(args.out.read_bytes()).hexdigest()
    with zipfile.ZipFile(args.out) as archive:
        bad = archive.testzip()
    if bad:
        raise RuntimeError(f"ZIP CRC failed at {bad}")

    print(f"PACKAGE {args.out}")
    print(f"FILES {len(files)}")
    print(f"BYTES {args.out.stat().st_size}")
    print("SECRET_SCAN PASS")
    print("CRC PASS")
    print(f"SHA256 {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
