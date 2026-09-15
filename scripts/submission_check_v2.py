#!/usr/bin/env python3
"""Verify the v2/v3 digital bundle: the PDF, the numbers, and the evidence.

scripts/submission_check.py pins the v1 (2026-09-11) bundle to hand-written
expected values. That works once and then rots, so this takes the opposite
approach: it regenerates every report fragment from the artifacts into a
scratch directory and diffs it against what is actually shipped. If any
number in the PDF is no longer the number the artifacts produce, the diff
says so by name.

    usage: scripts/submission_check_v2.py [--strict-pdf]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "report" / "generated"
PDF = ROOT / "report" / "nebula_report.pdf"

# \reportgenerated is a clock reading, not a measurement: it differs on every
# run by construction and must not be treated as drift.
VOLATILE = re.compile(r"\\newcommand\{\\reportgenerated\}")

REQUIRED = [
    "README.md",
    "report/nebula_report.pdf",
    "report/nebula_report.tex",
    "report/generated/numbers.tex",
    "report/generated/tab_ppa.tex",
    "report/generated/tab_v3.tex",
    "report/generated/tab_accepts.tex",
    "report/generated/tab_eqy_netlist.tex",
    "report/generated/fig_soc.tex",
    "bench/constraints/nebula.sdc",
    "bench/scripts/loop.py",
    "bench/scripts/metrics.py",
    "artifacts/paths/v2_targets.json",
    "artifacts/clockcheck_v2.json",
    "artifacts/clocksim.json",
    "artifacts/eqy_v2_serial_partial.log",
]

results: list[tuple[bool, str, str]] = []


def check(ok: bool, name: str, detail: str = "") -> bool:
    results.append((bool(ok), name, detail))
    return bool(ok)


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def strip_volatile(text: str) -> str:
    return "".join(l for l in text.splitlines(keepends=True)
                   if not VOLATILE.search(l))


# ------------------------------------------------------------------ checks

def check_required() -> None:
    missing = [r for r in REQUIRED if not (ROOT / r).is_file()]
    check(not missing, "required_files", ", ".join(missing))


def check_numbers_current() -> None:
    """Regenerate the fragments from the artifacts and diff against shipped."""
    with tempfile.TemporaryDirectory() as tmp:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "build_report.py"),
             "--out", tmp], capture_output=True, text=True, cwd=ROOT)
        if proc.returncode != 0:
            check(False, "numbers_regenerate", proc.stderr.strip()[-300:])
            return
        check(True, "numbers_regenerate")

        drift, absent = [], []
        for fresh in sorted(Path(tmp).glob("*.tex")):
            shipped = GEN / fresh.name
            if not shipped.is_file():
                absent.append(fresh.name)
            elif strip_volatile(fresh.read_text()) != strip_volatile(shipped.read_text()):
                drift.append(fresh.name)
        check(not absent, "every_fragment_shipped", ", ".join(absent))
        check(not drift, "numbers_match_artifacts", ", ".join(drift) +
              ("  (run scripts/build_report.py and rebuild the PDF)" if drift else ""))


def macros() -> dict[str, str]:
    out = {}
    for m in re.finditer(r"\\newcommand\{\\(\w+)\}\{(.*)\}",
                         (GEN / "numbers.tex").read_text()):
        out[m.group(1)] = m.group(2)
    return out


def check_accepts_independently(n: dict) -> None:
    """Recount ACCEPTED rows straight from the run logs.

    build_report.py owns the named-run list; this walks the same files without
    importing it, so a mistake in that list shows up as a disagreement rather
    than being reproduced identically on both sides.
    """
    runs = [ROOT / "artifacts" / "bakeoff_v2_sonnet_fixed",
            ROOT / "artifacts" / "divider_run"]
    runs += [p.parent for p in sorted((ROOT / "artifacts" / "bakeoff_v2")
                                      .glob("*/history.jsonl"))]
    seen = 0
    for run in runs:
        hist = run / "history.jsonl"
        if not hist.is_file():
            continue
        for line in hist.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                if json.loads(line).get("verdict") == "ACCEPTED":
                    seen += 1
            except json.JSONDecodeError:
                pass
    check(str(seen) == n.get("numaccepted"), "accepted_count_independent",
          f"logs say {seen}, report says {n.get('numaccepted')}")


def check_pdf(strict: bool) -> None:
    if not PDF.is_file():
        check(False, "pdf_present", "report/nebula_report.pdf")
        return
    fresh = PDF.stat().st_mtime >= (GEN / "numbers.tex").stat().st_mtime
    check(fresh, "pdf_newer_than_numbers",
          "" if fresh else "PDF predates the numbers it should contain")

    text = subprocess.run(["pdftotext", str(PDF), "-"], capture_output=True,
                          text=True).stdout
    if not text:
        check(False, "pdf_readable", "pdftotext produced nothing")
        return
    check(True, "pdf_readable", f"{len(text)} chars")

    # "[pending]" is build_report.py's visible marker for a missing artifact.
    # The report also explains the marker in prose, which is the one allowed
    # occurrence.
    pend = [l for l in text.splitlines() if "[pending]" in l
            and "renders as a visible" not in l]
    check(not pend, "no_pending_markers", " | ".join(pend[:3]))

    # Unresolved LaTeX references print as ??. The casez priority encoder in
    # the diff appendix is full of Verilog wildcards that also read as ?? --
    # and pdftotext turns the size tick into a curly quote, so match the
    # literal shape (9'b1????????) with either quote rather than an ASCII one.
    sized_literal = re.compile(r"[0-9]+\s*['\u2018\u2019`]\s*[bBhHdDoO]")
    qq = [l for l in text.splitlines()
          if "??" in l and "casez" not in l and not sized_literal.search(l)]
    check(not qq, "no_unresolved_refs", " | ".join(qq[:3]))

    pages = subprocess.run(["pdfinfo", str(PDF)], capture_output=True,
                           text=True).stdout
    m = re.search(r"Pages:\s+(\d+)", pages)
    npages = int(m.group(1)) if m else 0
    check(npages >= 10, "pdf_page_count", f"{npages} pages")

    if strict:
        log = ROOT / "report" / "nebula_report.log"
        if log.is_file():
            over = len(re.findall(r"Overfull \\hbox", log.read_text(errors="ignore")))
            check(over == 0, "no_overfull_boxes", f"{over} overfull")


def check_readme_current() -> None:
    with tempfile.NamedTemporaryFile(suffix=".md", delete=False) as fh:
        tmp = Path(fh.name)
    try:
        proc = subprocess.run([sys.executable,
                               str(ROOT / "scripts" / "build_readme.py"),
                               "--out", str(tmp)],
                              capture_output=True, text=True, cwd=ROOT)
        if proc.returncode != 0:
            check(False, "readme_regenerate", proc.stderr.strip()[-200:])
            return
        # The footer carries the generation time, which differs on every run
        # the same way \reportgenerated does; the numbers above it are what
        # must agree.
        def body(t: str) -> str:
            return t.split("*Generated by")[0]
        same = body(tmp.read_text()) == body((ROOT / "README.md").read_text())
        check(same, "readme_matches_numbers",
              "" if same else "run scripts/build_readme.py")
    finally:
        tmp.unlink(missing_ok=True)


def check_package() -> None:
    """The bundle builds, and nothing key-shaped is in it."""
    sys.path.insert(0, str(ROOT / "scripts"))
    try:
        import package_submission_v2 as pkg
    except Exception as exc:                       # noqa: BLE001
        check(False, "packager_importable", str(exc))
        return
    try:
        files, _notes = pkg.collect()
    except Exception as exc:                       # noqa: BLE001
        check(False, "package_collect", str(exc))
        return
    check(bool(files), "package_collect", f"{len(files)} files")
    try:
        pkg.check_secrets(files)
        check(True, "package_secret_scan")
    except Exception as exc:                       # noqa: BLE001
        check(False, "package_secret_scan", str(exc))


def check_dev_docs_excluded() -> None:
    """Machine-setup notes are for us, not for a reviewer."""
    sys.path.insert(0, str(ROOT / "scripts"))
    import package_submission_v2 as pkg
    files, _ = pkg.collect()
    rel = {str(p.relative_to(ROOT)) for p in files}
    leaked = sorted(rel & {"CLAUDE.md", "CLAUDE_CODE_SETUP.md",
                           "NEW_MACHINE_CLAUDE.md", "LAPTOP_HANDOFF.md"})
    check(not leaked, "dev_docs_excluded", ", ".join(leaked))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict-pdf", action="store_true",
                    help="also fail on overfull boxes in the LaTeX log")
    args = ap.parse_args()

    if not shutil.which("pdftotext"):
        print("NOTE pdftotext not found -- PDF content checks will fail")

    check_required()
    check_numbers_current()
    n = macros() if (GEN / "numbers.tex").is_file() else {}
    if n:
        check_accepts_independently(n)
    check_readme_current()
    check_pdf(args.strict_pdf)
    check_package()
    check_dev_docs_excluded()

    width = max(len(name) for _ok, name, _d in results)
    for ok, name, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name.ljust(width)}  {detail}".rstrip())

    print("\nKey SHA-256:")
    for rel in ["report/nebula_report.pdf", "report/generated/numbers.tex",
                "README.md", "bench/constraints/nebula.sdc"]:
        p = ROOT / rel
        if p.is_file():
            print(f"  {sha256(p)}  {rel}")

    failed = [name for ok, name, _d in results if not ok]
    print("\n" + ("READY" if not failed else "NOT_READY: " + ", ".join(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
