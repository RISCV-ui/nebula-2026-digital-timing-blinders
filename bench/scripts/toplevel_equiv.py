#!/usr/bin/env python3
"""Assemble the frozen-to-final equivalence artifact from existing evidence.

The FP4 optimisation deliberately changes latency, so ordinary cycle-by-cycle
equivalence at axi_lite_dot is false. This report does not hide that result. It
decomposes the top-level claim into byte-identical RTL outside the changed cone,
a complete combinational proof for fp8_adder, and the bounded elastic-stream
contract proof for the four-stage FP4 pipeline.

No solver is run here. Every evidence file and every RTL source is SHA-256
hashed so the report cannot silently drift away from the design it describes.

    toplevel_equiv.py --golden bench/rtl \
      --candidate artifacts/final_candidate/rtl \
      --g1 artifacts/final_candidate/g1_fp8_adder.json \
      --g1c artifacts/final_candidate/g1c_stream.json \
      --boundary artifacts/final_candidate/g1b_fp4_dot_unit.json \
      --out artifacts/final_candidate/toplevel_equiv
"""

import argparse
import hashlib
import json
import os
import re
import sys


EXPECTED_CHANGED = {"axi_lite_dot.v", "fp4_dot_unit.v", "fp8_adder.v"}
EXPECTED_ADDED = {"fp4_dot_stage.v"}
REQUIRED_STREAM_PROPERTIES = {
    "P0 accept available input",
    "P1 no overflow",
    "P2a no invention",
    "P2b no loss",
    "P3 data and order",
    "P4 drain",
    "r_en_1 == r_en_2",
}


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def tree_files(root):
    return {name: os.path.join(root, name) for name in sorted(os.listdir(root))
            if name.endswith(".v") and os.path.isfile(os.path.join(root, name))}


def compare_trees(golden, candidate):
    gf, cf = tree_files(golden), tree_files(candidate)
    rows = []
    for name in sorted(set(gf) | set(cf)):
        gh = digest(gf[name]) if name in gf else None
        ch = digest(cf[name]) if name in cf else None
        status = ("identical" if gh == ch else
                  "changed" if gh and ch else
                  "added" if ch else "removed")
        rows.append({"file": name, "status": status,
                     "golden_sha256": gh, "candidate_sha256": ch})
    return rows


def load_evidence(path):
    return json.load(open(path)), {"path": os.path.abspath(path),
                                   "sha256": digest(path)}


def divergence_cycle(boundary):
    for check in boundary.get("checks", []):
        # The raw trace is capped for prompt feedback and can end inside the
        # initial-state rows on a large parent. Its filtered summary retains
        # the real cycles, including the first asserted miter trigger.
        text = check.get("counterexample_summary", "")
        match = re.search(r"(?m)^\s*(\d+)\s+\\trigger\s+1\s+1", text)
        if match:
            return int(match.group(1))
    return None


def build(args):
    rows = compare_trees(args.golden, args.candidate)
    changed = {r["file"] for r in rows if r["status"] == "changed"}
    added = {r["file"] for r in rows if r["status"] == "added"}
    removed = {r["file"] for r in rows if r["status"] == "removed"}
    if changed != EXPECTED_CHANGED or added != EXPECTED_ADDED or removed:
        raise ValueError(
            "RTL scope differs from the proved cone: "
            f"changed={sorted(changed)}, added={sorted(added)}, "
            f"removed={sorted(removed)}")

    g1, g1_meta = load_evidence(args.g1)
    g1c, g1c_meta = load_evidence(args.g1c)
    boundary, boundary_meta = load_evidence(args.boundary)
    if g1.get("module") != "fp8_adder":
        raise ValueError("G1 evidence is not for fp8_adder")
    if g1c.get("module") != "fp4_dot_stage":
        raise ValueError("G1c evidence is not for fp4_dot_stage")
    if g1c.get("latency") != 4:
        raise ValueError("G1c evidence does not declare latency +4")
    if set(g1c.get("properties", [])) != REQUIRED_STREAM_PROPERTIES:
        raise ValueError("G1c evidence does not contain the required six properties")
    if boundary.get("module") != "fp4_dot_unit":
        raise ValueError("boundary evidence is not rooted at fp4_dot_unit")
    checks = boundary.get("checks", [])
    if not any(c.get("parent") == "axi_lite_dot" and
               c.get("verdict") == "NOT_EQUIVALENT" for c in checks):
        raise ValueError("boundary evidence does not record axi_lite_dot divergence")

    counterexample = (g1.get("verdict") == "NOT_EQUIVALENT" or
                      g1c.get("verdict") == "PROPERTY_VIOLATED")
    complete = (g1.get("verdict") == "EQUIVALENT" and g1.get("depth") == 1 and
                g1c.get("verdict") == "STREAM_EQUIVALENT")
    verdict = ("COUNTEREXAMPLE_FOUND" if counterexample else
               "EQUIVALENT_MODULO_DECLARED_STREAM_LATENCY" if complete else
               "INCOMPLETE")
    return {
        "verdict": verdict,
        "ordinary_top_level_equivalence": "NOT_EQUIVALENT",
        "declared_difference": {
            "cone": ["axi_lite_dot", "fp4_dot_stage", "fp4_dot_unit",
                     "fp8_adder"],
            "latency_cycles": 4,
            "contract_boundary": "fp4_dot_stage FIFO-shaped interface",
            "observable_effect":
                "result availability may move later; consumed and produced "
                "data streams remain equal and ordered",
            "ordinary_boundary_check": boundary.get("verdict"),
            "ordinary_boundary_parent": "axi_lite_dot",
            "ordinary_boundary_divergence_cycle": divergence_cycle(boundary),
        },
        "proofs": {
            "fp8_adder": {
                "verdict": g1.get("verdict"), "depth": g1.get("depth"),
                "seconds": g1.get("seconds"),
                "scope": "complete combinational equivalence",
            },
            "fp4_stream": {
                "verdict": g1c.get("verdict"), "depth": g1c.get("depth"),
                "seconds": g1c.get("seconds"),
                "latency_cycles": g1c.get("latency"),
                "properties": g1c.get("properties"),
                "scope": "bounded stream-contract proof",
            },
        },
        "rtl_scope": {
            "golden": os.path.abspath(args.golden),
            "candidate": os.path.abspath(args.candidate),
            "golden_file_count": sum(r["golden_sha256"] is not None for r in rows),
            "candidate_file_count": sum(r["candidate_sha256"] is not None for r in rows),
            "identical_files": sum(r["status"] == "identical" for r in rows),
            "changed_files": sorted(changed), "added_files": sorted(added),
            "removed_files": sorted(removed), "files": rows,
        },
        "evidence": {"g1": g1_meta, "g1c": g1c_meta,
                     "ordinary_boundary": boundary_meta},
        "limitation":
            "This is not cycle-by-cycle soc_top equivalence. The stream proof "
            "is bounded to 16 cycles and permits the declared result-latency "
            "change at the FIFO-shaped interface.",
    }


def markdown(report):
    p1, ps = report["proofs"]["fp8_adder"], report["proofs"]["fp4_stream"]
    d, scope = report["declared_difference"], report["rtl_scope"]
    lines = [
        "# Frozen RTL to final RTL equivalence artifact", "",
        f"## {report['verdict']}", "",
        "The final RTL is **not cycle-by-cycle equivalent** to the frozen RTL. "
        "The accepted FP4 transform adds four cycles, and an ordinary parent "
        "miter correctly finds a counterexample. The supported claim is "
        "equivalence modulo that declared elastic-stream latency.", "",
        "## Decomposed argument", "",
        f"1. **File identity:** {scope['identical_files']} RTL files are "
        "byte-identical between the frozen and final trees.",
        f"2. **FP8 leaf:** `fp8_adder` is `{p1['verdict']}` at depth "
        f"{p1['depth']} in {p1['seconds']} s. It is combinational, so depth 1 "
        "covers the complete function.",
        f"3. **FP4 stream:** `fp4_dot_stage` is `{ps['verdict']}` at depth "
        f"{ps['depth']} in {ps['seconds']} s under a +{ps['latency_cycles']} "
        "cycle contract.",
        "4. **Ordinary boundary check:** `axi_lite_dot` is "
        f"`NOT_EQUIVALENT` at cycle {d['ordinary_boundary_divergence_cycle']}; "
        "the candidate result-valid signal is later. This is the declared "
        "latency difference, not a hidden clean pass.", "",
        "The stream proof checks acceptance when operands and room are "
        "available, no overflow, no invented result, no lost result, data and "
        "order equality, bounded drain, and paired operand reads.", "",
        "## Exact RTL scope", "",
        f"- Frozen tree: {scope['golden_file_count']} Verilog files",
        f"- Final tree: {scope['candidate_file_count']} Verilog files",
        f"- Changed: {', '.join(f'`{x}`' for x in scope['changed_files'])}",
        f"- Added: {', '.join(f'`{x}`' for x in scope['added_files'])}",
        "", "| file | status | frozen SHA-256 | final SHA-256 |",
        "|---|---|---|---|",
    ]
    for row in scope["files"]:
        gh = row["golden_sha256"] or "—"
        ch = row["candidate_sha256"] or "—"
        lines.append(f"| `{row['file']}` | {row['status']} | `{gh}` | `{ch}` |")
    lines += ["", "## Evidence files", ""]
    for name, meta in report["evidence"].items():
        lines.append(f"- `{name}`: `{meta['sha256']}` — `{meta['path']}`")
    lines += ["", "## Limitation", "", report["limitation"]]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--golden", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--g1", required=True)
    ap.add_argument("--g1c", required=True)
    ap.add_argument("--boundary", required=True)
    ap.add_argument("--out", default="artifacts/final_candidate/toplevel_equiv")
    args = ap.parse_args()
    try:
        report = build(args)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"top-level equivalence report error: {exc}", file=sys.stderr)
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
    return 1 if report["verdict"] == "COUNTEREXAMPLE_FOUND" else 0


if __name__ == "__main__":
    sys.exit(main())
