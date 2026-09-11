#!/usr/bin/env python3
"""Build the clean EQY deliverable from an existing hierarchical sweep.

The sweep is expensive evidence, so this script never invokes EQY or Yosys.
It validates the saved JSON against its own totals and, when supplied, against
the final summary in the captured log. It then emits machine-readable JSON and
reviewable Markdown from that evidence.

An incomplete proof is not a counterexample. The report therefore separates
PROVED_EQUIVALENT, TIMEOUT, UNPROVEN and tool errors, and exits non-zero only
when a final module verdict is NOT_EQUIVALENT. Intermediate partition claims
are preserved as diagnostics because merged equivalence has already disproved
some of them; promoting those claims would turn a checker limitation into a
false design failure.

    eqy_report.py --input artifacts/eqy/soc_top_hier4.json \
                  --log artifacts/eqy/hier4.log \
                  --out artifacts/eqy/report
"""

import argparse
import hashlib
import json
import os
import re
import sys
from collections import Counter


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def category(result):
    status = result.get("status", "")
    if result.get("equivalent") is True and status == "PROVED_EQUIVALENT":
        return "proved"
    if status == "NOT_EQUIVALENT":
        return "not_equivalent"
    if status.startswith("TIMEOUT"):
        return "timeout"
    if status.startswith("UNPROVEN"):
        return "unproven"
    if status.startswith(("EQY_ERROR", "YOSYS_ERROR", "ERROR")):
        return "tool_error"
    return "other"


def validate(source, log_path=None):
    results = source.get("results")
    if not isinstance(results, list) or not results:
        raise ValueError("input has no non-empty results list")
    names = [r.get("module") for r in results]
    if any(not n for n in names) or len(names) != len(set(names)):
        raise ValueError("every result needs one unique module name")

    checked = len(results)
    proved = sum(category(r) == "proved" for r in results)
    if source.get("modules_checked") != checked:
        raise ValueError(
            f"modules_checked says {source.get('modules_checked')}, results has {checked}")
    if source.get("modules_equivalent") != proved:
        raise ValueError(
            f"modules_equivalent says {source.get('modules_equivalent')}, "
            f"results proves {proved}")

    if log_path:
        text = open(log_path).read()
        matches = re.findall(
            r"(?m)^(\d+)/(\d+) proved equivalent in [0-9.]+s\s*->", text)
        if not matches:
            raise ValueError("log has no final '<proved>/<checked> proved' summary")
        lp, lc = map(int, matches[-1])
        if (lp, lc) != (proved, checked):
            raise ValueError(
                f"log summary is {lp}/{lc}, JSON results are {proved}/{checked}")
    return results


def make_report(source_path, log_path=None):
    source = json.load(open(source_path))
    results = validate(source, log_path)
    rows = []
    for result in results:
        rows.append({
            "module": result["module"],
            "category": category(result),
            "status": result.get("status"),
            "seconds": result.get("seconds"),
            "proved_child_cut_points": result.get("cut_points", []),
            "intermediate_counterexample_claims":
                result.get("counterexample_claimed_by", []),
        })

    counts = Counter(r["category"] for r in rows)
    for key in ("proved", "timeout", "unproven", "tool_error",
                "not_equivalent", "other"):
        counts.setdefault(key, 0)
    return {
        "verdict": ("COUNTEREXAMPLE_FOUND" if counts["not_equivalent"]
                    else "NO_COUNTEREXAMPLES"),
        "headline": (f"{counts['proved']}/{len(rows)} proved, "
                     f"{counts['not_equivalent']} counterexample"
                     f"{'s' if counts['not_equivalent'] != 1 else ''}"),
        "counts": dict(counts),
        "modules_checked": len(rows),
        "total_seconds": source.get("total_seconds"),
        "method": source.get("method"),
        "evidence": {
            "json": os.path.abspath(source_path),
            "json_sha256": digest(source_path),
            "log": os.path.abspath(log_path) if log_path else None,
            "log_sha256": digest(log_path) if log_path else None,
        },
        "results": rows,
    }


def markdown(report):
    c = report["counts"]
    unresolved = [r for r in report["results"] if r["category"] != "proved"]
    claims = [r for r in report["results"]
              if r["intermediate_counterexample_claims"]]
    lines = [
        "# EQY hierarchical equivalence report",
        "",
        f"## {report['headline']}",
        "",
        f"- **PROVED_EQUIVALENT:** {c['proved']}",
        f"- **TIMEOUT:** {c['timeout']}",
        f"- **UNPROVEN:** {c['unproven']}",
        f"- **tool error:** {c['tool_error']}",
        f"- **NOT_EQUIVALENT:** {c['not_equivalent']}",
        f"- **sweep runtime:** {report['total_seconds']} s",
        "",
        "`TIMEOUT`, `UNPROVEN`, and tool errors are incomplete checks. They are "
        "not proofs and they are not counterexamples.",
        "",
        "## Why incomplete parents cost more",
        "",
        "The sweep is compositional. A child is boxed identically on the RTL "
        "and netlist sides only after that child has proved equivalent. If a "
        "child is unproven, it is deliberately left expanded in every parent, "
        "so the parent solver must carry that child's state and logic. This "
        "preserves soundness at the cost of runtime and is why incomplete leaf "
        "proofs can propagate upward as parent timeouts.",
        "",
        "## Modules without a proof",
        "",
        "| module | result | seconds | proved children boxed |",
        "|---|---|---:|---|",
    ]
    for row in unresolved:
        cuts = ", ".join(f"`{x}`" for x in row["proved_child_cut_points"]) or "none"
        lines.append(
            f"| `{row['module']}` | {row['status']} | {row['seconds']} | {cuts} |")

    lines += [
        "",
        "## Intermediate counterexample diagnostics",
        "",
        "Partitioned passes can report a counterexample that the merged pass "
        "does not reproduce. These signals are retained for debugging but are "
        "never promoted to a final `NOT_EQUIVALENT` verdict.",
        "",
    ]
    if claims:
        lines += ["| module | claiming pass(es) | final result |",
                  "|---|---|---|"]
        for row in claims:
            who = ", ".join(f"`{x}`" for x in
                            row["intermediate_counterexample_claims"])
            lines.append(f"| `{row['module']}` | {who} | {row['status']} |")
    else:
        lines.append("None.")

    lines += [
        "",
        "## Evidence integrity",
        "",
        f"- JSON SHA-256: `{report['evidence']['json_sha256']}`",
    ]
    if report["evidence"]["log_sha256"]:
        lines.append(f"- log SHA-256: `{report['evidence']['log_sha256']}`")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="existing EQY sweep JSON")
    ap.add_argument("--log", help="captured sweep log to cross-check")
    ap.add_argument("--out", default="artifacts/eqy/report",
                    help="output basename; .md and .json are added")
    args = ap.parse_args()

    try:
        report = make_report(args.input, args.log)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"EQY report error: {exc}", file=sys.stderr)
        return 2

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out + ".json", "w") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")
    md = markdown(report)
    with open(args.out + ".md", "w") as fh:
        fh.write(md + "\n")
    print(md)
    print(f"\nwrote {args.out}.md and {args.out}.json")
    return 1 if report["counts"]["not_equivalent"] else 0


if __name__ == "__main__":
    sys.exit(main())
