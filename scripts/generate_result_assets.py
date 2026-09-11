#!/usr/bin/env python3
"""Generate report-ready figures and tables from signed-off JSON evidence."""

from __future__ import annotations

import csv
import hashlib
import html
import json
import math
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "result_assets"
FIG = OUT / "figures"
DATA = OUT / "data"
W, H = 1600, 900

NAVY = "#12263A"
BLUE = "#2563EB"
CYAN = "#0891B2"
GREEN = "#059669"
ORANGE = "#D97706"
RED = "#DC2626"
PURPLE = "#7C3AED"
SLATE = "#64748B"
LIGHT = "#F5F7FB"
GRID = "#D9E1EA"
INK = "#172033"
MUTED = "#5B6678"
WHITE = "#FFFFFF"


def esc(value: object) -> str:
    return html.escape(str(value))


class Canvas:
    def __init__(self, title: str, subtitle: str, source: str):
        self.parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
            f'<rect width="{W}" height="{H}" fill="{LIGHT}"/>',
            f'<rect width="{W}" height="16" fill="{BLUE}"/>',
        ]
        self.text(64, 76, title, 36, NAVY, "700")
        self.text(64, 116, subtitle, 19, MUTED)
        self.text(64, 868, source, 14, MUTED)
        self.text(1536, 868, "Timing Blinders | Nebula 2026 Digital", 14, MUTED, anchor="end")

    def text(self, x, y, value, size=18, fill=INK, weight="400", anchor="start"):
        self.parts.append(
            f'<text x="{x}" y="{y}" font-family="Arial,Helvetica,sans-serif" '
            f'font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}">{esc(value)}</text>'
        )

    def multiline(self, x, y, lines, size=18, fill=INK, weight="400", gap=1.25, anchor="start"):
        for idx, line in enumerate(lines):
            self.text(x, y + idx * size * gap, line, size, fill, weight, anchor)

    def rect(self, x, y, w, h, fill=WHITE, stroke=GRID, radius=14, sw=1.5):
        self.parts.append(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'
        )

    def line(self, x1, y1, x2, y2, stroke=GRID, sw=2, dash=None):
        extra = f' stroke-dasharray="{dash}"' if dash else ""
        self.parts.append(
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}"{extra}/>'
        )

    def circle(self, cx, cy, r, fill=WHITE, stroke=GRID, sw=2):
        self.parts.append(
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'
        )

    def arrow(self, x1, y1, x2, y2, stroke=SLATE, sw=3):
        self.line(x1, y1, x2, y2, stroke, sw)
        angle = math.atan2(y2 - y1, x2 - x1)
        pts = []
        for delta in (2.55, -2.55):
            pts.append((x2 + 13 * math.cos(angle + delta), y2 + 13 * math.sin(angle + delta)))
        self.parts.append(
            f'<polygon points="{x2},{y2} {pts[0][0]},{pts[0][1]} {pts[1][0]},{pts[1][1]}" fill="{stroke}"/>'
        )

    def save(self, stem: str):
        self.parts.append("</svg>")
        svg = FIG / f"{stem}.svg"
        png = FIG / f"{stem}.png"
        svg.write_text("\n".join(self.parts))
        subprocess.run(
            ["rsvg-convert", "-w", str(W), "-h", str(H), "-o", str(png), str(svg)],
            check=True,
        )


def load(rel: str):
    return json.loads((ROOT / rel).read_text())


def write_csv(name: str, rows: list[dict]):
    if not rows:
        return
    with (DATA / name).open("w", newline="") as handle:
        # Unix line endings keep generated evidence readable in Git diffs.
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def card(c: Canvas, x, y, w, h, label, value, note, color=BLUE):
    c.rect(x, y, w, h, WHITE, GRID, 18)
    c.rect(x, y, 9, h, color, color, 4, 0)
    c.text(x + 28, y + 40, label, 17, MUTED, "700")
    c.text(x + 28, y + 95, value, 35, color, "700")
    c.text(x + 28, y + 130, note, 15, MUTED)


def flow_figure():
    c = Canvas(
        "Proof-gated GenAI RTL optimization loop",
        "LLM proposes; deterministic tools decide whether an edit survives.",
        "Source: bench/scripts/loop.py and verified gate artifacts",
    )
    labels = [
        ("Signoff STA", "Rank real paths"),
        ("RTL slicer", "Path -> module + lines"),
        ("LLM proposal", "One bounded transform"),
        ("Validate", "Syntax + structure"),
        ("Formal gates", "G1 / G1c / CDC / clocks"),
        ("Accept", "Write candidate tree"),
    ]
    colors = [CYAN, BLUE, PURPLE, ORANGE, RED, GREEN]
    xs = [45, 300, 555, 810, 1065, 1320]
    for idx, ((title, note), color, x) in enumerate(zip(labels, colors, xs)):
        c.rect(x, 250, 205, 135, WHITE, color, 18, 3)
        c.text(x + 102, 300, title, 22, color, "700", "middle")
        c.text(x + 102, 338, note, 15, MUTED, anchor="middle")
        if idx < len(xs) - 1:
            c.arrow(x + 205, 318, xs[idx + 1] - 12, 318, SLATE, 3)
    c.rect(560, 520, 480, 140, "#EEF6FF", BLUE, 18, 3)
    c.text(800, 570, "Final combined candidate", 25, NAVY, "700", "middle")
    c.text(800, 610, "One full OpenROAD PnR + parasitic signoff", 18, MUTED, anchor="middle")
    c.arrow(1422, 385, 1030, 520, GREEN, 3)
    c.rect(1050, 705, 440, 86, "#FFF1F2", RED, 16, 2)
    c.text(1270, 741, "Reject + preserve counterexample", 20, RED, "700", "middle")
    c.text(1270, 770, "Retry is capped; frozen RTL is never edited", 15, MUTED, anchor="middle")
    c.arrow(1165, 385, 1220, 705, RED, 2)
    c.arrow(1050, 748, 658, 385, RED, 2)
    c.text(800, 185, "Cheap checks first", 18, GREEN, "700", "middle")
    c.text(800, 215, "milliseconds -> formal seconds/minutes -> one final PnR", 16, MUTED, anchor="middle")
    c.save("01_proof_gated_flow")


def dashboard(ppa, eqy, top):
    metrics = ppa["ppa"]
    s5 = next(row for row in ppa["clocks"] if row["clock"] == "clk_s5")
    unresolved = eqy["modules_checked"] - eqy["counts"]["proved"]
    latency = top["declared_difference"]["latency_cycles"]
    stream_depth = top["proofs"]["fp4_stream"]["depth"]
    c = Canvas(
        "Verified result dashboard",
        "Parasitic-aware final signoff; optimistic ideal-clock numbers are excluded.",
        "Sources: ppa.json, fmax signoff JSON, EQY report, top-level contract",
    )
    cards = [
        ("clk_s5 Fmax", f'{s5["fmax_before"]:.2f} -> {s5["fmax_after"]:.2f} MHz', f'{s5["fmax_after"] / s5["fmax_before"]:.2f}x measured period sweep', GREEN),
        ("Setup WNS", f'{metrics["wns"]["before"]:.4f} -> {metrics["wns"]["after"]:.4f} ns', f'{metrics["wns"]["abs"]:+.3f} ns', GREEN),
        ("Setup TNS", f'{metrics["tns"]["before"]:.4f} -> {metrics["tns"]["after"]:.4f} ns', f'{metrics["tns"]["abs"]:+.4f} ns', GREEN),
        ("Routed area", f'{metrics["area_um2"]["pct"]:.3f}%', f'{metrics["area_um2"]["before"]:,.0f} -> {metrics["area_um2"]["after"]:,.0f} um2', GREEN),
        ("Formal sweep", f'{eqy["counts"]["proved"]}/{eqy["modules_checked"]} proved', f'{eqy["counts"]["not_equivalent"]} counterexamples; {unresolved} unresolved', BLUE),
        ("Top contract", f'+{latency} cycles', f'stream data/order proved at depth {stream_depth}', PURPLE),
    ]
    for i, values in enumerate(cards):
        x = 64 + (i % 3) * 500
        y = 175 + (i // 3) * 245
        card(c, x, y, 455, 185, *values)
    c.rect(64, 700, 1455, 85, "#FFF7ED", ORANGE, 14, 2)
    c.text(90, 737, "Honest limits", 19, ORANGE, "700")
    c.text(245, 737, "clk1 and clk_s8 retain small violations; clk2-clk5 have no timing paths; 18 EQY modules unresolved.", 17, INK)
    c.text(245, 767, "Ordinary cycle-by-cycle top equivalence is NOT claimed because accepted pipeline adds four cycles.", 17, INK)
    c.save("02_verified_dashboard")


def model_outcomes(arms):
    tested = [a for a in arms if a["tested"]]
    tested.sort(key=lambda a: (-a["accepted"], -a["proposals"], a["arm"]))
    labels = {
        "openrouter:nemotron-ultra": "Nemotron Ultra 550B",
        "gemini:gemini-flash": "Gemini 3.5 Flash",
        "openrouter:nemotron": "Nemotron Super 120B",
        "openrouter:nemotron-nano": "Nemotron Nano 30B",
    }
    stage_order = ["propose", "validate", "audit", "g1", "accepted"]
    stage_colors = {"propose": PURPLE, "validate": ORANGE, "audit": SLATE, "g1": RED, "accepted": GREEN}
    c = Canvas(
        "Same-task model outcomes",
        "Same paths, retry budget and formal gates. Only tested arms receive rates.",
        "Source: artifacts/bakeoff_all_20260911/bakeoff_all.json",
    )
    for i, stage in enumerate(stage_order):
        x = 530 + i * 180
        c.rect(x, 155, 20, 20, stage_colors[stage], stage_colors[stage], 3, 0)
        c.text(x + 28, 172, stage.upper(), 15, MUTED, "700")
    max_n = max(a["proposals"] for a in tested)
    for row, arm in enumerate(tested):
        y = 245 + row * 130
        c.text(70, y + 35, labels[arm["arm"]], 21, NAVY, "700")
        c.text(70, y + 65, arm["model_id"], 13, MUTED)
        x = 515
        for stage in stage_order:
            n = arm["died_at"].get(stage, 0)
            width = 850 * n / max_n
            if n:
                c.rect(x, y, width, 66, stage_colors[stage], stage_colors[stage], 4, 0)
                c.text(x + width / 2, y + 41, n, 20, WHITE, "700", "middle")
            x += width
        rate = 100 * arm["accepted"] / arm["proposals"]
        c.text(1415, y + 29, f'{arm["accepted"]}/{arm["proposals"]}', 22, GREEN if arm["accepted"] else MUTED, "700", "middle")
        c.text(1415, y + 58, f"{rate:.1f}% valid", 15, MUTED, anchor="middle")
    c.rect(65, 765, 1450, 56, "#EEF2F7", GRID, 12)
    c.text(90, 800, "NOT TESTED: Gemma 4 31B free and Gemini 3.1 Pro - HTTP 429 before any proposal reached a gate.", 17, SLATE, "700")
    c.save("03_model_gate_outcomes")


def model_rate_runtime(arms):
    tested = [a for a in arms if a["tested"]]
    tested.sort(key=lambda a: -a["accept_rate"])
    names = {
        "gemini:gemini-flash": "Gemini Flash",
        "openrouter:nemotron-ultra": "Nemotron Ultra",
        "openrouter:nemotron": "Nemotron Super",
        "openrouter:nemotron-nano": "Nemotron Nano",
    }
    c = Canvas(
        "Model acceptance rate and wall time",
        "Wall time includes provider latency, retries and formal gates; it is not pure inference latency.",
        "Source: corrected merged bake-off artifact",
    )
    c.text(385, 180, "Valid acceptance rate", 23, NAVY, "700", "middle")
    c.text(1160, 180, "End-to-end wall time", 23, NAVY, "700", "middle")
    for idx, arm in enumerate(tested):
        y = 250 + idx * 125
        name = names[arm["arm"]]
        c.text(65, y + 28, name, 19, INK, "700")
        rate = 100 * arm["accept_rate"]
        c.rect(260, y, 520, 50, "#E5EAF1", "#E5EAF1", 5, 0)
        if rate:
            c.rect(260, y, 520 * rate / 20, 50, GREEN, GREEN, 5, 0)
        c.text(795, y + 33, f"{rate:.1f}%", 18, GREEN if rate else MUTED, "700")
        mins = arm["wall_seconds"] / 60
        c.rect(985, y, 450, 50, "#E5EAF1", "#E5EAF1", 5, 0)
        c.rect(985, y, 450 * mins / 45, 50, BLUE, BLUE, 5, 0)
        c.text(1450, y + 33, f"{mins:.1f} min", 18, BLUE, "700")
    c.rect(65, 755, 1450, 70, "#FFF7ED", ORANGE, 12, 2)
    c.text(90, 787, "Audit correction", 18, ORANGE, "700")
    c.text(255, 787, "Nemotron Ultra raw history said 2/7; one no-op/wrong-target accept was removed. Honest score: 1/7.", 16, INK)
    c.save("04_model_rate_runtime")


def loop_verdicts(history):
    counts = {"accepted": 0, "g1": 0, "validate": 0}
    for row in history:
        counts[row["stage"]] = counts.get(row["stage"], 0) + 1
    c = Canvas(
        "Accepted-design loop: six proposal verdicts",
        "Four of six suggestions were stopped before final PnR.",
        "Source: artifacts/loop/history.jsonl",
    )
    items = [
        ("Accepted", counts.get("accepted", 0), GREEN, "formally gated into final candidate"),
        ("Formal rejection (G1)", counts.get("g1", 0), RED, "counterexample / contract failure"),
        ("Structural rejection", counts.get("validate", 0), ORANGE, "invalid before expensive proof"),
    ]
    for i, (label, n, color, note) in enumerate(items):
        x = 90 + i * 500
        c.rect(x, 220, 430, 400, WHITE, color, 22, 3)
        c.circle(x + 215, 365, 92, color, color, 1)
        c.text(x + 215, 388, n, 62, WHITE, "700", "middle")
        c.text(x + 215, 510, label, 23, color, "700", "middle")
        c.text(x + 215, 550, note, 15, MUTED, anchor="middle")
    c.rect(90, 690, 1430, 92, "#EEF6FF", BLUE, 15, 2)
    c.text(805, 728, "Core evidence", 18, BLUE, "700", "middle")
    c.text(805, 760, "Half of proposals from a capable model were formally disproved; compilation alone would not catch this.", 20, NAVY, "700", "middle")
    c.save("05_agent_loop_verdicts")


def fmax_chart(clocks):
    selected = ["clk1", "clk_s1", "clk_s2", "clk_s3", "clk_s4", "clk_s5", "clk_s8"]
    rows = [next(x for x in clocks if x["clock"] == name) for name in selected]
    c = Canvas(
        "Measured Fmax before and after optimization",
        "Primary/derived clocks with timing paths; generated gate clocks shown separately in CSV.",
        "Source: matched parasitic-aware period sweeps, baseline and final candidate",
    )
    plot_x, plot_y, plot_w, row_h = 360, 190, 1050, 82
    max_v = max(max(r["fmax_before"], r["fmax_after"]) for r in rows)
    for i, row in enumerate(rows):
        y = plot_y + i * row_h
        c.text(80, y + 36, row["clock"], 20, NAVY, "700")
        bw = plot_w * row["fmax_before"] / max_v
        aw = plot_w * row["fmax_after"] / max_v
        c.rect(plot_x, y, bw, 25, "#AFC4E8", "#AFC4E8", 3, 0)
        c.rect(plot_x, y + 31, aw, 25, GREEN if row["fmax_after"] >= row["fmax_before"] else ORANGE, GREEN if row["fmax_after"] >= row["fmax_before"] else ORANGE, 3, 0)
        c.text(plot_x + bw + 10, y + 20, f'{row["fmax_before"]:.2f}', 15, MUTED)
        c.text(plot_x + aw + 10, y + 52, f'{row["fmax_after"]:.2f}', 15, INK, "700")
    c.rect(85, 775, 18, 18, "#AFC4E8", "#AFC4E8", 2, 0)
    c.text(115, 790, "Baseline", 15, MUTED)
    c.rect(225, 775, 18, 18, GREEN, GREEN, 2, 0)
    c.text(255, 790, "Final (green improvement, orange regression)", 15, MUTED)
    c.text(1450, 790, "MHz", 16, NAVY, "700", "end")
    c.save("06_fmax_before_after")


def slack_delta_chart(clocks):
    timed = [x for x in clocks if x["delta_ns"] is not None]
    headline = next(x for x in timed if x["clock"] == "clk_s5")
    rest = [x for x in timed if x["clock"] != "clk_s5"]
    rest.sort(key=lambda x: x["delta_ns"])
    c = Canvas(
        "Per-clock setup slack change",
        "Positive means improvement. Four clocks have no paths and are excluded, not counted as passing.",
        "Source: final PPA comparison at identical 6_final stage",
    )
    c.text(470, 175, "Other timed clocks (-2 ns to +2 ns)", 21, NAVY, "700", "middle")
    zero_x, scale = 470, 190
    c.line(zero_x, 205, zero_x, 740, SLATE, 2)
    for i, row in enumerate(rest):
        y = 225 + i * 49
        c.text(75, y + 18, row["clock"], 16, INK, "700")
        value = row["delta_ns"]
        width = min(abs(value), 2.0) * scale
        color = GREEN if value >= 0 else ORANGE
        x = zero_x if value >= 0 else zero_x - width
        c.rect(x, y, width, 25, color, color, 2, 0)
        c.text(870, y + 19, f"{value:+.4f} ns", 15, color, "700", "end")
    c.rect(1000, 235, 500, 330, WHITE, GREEN, 22, 3)
    c.text(1250, 300, "clk_s5 headline", 24, NAVY, "700", "middle")
    c.text(1250, 385, f'{headline["delta_ns"]:+.4f} ns', 52, GREEN, "700", "middle")
    c.text(1250, 435, f'WNS {headline["wns_before"]:.4f} -> {headline["wns_after"]:.4f} ns', 20, INK, "700", "middle")
    c.text(1250, 485, "25.65 -> 89.09 MHz", 25, BLUE, "700", "middle")
    c.rect(1000, 625, 500, 115, "#FFF7ED", ORANGE, 16, 2)
    c.text(1250, 664, "Regressed slack", 18, ORANGE, "700", "middle")
    c.text(1250, 700, "clk_s1, clk_s1_gate, clk_s2_gate, clk_s4", 16, INK, anchor="middle")
    c.save("07_clock_slack_delta")


def ppa_chart(ppa):
    metrics = ppa["ppa"]
    c = Canvas(
        "Final physical implementation comparison",
        "Baseline and optimized designs compared at the same routed 6_final stage.",
        "Source: OpenROAD signoff reports with SPEF parasitics",
    )
    cards_data = [
        ("Routed area (um2)", metrics["area_um2"]["before"], metrics["area_um2"]["after"], "-1.596%", GREEN),
        ("Instances", metrics["instances"]["before"], metrics["instances"]["after"], "-4,927", GREEN),
        ("Setup WNS (ns)", metrics["wns"]["before"], metrics["wns"]["after"], "+25.088 ns", GREEN),
        ("Setup TNS (ns)", metrics["tns"]["before"], metrics["tns"]["after"], "+3382.4934 ns", GREEN),
    ]
    for i, (label, before, after, delta, color) in enumerate(cards_data):
        x = 65 + (i % 2) * 760
        y = 175 + (i // 2) * 285
        c.rect(x, y, 710, 235, WHITE, GRID, 18)
        c.text(x + 30, y + 43, label, 20, NAVY, "700")
        c.text(x + 30, y + 100, f"{before:,.4f}" if isinstance(before, float) else f"{before:,}", 27, MUTED, "700")
        c.text(x + 30, y + 132, "BASELINE", 14, MUTED, "700")
        c.arrow(x + 280, y + 100, x + 390, y + 100, BLUE, 3)
        c.text(x + 420, y + 100, f"{after:,.4f}" if isinstance(after, float) else f"{after:,}", 27, NAVY, "700")
        c.text(x + 420, y + 132, "FINAL", 14, MUTED, "700")
        c.rect(x + 30, y + 165, 650, 45, "#ECFDF5", "#A7F3D0", 8)
        c.text(x + 355, y + 195, delta, 18, color, "700", "middle")
    drc = metrics["drc_violations"]
    hold = metrics["wns_hold"]
    power = metrics["power_total_w"]["verdict"]
    c.text(800, 790, f'DRC: {drc["before"]} -> {drc["after"]} | Hold WNS: {hold["before"]:.4f} -> {hold["after"]:.4f} ns | Power: {power}', 17, INK, "700", "middle")
    c.save("08_physical_ppa")


def formal_chart(eqy, top):
    counts = eqy["counts"]
    items = [
        ("PROVED", counts["proved"], GREEN),
        ("TIMEOUT", counts["timeout"], ORANGE),
        ("UNPROVEN", counts["unproven"], PURPLE),
        ("TOOL ERROR", counts["tool_error"], SLATE),
        ("COUNTEREXAMPLE", counts["not_equivalent"], RED),
    ]
    c = Canvas(
        "Formal verification evidence",
        "Compositional EQY sweep plus latency-aware proof for the changed FP4 stream.",
        "Sources: EQY clean report and final top-level equivalence artifact",
    )
    x, y, total_w = 70, 220, 1460
    for label, n, color in items:
        width = total_w * n / 54
        if width:
            c.rect(x, y, width, 92, color, color, 2, 0)
            if width > 90:
                c.text(x + width / 2, y + 42, n, 27, WHITE, "700", "middle")
                c.text(x + width / 2, y + 70, label, 13, WHITE, "700", "middle")
            x += width
    for i, (label, n, color) in enumerate(items):
        bx = 110 + i * 290
        c.rect(bx, 355, 20, 20, color, color, 3, 0)
        c.text(bx + 30, 372, f"{label}: {n}", 16, INK, "700")
    c.rect(70, 450, 710, 285, WHITE, BLUE, 18, 3)
    c.text(425, 505, "EQY sweep", 24, BLUE, "700", "middle")
    c.text(425, 585, "36 / 54", 54, NAVY, "700", "middle")
    c.text(425, 630, "proved equivalent", 21, MUTED, anchor="middle")
    c.text(425, 684, "0 counterexamples", 25, GREEN, "700", "middle")
    c.rect(820, 450, 710, 285, WHITE, PURPLE, 18, 3)
    c.text(1175, 505, "Changed cone contract", 24, PURPLE, "700", "middle")
    latency = top["declared_difference"]["latency_cycles"]
    depth = top["proofs"]["fp4_stream"]["depth"]
    c.text(1175, 570, f"+{latency} cycles", 44, NAVY, "700", "middle")
    c.text(1175, 615, f"STREAM_EQUIVALENT at depth {depth}", 20, GREEN, "700", "middle")
    c.text(1175, 655, "data and order preserved", 18, MUTED, anchor="middle")
    c.text(1175, 695, "ordinary cycle equivalence: NOT_EQUIVALENT", 16, RED, "700", "middle")
    c.save("09_formal_verification")


def rtl_scope_chart(top):
    scope = top["rtl_scope"]
    c = Canvas(
        "Final RTL change scope",
        "Identity closes unchanged files; proof focuses on the modified cone.",
        "Source: SHA-256 manifest in toplevel_equiv.json",
    )
    total = scope["candidate_file_count"]
    values = [("Byte-identical", len([f for f in scope["files"] if f["status"] == "identical"]), BLUE),
              ("Changed", len(scope["changed_files"]), ORANGE),
              ("Added", len(scope["added_files"]), GREEN)]
    x, y, total_w = 80, 220, 1440
    for label, n, color in values:
        width = total_w * n / total
        c.rect(x, y, width, 100, color, color, 2, 0)
        if width > 100:
            c.text(x + width / 2, y + 45, n, 30, WHITE, "700", "middle")
            c.text(x + width / 2, y + 75, label, 16, WHITE, "700", "middle")
        x += width
    c.text(800, 370, "52 identical | 3 changed | 1 added", 25, NAVY, "700", "middle")
    modules = [
        ("axi_lite_dot.v", "changed", ORANGE),
        ("fp4_dot_stage.v", "added", GREEN),
        ("fp4_dot_unit.v", "changed", ORANGE),
        ("fp8_adder.v", "changed", ORANGE),
    ]
    for i, (name, status, color) in enumerate(modules):
        x = 80 + i * 375
        c.rect(x, 475, 330, 150, WHITE, color, 16, 3)
        c.text(x + 165, 535, name, 20, NAVY, "700", "middle")
        c.text(x + 165, 578, status.upper(), 16, color, "700", "middle")
        if i < len(modules) - 1:
            c.arrow(x + 330, 550, x + 363, 550, SLATE, 2)
    c.rect(80, 690, 1440, 90, "#EEF6FF", BLUE, 14, 2)
    c.text(800, 728, "Proof decomposition", 18, BLUE, "700", "middle")
    c.text(800, 758, "fp8_adder: complete combinational equivalence | FP4 stream: six-property latency contract | rest: file identity", 16, INK, anchor="middle")
    c.save("10_rtl_change_scope")


def stage_aware_chart(synth, ppa):
    mapped = [
        ("Cells", synth["top_cells"]["percent"]),
        ("Area", synth["top_area_um2"]["percent"]),
        ("Sequential area", synth["top_sequential_area_um2"]["percent"]),
    ]
    routed = [
        ("Instances", ppa["ppa"]["instances"]["pct"]),
        ("Area", ppa["ppa"]["area_um2"]["pct"]),
        ("Nets", ppa["ppa"]["nets"]["pct"]),
    ]
    c = Canvas(
        "Area results depend on implementation stage",
        "Mapped synthesis grows slightly; final routed implementation shrinks. Both results are retained.",
        "Sources: synthesis report and routed 6_final PPA report",
    )
    panels = [("Yosys mapped netlist", mapped, 80), ("OpenROAD routed 6_final", routed, 830)]
    for title, rows, x0 in panels:
        c.rect(x0, 185, 690, 525, WHITE, GRID, 18)
        c.text(x0 + 345, 235, title, 24, NAVY, "700", "middle")
        zero = x0 + 345
        c.line(zero, 285, zero, 630, SLATE, 2)
        for i, (label, value) in enumerate(rows):
            y = 330 + i * 105
            c.text(x0 + 25, y + 18, label, 18, INK, "700")
            width = min(abs(value), 5) * 55
            color = GREEN if value < 0 else ORANGE
            x = zero - width if value < 0 else zero
            c.rect(x, y - 8, width, 38, color, color, 3, 0)
            c.text(x0 + 650, y + 19, f"{value:+.3f}%", 19, color, "700", "end")
        c.text(x0 + 345, 675, "smaller < 0 | larger > 0", 15, MUTED, anchor="middle")
    c.rect(80, 750, 1440, 70, "#EEF6FF", BLUE, 12, 2)
    c.text(800, 792, "Do not compare mapped cells directly with routed instances; filler, tap, buffering and placement change the population.", 17, NAVY, "700", "middle")
    c.save("13_stage_aware_area")


def table_figure(stem, title, subtitle, headers, rows, widths, source, font=15):
    c = Canvas(title, subtitle, source)
    x0, y0 = 55, 175
    table_w = 1490
    row_h = min(74, 600 / max(len(rows) + 1, 1))
    c.rect(x0, y0, table_w, row_h, NAVY, NAVY, 4, 0)
    x = x0
    for header, frac in zip(headers, widths):
        c.text(x + 12, y0 + row_h * 0.66, header, font, WHITE, "700")
        x += table_w * frac
    for ridx, row in enumerate(rows):
        y = y0 + row_h * (ridx + 1)
        fill = WHITE if ridx % 2 == 0 else "#EEF2F7"
        c.rect(x0, y, table_w, row_h, fill, GRID, 0, 1)
        x = x0
        for value, frac in zip(row, widths):
            color = RED if "NOT TESTED" in str(value) else INK
            c.text(x + 12, y + row_h * 0.64, value, font, color, "700" if ridx < 2 else "400")
            x += table_w * frac
    c.save(stem)


def result_tables(arms, clocks, ppa, eqy, top, synth, history):
    names = {
        "gemini:gemini-flash": "Gemini 3.5 Flash",
        "gemini:gemini-pro": "Gemini 3.1 Pro",
        "openrouter:gemma-free": "Gemma 4 31B free",
        "openrouter:nemotron-nano": "Nemotron Nano 30B",
        "openrouter:nemotron-ultra": "Nemotron Ultra 550B",
        "openrouter:nemotron": "Nemotron Super 120B",
    }
    model_rows = []
    gate_rows = []
    for arm in arms:
        status = "TESTED" if arm["tested"] else "NOT TESTED (429)"
        rate = f'{100 * arm["accept_rate"]:.1f}%' if arm["tested"] else "N/A"
        stops = ", ".join(f"{k}:{v}" for k, v in arm["died_at"].items())
        model_rows.append({
            "model": names[arm["arm"]], "model_id": arm["model_id"], "licence": arm["licence"],
            "status": status, "recorded_attempts": arm["proposals"], "valid_accepted": arm["accepted"],
            "acceptance_rate": rate, "wall_seconds": arm["wall_seconds"], "individual_pnr": "not run",
        })
        gate_rows.append({
            "model": names[arm["arm"]], "propose": arm["died_at"].get("propose", 0),
            "validate": arm["died_at"].get("validate", 0), "audit": arm["died_at"].get("audit", 0),
            "g1": arm["died_at"].get("g1", 0), "backend": arm["died_at"].get("backend", 0),
            "accepted": arm["accepted"],
        })
    write_csv("model_comparison.csv", model_rows)
    write_csv("model_gate_breakdown.csv", gate_rows)

    clock_rows = []
    for row in clocks:
        clock_rows.append({
            "clock": row["clock"], "period_ns": row["period_ns"], "wns_before_ns": row["wns_before"],
            "wns_after_ns": row["wns_after"], "delta_ns": row["delta_ns"], "fmax_before_mhz": row["fmax_before"],
            "fmax_after_mhz": row["fmax_after"], "met_before": row["met_before"], "met_after": row["met_after"],
        })
    write_csv("clock_comparison.csv", clock_rows)

    ppa_rows = []
    for metric, values in ppa["ppa"].items():
        ppa_rows.append({"metric": metric, **values})
    write_csv("ppa_comparison.csv", ppa_rows)
    write_csv("formal_summary.csv", [
        {"check": "EQY modules", "result": eqy["headline"], "scope": "54-module compositional sweep"},
        {"check": "fp8_adder", "result": "EQUIVALENT", "scope": "complete combinational proof, depth 1"},
        {"check": "FP4 stream", "result": "STREAM_EQUIVALENT", "scope": "six-property contract, depth 16, +4 cycles"},
        {"check": "ordinary top cycle equivalence", "result": "NOT_EQUIVALENT", "scope": "expected after declared latency change"},
        {"check": "final qualified verdict", "result": top["verdict"], "scope": "identity + leaf proof + stream contract"},
    ])
    write_csv("proposal_outcomes.csv", [
        {key: row.get(key) for key in ["iteration", "attempt", "module", "transform", "latency_delta", "stage", "verdict", "reason"]}
        for row in history
    ])
    write_csv("eqy_module_results.csv", [
        {
            "module": row["module"], "category": row["category"], "status": row["status"],
            "seconds": row["seconds"], "proved_child_cut_points": ";".join(row["proved_child_cut_points"]),
            "intermediate_counterexample_claims": ";".join(row["intermediate_counterexample_claims"]),
        }
        for row in eqy["results"]
    ])
    write_csv("synthesis_module_comparison.csv", [
        {
            "module": row["module"], "presence": row["presence"],
            "cells_before": row["cells_local"]["before"], "cells_after": row["cells_local"]["after"],
            "cells_delta": row["cells_local"]["delta"], "cells_percent": row["cells_local"]["percent"],
            "area_before_um2": row["area_local_um2"]["before"], "area_after_um2": row["area_local_um2"]["after"],
            "area_delta_um2": row["area_local_um2"]["delta"], "area_percent": row["area_local_um2"]["percent"],
        }
        for row in synth["modules"]
    ])

    table_rows = []
    for row in sorted(model_rows, key=lambda x: (x["status"] != "TESTED", -x["valid_accepted"], x["model"])):
        table_rows.append([
            row["model"], row["licence"], row["status"], str(row["recorded_attempts"]),
            str(row["valid_accepted"]), row["acceptance_rate"], f'{row["wall_seconds"]/60:.1f} min', "Not run per arm",
        ])
    table_figure(
        "11_model_comparison_table", "Complete model comparison", "Individual model-arm PnR was not run; full PPA belongs to the combined accepted candidate.",
        ["Model", "Class", "Status", "Attempts", "Accepted", "Rate", "Wall", "PPA scope"], table_rows,
        [0.17, 0.12, 0.16, 0.08, 0.08, 0.08, 0.09, 0.22], "Source: corrected merged bake-off JSON", 13,
    )

    timed_rows = []
    for row in clocks:
        if row["wns_before"] is None:
            timed_rows.append([row["clock"], "NO PATH", "NO PATH", "N/A", "N/A", "N/A", "UNREPORTED"])
        else:
            timed_rows.append([
                row["clock"], f'{row["wns_before"]:.4f}', f'{row["wns_after"]:.4f}', f'{row["delta_ns"]:+.4f}',
                f'{row["fmax_before"]:.2f}', f'{row["fmax_after"]:.2f}', "PASS" if row["met_after"] else "VIOLATION",
            ])
    table_figure(
        "12_complete_clock_table", "Complete clock-by-clock timing table", "NO PATH means unconstrained/unreported, never a passing clock.",
        ["Clock", "WNS before", "WNS after", "Delta ns", "Fmax before", "Fmax after", "Final"], timed_rows,
        [0.13, 0.15, 0.15, 0.13, 0.15, 0.15, 0.14], "Source: PPA signoff comparison", 13,
    )


def retry_assets(retry):
    rows = []
    csv_rows = []
    for item in retry["completed_retries"]:
        rows.append([
            item["module"], str(item["depth"]), item["method"], item["status"],
            f'{item["seconds"]:.1f}', "YES" if item["new_proof"] else "NO",
        ])
        csv_rows.append({
            "module": item["module"], "depth": item["depth"], "method": item["method"],
            "status": item["status"], "seconds": item["seconds"], "new_proof": item["new_proof"],
            "evidence_sha256": item["evidence_sha256"],
        })
    write_csv("eqy_targeted_retries.csv", csv_rows)
    table_figure(
        "14_eqy_targeted_retries", "Targeted deeper EQY retries", "Five bounded checks produced zero new proofs; 36/54 remains the defensible result.",
        ["Module", "Depth", "Method", "Result", "Seconds", "New proof"], rows,
        [0.18, 0.07, 0.24, 0.31, 0.10, 0.10], "Source: artifacts/eqy/retry_summary_20260911.json", 13,
    )


def write_index(source_hashes):
    content = """# Digital result asset pack

Ready-to-paste figures are in `figures/` as both SVG and 1600x900 PNG. Machine-readable tables are in `data/`.

## Figure map

1. `01_proof_gated_flow` - innovation and complete loop.
2. `02_verified_dashboard` - headline signoff numbers and limits.
3. `03_model_gate_outcomes` - same-task stacked outcome comparison.
4. `04_model_rate_runtime` - valid acceptance rate and end-to-end wall time.
5. `05_agent_loop_verdicts` - six final-design proposal outcomes.
6. `06_fmax_before_after` - measured Fmax across clocks with timing paths.
7. `07_clock_slack_delta` - improvements and regressions per clock.
8. `08_physical_ppa` - routed area, instances, WNS and TNS.
9. `09_formal_verification` - EQY coverage and latency-aware proof.
10. `10_rtl_change_scope` - changed cone versus byte-identical RTL.
11. `11_model_comparison_table` - all model rows, including untested arms.
12. `12_complete_clock_table` - every clock, including four NO PATH rows.
13. `13_stage_aware_area` - mapped synthesis versus routed PPA without mixing stages.
14. `14_eqy_targeted_retries` - deeper retry results and zero-new-proof outcome.

## Required interpretation

- Only four model arms were tested: Nemotron Ultra, Nemotron Super, Nemotron Nano and Gemini Flash.
- Gemma free and Gemini Pro received HTTP 429 before a proposal reached a gate. They are `NOT TESTED`, not 0% performers.
- Nemotron Ultra is 1/7 after audit. A historical second accept targeted one module but returned an unchanged/wrong module and is invalid.
- Full OpenROAD PnR/PPA was run once for the final combined accepted candidate. No individual model-arm PnR numbers exist. The model comparison therefore reports proposal/gate performance; the PPA figures report final combined design performance.
- `clk1` and `clk_s8` retain small violations. `clk2` through `clk5` report no paths. Four timed clocks regress in slack while remaining closed.
- EQY has 36/54 proved and zero counterexamples; 18 modules remain unresolved. The accepted pipeline changes latency by four cycles, so ordinary cycle equivalence is not claimed.
- Five targeted deeper EQY retries produced zero new proofs. The original 36/54 result remains unchanged.

## Evidence hashes

"""
    for path, digest in source_hashes.items():
        content += f"- `{digest}`  `{path}`\n"
    (OUT / "README.md").write_text(content)


def main():
    FIG.mkdir(parents=True, exist_ok=True)
    DATA.mkdir(parents=True, exist_ok=True)
    sources = [
        "artifacts/bakeoff_all_20260911/bakeoff_all.json",
        "artifacts/submission_20260911/ppa.json",
        "artifacts/eqy/report.json",
        "artifacts/final_candidate/toplevel_equiv.json",
        "artifacts/loop/history.jsonl",
        "artifacts/submission_20260911/synth.json",
        "artifacts/eqy/retry_summary_20260911.json",
    ]
    hashes = {rel: hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() for rel in sources}
    bakeoff = load(sources[0])
    ppa = load(sources[1])
    eqy = load(sources[2])
    top = load(sources[3])
    history = [json.loads(line) for line in (ROOT / sources[4]).read_text().splitlines() if line.strip()]
    synth = load(sources[5])
    retry = load(sources[6])

    flow_figure()
    dashboard(ppa, eqy, top)
    model_outcomes(bakeoff["arms"])
    model_rate_runtime(bakeoff["arms"])
    loop_verdicts(history)
    fmax_chart(ppa["clocks"])
    slack_delta_chart(ppa["clocks"])
    ppa_chart(ppa)
    formal_chart(eqy, top)
    rtl_scope_chart(top)
    stage_aware_chart(synth, ppa)
    result_tables(bakeoff["arms"], ppa["clocks"], ppa, eqy, top, synth, history)
    retry_assets(retry)
    consolidated = {
        "provenance_sha256": hashes,
        "model_comparison": bakeoff,
        "physical_ppa": ppa,
        "formal_eqy": eqy,
        "top_level_contract": top,
        "synthesis": {
            "verdict": synth["verdict"], "top_cells": synth["top_cells"],
            "top_area_um2": synth["top_area_um2"], "top_sequential_area_um2": synth["top_sequential_area_um2"],
        },
        "accepted_loop_history": history,
        "eqy_targeted_retry": retry,
    }
    (DATA / "all_results.json").write_text(json.dumps(consolidated, indent=2) + "\n")
    write_index(hashes)
    print(f"generated {len(list(FIG.glob('*.png')))} PNG, {len(list(FIG.glob('*.svg')))} SVG, {len(list(DATA.glob('*.csv')))} CSV")
    print(OUT)


if __name__ == "__main__":
    main()
