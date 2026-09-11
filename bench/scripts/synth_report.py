#!/usr/bin/env python3
"""Compare two hierarchy-preserving Yosys synthesis netlists.

Both netlists must be produced with the same synthesis recipe and liberty.
The report re-reads them in Yosys and requests hierarchical JSON statistics,
so cell count and area come from the mapped netlists rather than source-text
heuristics. Local module area is reported separately from inclusive top area;
summing inclusive module areas would count descendants many times.

    synth_report.py --golden artifacts/synth_report/golden_named.v \
                    --candidate artifacts/final_candidate/soc_top_named.v \
                    --liberty sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib \
                    --macro-stub macros/macro_blackbox_stubs.v \
                    --out artifacts/synth_report/report
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_YOSYS = REPO_ROOT / "oss-cad-suite" / "bin" / "yosys"


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def stat(netlist, liberty, top, macro_stubs, yosys):
    with tempfile.TemporaryDirectory(prefix="nebula_synth_report_") as tmp:
        out = os.path.join(tmp, "stat.json")
        lines = [f"read_liberty -lib {os.path.abspath(liberty)}"]
        lines += [f"read_verilog -lib {os.path.abspath(p)}" for p in macro_stubs]
        lines += [f"read_verilog {os.path.abspath(netlist)}",
                  f"hierarchy -check -top {top}",
                  f"tee -o {out} stat -top {top} -liberty "
                  f"{os.path.abspath(liberty)} -json -hierarchy"]
        proc = subprocess.run([str(yosys), "-Q", "-p", "; ".join(lines)],
                              cwd=REPO_ROOT, capture_output=True, text=True)
        if proc.returncode:
            raise RuntimeError((proc.stdout + proc.stderr)[-4000:])
        raw = json.load(open(out))

    modules = {}
    for escaped, block in raw["modules"].items():
        name = escaped[1:] if escaped.startswith("\\") else escaped
        modules[name] = {
            "cells_inclusive": int(block["num_cells"]["count"]),
            "area_inclusive_um2": float(block["num_cells"]["area"]),
            "cells_local": int(block["num_cells"]["local_count"]),
            "area_local_um2": float(block["num_cells"]["local_area"]),
            "sequential_area_inclusive_um2":
                float(block["sequential_area"]["area"]),
            "sequential_area_local_um2":
                float(block["sequential_area"]["local_area"]),
        }
    design = raw["design"]
    generic = {k: int(v["count"])
               for k, v in design.get("num_cells_by_type", {}).items()
               if k.startswith("$") and not k.startswith("$paramod$")}
    return {
        "creator": raw.get("creator"),
        "netlist": os.path.abspath(netlist),
        "netlist_sha256": digest(netlist),
        "module_count": len(modules),
        "hierarchy_retained": len(modules) > 1 and top in modules,
        "top": top,
        "cells": int(design["num_cells"]["count"]),
        "area_um2": float(design["num_cells"]["area"]),
        "sequential_area_um2": float(design["sequential_area"]["area"]),
        "unmapped_generic_cells": generic,
        "modules": modules,
    }


def delta(before, after):
    d = after - before
    return {"before": before, "after": after, "delta": d,
            "percent": d / abs(before) * 100.0 if before else None}


def compare(golden, candidate, liberty):
    names = sorted(set(golden["modules"]) | set(candidate["modules"]))
    rows = []
    for name in names:
        g = golden["modules"].get(name)
        c = candidate["modules"].get(name)
        # A newly introduced pipeline module still needs an area row. Treating
        # its absent side as zero exposes its actual cost instead of replacing
        # the only numbers a reviewer wants with the word "added".
        gz = g or {"cells_local": 0, "area_local_um2": 0.0}
        cz = c or {"cells_local": 0, "area_local_um2": 0.0}
        rows.append({
            "module": name,
            "presence": ("both" if g and c else
                         "candidate_only" if c else "golden_only"),
            "cells_local": delta(gz["cells_local"], cz["cells_local"]),
            "area_local_um2": delta(gz["area_local_um2"],
                                    cz["area_local_um2"]),
        })
    blocking = []
    for tag, data in (("golden", golden), ("candidate", candidate)):
        if not data["hierarchy_retained"]:
            blocking.append(f"{tag} hierarchy is not retained")
        if data["unmapped_generic_cells"]:
            blocking.append(f"{tag} contains unmapped generic cells")
    return {
        "verdict": "SYNTHESIS_VALID" if not blocking else "SYNTHESIS_INVALID",
        "blocking_findings": blocking,
        "liberty": os.path.abspath(liberty),
        "liberty_sha256": digest(liberty),
        "golden": golden,
        "candidate": candidate,
        "top_cells": delta(golden["cells"], candidate["cells"]),
        "top_area_um2": delta(golden["area_um2"], candidate["area_um2"]),
        "top_sequential_area_um2":
            delta(golden["sequential_area_um2"],
                  candidate["sequential_area_um2"]),
        "modules": rows,
    }


def fmt(value):
    if isinstance(value, int):
        return f"{value:,}"
    return f"{value:,.2f}"


def markdown(report):
    lines = ["# Synthesis comparison", "",
             f"## {report['verdict']}", "",
             "Both sides were mapped with the same liberty and re-read by "
             "Yosys with hierarchy enabled.", "",
             "| metric | golden | candidate | change |",
             "|---|---:|---:|---:|"]
    for key, label in (("top_cells", "Mapped cells"),
                       ("top_area_um2", "Mapped area (µm²)"),
                       ("top_sequential_area_um2", "Sequential area (µm²)")):
        row = report[key]
        pct = "" if row["percent"] is None else f" ({row['percent']:+.3f}%)"
        lines.append(f"| {label} | {fmt(row['before'])} | {fmt(row['after'])} "
                     f"| {fmt(row['delta'])}{pct} |")
    lines += ["",
              f"Golden hierarchy: **{report['golden']['module_count']} modules**; "
              f"candidate hierarchy: **{report['candidate']['module_count']} modules**.",
              "", "## Local area by module", "",
              "Local figures exclude child instances, so each mapped cell is "
              "counted once across this table.", "",
              "| module | golden cells | candidate cells | Δcells | golden area | candidate area | Δarea |",
              "|---|---:|---:|---:|---:|---:|---:|"]
    for row in report["modules"]:
        cells, area = row["cells_local"], row["area_local_um2"]
        lines.append(
            f"| `{row['module']}` | {fmt(cells['before'])} | {fmt(cells['after'])} "
            f"| {cells['delta']:+,} | {fmt(area['before'])} | {fmt(area['after'])} "
            f"| {area['delta']:+,.2f} |")
    lines += ["", "## Evidence integrity", "",
              f"- Golden netlist SHA-256: `{report['golden']['netlist_sha256']}`",
              f"- Candidate netlist SHA-256: `{report['candidate']['netlist_sha256']}`",
              f"- Liberty SHA-256: `{report['liberty_sha256']}`"]
    if report["blocking_findings"]:
        lines += ["", "## Blocking findings", ""]
        lines += [f"- {x}" for x in report["blocking_findings"]]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--golden", required=True, help="mapped golden netlist")
    ap.add_argument("--candidate", required=True, help="mapped candidate netlist")
    ap.add_argument("--liberty", required=True)
    ap.add_argument("--top", default="soc_top")
    ap.add_argument("--macro-stub", action="append", default=[])
    ap.add_argument("--yosys", default=str(DEFAULT_YOSYS))
    ap.add_argument("--out", default="artifacts/synth_report/report")
    args = ap.parse_args()
    try:
        g = stat(args.golden, args.liberty, args.top, args.macro_stub, args.yosys)
        c = stat(args.candidate, args.liberty, args.top, args.macro_stub, args.yosys)
        report = compare(g, c, args.liberty)
    except (OSError, KeyError, ValueError, RuntimeError,
            json.JSONDecodeError) as exc:
        print(f"synthesis report error: {exc}", file=sys.stderr)
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
    return 0 if report["verdict"] == "SYNTHESIS_VALID" else 1


if __name__ == "__main__":
    sys.exit(main())
