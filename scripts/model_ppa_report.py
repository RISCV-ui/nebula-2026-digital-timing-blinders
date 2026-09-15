#!/usr/bin/env python3
"""Build an honest per-model synthesis and routed-PPA comparison."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from pathlib import Path


MODEL_INFO = {
    "nemotron_ultra": ("Nemotron Ultra 550B", "openrouter:nemotron-ultra"),
    "nemotron_super": ("Nemotron Super 120B", "openrouter:nemotron"),
    "nemotron_nano": ("Nemotron Nano 30B", "openrouter:nemotron-nano"),
    "gemini_flash": ("Gemini 3.5 Flash", "gemini:gemini-flash"),
    "gemma_free": ("Gemma 4 31B free", "openrouter:gemma-free"),
    "gemini_pro": ("Gemini 3.1 Pro", "gemini:gemini-pro"),
}


def read_json(path: Path):
    return json.loads(path.read_text())


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_metric_args(items: list[str]) -> dict[str, Path]:
    result = {}
    for item in items:
        if "=" not in item:
            raise ValueError(f"metric input must be NAME=PATH: {item}")
        name, raw_path = item.split("=", 1)
        if name in result:
            raise ValueError(f"duplicate metric input for {name}")
        result[name] = Path(raw_path)
    return result


def synth_values(report: dict, side: str) -> dict:
    design = report[side]
    return {
        "cells": design["cells"],
        "area_um2": design["area_um2"],
        "sequential_area_um2": design["sequential_area_um2"],
    }


def route_values(metrics: dict) -> dict:
    return {
        "area_um2": metrics.get("area_um2"),
        "instances": metrics.get("instances"),
        "nets": metrics.get("nets"),
        "setup_wns_ns": metrics.get("wns"),
        "setup_tns_ns": metrics.get("tns"),
        "hold_wns_ns": metrics.get("wns_hold"),
        "hold_tns_ns": metrics.get("tns_hold"),
        "drc_violations": metrics.get("drc_violations"),
    }


def pct(after, before):
    if after is None or before in (None, 0):
        return None
    return 100.0 * (after - before) / abs(before)


def delta_values(values: dict | None, baseline: dict, smaller: set[str]) -> dict | None:
    if values is None:
        return None
    result = {}
    for key, after in values.items():
        before = baseline.get(key)
        delta = None if before is None or after is None else after - before
        result[key] = {
            "value": after,
            "baseline": before,
            "delta": delta,
            "percent": pct(after, before),
            "direction": (
                "not_reported" if delta is None else
                "same" if delta == 0 else
                "better" if ((delta < 0) == (key in smaller)) else
                "worse"
            ),
        }
    return result


def markdown(report: dict) -> str:
    lines = [
        "# Per-model PPA comparison",
        "",
        "Models used the same frozen RTL, targets, retry budget and gate chain. "
        "A routed result is inherited from baseline only when the reconstructed "
        "model RTL is byte-identical to baseline.",
        "",
        "| model | status | accepted RTL | mapped area (um²) | routed area (um²) | instances | setup WNS (ns) | PPA evidence |",
        "|---|---|---|---:|---:|---:|---:|---|",
    ]
    for row in report["rows"]:
        synth = row.get("synthesis")
        route = row.get("routed")
        changed = ", ".join(row["accepted_files"]) or "none"
        lines.append(
            f"| {row['label']} | {row['status']} | {changed} | "
            f"{synth['area_um2']:,.4f} | " if synth else
            f"| {row['label']} | {row['status']} | {changed} | N/A | "
        )
        suffix = (
            f"{route['area_um2']:,.0f} | {route['instances']:,} | "
            f"{route['setup_wns_ns']:+.4f} | {row['ppa_evidence']} |"
            if route else f"N/A | N/A | N/A | {row['ppa_evidence']} |"
        )
        lines[-1] += suffix

    lines += [
        "",
        "## Interpretation",
        "",
        "- Untested HTTP 429/quota arms remain N/A; absence of a proposal is not a model failure.",
        "- Zero-accept tested arms equal baseline because their reconstructed RTL hashes are identical.",
        "- Synthesis and routed values are separate implementation stages and must not be compared directly.",
        "- The combined final design is reported separately from single-model rankings when supplied.",
        "",
    ]
    if report["blocking_findings"]:
        lines += ["## Incomplete evidence", ""]
        lines += [f"- {item}" for item in report["blocking_findings"]]
        lines.append("")
    return "\n".join(lines)


def write_csv(path: Path, rows: list[dict]):
    fields = [
        "variant", "model", "status", "accepted_files", "synth_cells",
        "synth_area_um2", "routed_area_um2", "routed_instances", "routed_nets",
        "setup_wns_ns", "setup_tns_ns", "hold_wns_ns", "hold_tns_ns",
        "drc_violations", "ppa_evidence",
    ]
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            synth, route = row.get("synthesis") or {}, row.get("routed") or {}
            writer.writerow({
                "variant": row["variant"],
                "model": row["label"],
                "status": row["status"],
                "accepted_files": ";".join(row["accepted_files"]),
                "synth_cells": synth.get("cells"),
                "synth_area_um2": synth.get("area_um2"),
                "routed_area_um2": route.get("area_um2"),
                "routed_instances": route.get("instances"),
                "routed_nets": route.get("nets"),
                "setup_wns_ns": route.get("setup_wns_ns"),
                "setup_tns_ns": route.get("setup_tns_ns"),
                "hold_wns_ns": route.get("hold_wns_ns"),
                "hold_tns_ns": route.get("hold_tns_ns"),
                "drc_violations": route.get("drc_violations"),
                "ppa_evidence": row["ppa_evidence"],
            })


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--bakeoff", required=True)
    parser.add_argument("--baseline-metrics", required=True)
    parser.add_argument("--synth-root", required=True)
    parser.add_argument(
        "--metrics", action="append", default=[], metavar="NAME=PATH",
        help="routed metrics for a changed model variant or combined_final",
    )
    parser.add_argument("--out", required=True, help="output stem")
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    bakeoff_path = Path(args.bakeoff)
    baseline_metrics_path = Path(args.baseline_metrics)
    synth_root = Path(args.synth_root)
    out = Path(args.out)
    metric_paths = parse_metric_args(args.metrics)

    manifest = read_json(manifest_path)
    arms = {row["arm"]: row for row in read_json(bakeoff_path)["arms"]}
    variants = {row["name"]: row for row in manifest["variants"]}
    baseline_variant = variants["baseline"]
    baseline_metrics = route_values(read_json(baseline_metrics_path))

    # A zero-edit arm may reuse baseline PPA only after proving the whole RTL
    # tree is identical; otherwise a convenient assumption becomes fake data.
    baseline_hashes = baseline_variant["rtl_sha256"]
    rows = []
    findings = []
    source_paths = [manifest_path, bakeoff_path, baseline_metrics_path]

    changed_synth_reports = {}
    for name in ("nemotron_ultra", "gemini_flash", "combined_final"):
        path = synth_root / name / "report.json"
        if path.exists():
            changed_synth_reports[name] = read_json(path)
            source_paths.append(path)
    if not changed_synth_reports:
        sys.exit("no synthesis reports found")
    exemplar = next(iter(changed_synth_reports.values()))
    baseline_synth = synth_values(exemplar, "golden")

    baseline_row = {
        "variant": "baseline",
        "label": "Frozen baseline",
        "status": "BASELINE",
        "accepted_files": [],
        "synthesis": baseline_synth,
        "routed": baseline_metrics,
        "ppa_evidence": "measured baseline signoff",
    }
    baseline_row["synthesis_delta"] = delta_values(
        baseline_synth, baseline_synth, {"cells", "area_um2", "sequential_area_um2"}
    )
    baseline_row["routed_delta"] = delta_values(
        baseline_metrics, baseline_metrics,
        {"area_um2", "instances", "nets", "setup_tns_ns", "hold_tns_ns", "drc_violations"},
    )
    rows.append(baseline_row)

    for name, (label, arm_name) in MODEL_INFO.items():
        variant = variants[name]
        arm = arms[arm_name]
        tested = arm["tested"]
        identical = variant["rtl_sha256"] == baseline_hashes
        synth = None
        routed = None
        evidence = "N/A: proposal never reached a gate"

        if tested and identical:
            synth = baseline_synth
            routed = baseline_metrics
            evidence = "baseline inherited by byte-identical RTL"
        elif tested:
            synth_report = changed_synth_reports.get(name)
            if synth_report:
                synth = synth_values(synth_report, "candidate")
            else:
                findings.append(f"{label}: mapped synthesis report missing")
            metric_path = metric_paths.get(name)
            if metric_path and metric_path.exists():
                routed = route_values(read_json(metric_path))
                source_paths.append(metric_path)
                evidence = "measured individual-model signoff"
            else:
                evidence = "PENDING: individual-model routed signoff"
                findings.append(f"{label}: routed metrics missing")

        row = {
            "variant": name,
            "label": label,
            "model_id": arm["model_id"],
            "status": variant["status"],
            "accepted_files": variant["accepted_files"],
            "rtl_identical_to_baseline": identical,
            "proposals": arm["proposals"],
            "accepted": arm["accepted"],
            "synthesis": synth,
            "routed": routed,
            "ppa_evidence": evidence,
        }
        row["synthesis_delta"] = delta_values(
            synth, baseline_synth, {"cells", "area_um2", "sequential_area_um2"}
        )
        row["routed_delta"] = delta_values(
            routed, baseline_metrics,
            {"area_um2", "instances", "nets", "setup_tns_ns", "hold_tns_ns", "drc_violations"},
        )
        rows.append(row)

    if "combined_final" in metric_paths:
        metric_path = metric_paths["combined_final"]
        final_route = route_values(read_json(metric_path))
        final_synth = synth_values(changed_synth_reports["combined_final"], "candidate")
        source_paths.append(metric_path)
        rows.append({
            "variant": "combined_final",
            "label": "Combined final (multi-model)",
            "status": "FINAL_COMBINED",
            "accepted_files": variants["combined_final"]["accepted_files"],
            "synthesis": final_synth,
            "routed": final_route,
            "synthesis_delta": delta_values(
                final_synth, baseline_synth, {"cells", "area_um2", "sequential_area_um2"}
            ),
            "routed_delta": delta_values(
                final_route, baseline_metrics,
                {"area_um2", "instances", "nets", "setup_tns_ns", "hold_tns_ns", "drc_violations"},
            ),
            "ppa_evidence": "measured timing-closed final; excluded from single-model ranking",
        })

    report = {
        "verdict": "COMPLETE" if not findings else "INCOMPLETE",
        "blocking_findings": findings,
        "rows": rows,
        "provenance_sha256": {str(path): digest(path) for path in dict.fromkeys(source_paths)},
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n")
    out.with_suffix(".md").write_text(markdown(report))
    write_csv(out.with_suffix(".csv"), rows)
    print(f"{report['verdict']}: {len(rows)} rows; {len(findings)} missing evidence item(s)")
    if args.require_complete and findings:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
