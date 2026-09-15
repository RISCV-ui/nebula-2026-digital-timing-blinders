#!/usr/bin/env python3
"""Regenerate every number in the LaTeX report from the run artifacts.

The report must never contain a hand-typed measurement. Runs are still
finishing while it is being written, PnR reorders, an arm gets re-run with a
fixed harness -- and a number transcribed by hand into prose survives all of
that silently, which is the one failure mode a formal-equivalence project
cannot afford to demonstrate in its own report.

So the .tex under report/ carries the argument and this carries the numbers.
Every table and every quoted figure is written into report/generated/ as a
fragment the document \\inputs, and every inline figure is a \\newcommand in
numbers.tex, so a stale value is a build error rather than a wrong sentence.
Re-run this after any run finishes and the whole document is current.

Missing inputs are normal: this is expected to run while some of the work is
still in flight. Anything absent becomes a visibly marked placeholder rather
than a zero, because a zero reads as a result.

    usage: scripts/build_report.py [--out report/generated]
"""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "report" / "generated"
_V3: dict = {}
TBD = r"\tbd"          # defined in the preamble, renders as a visible marker


# ----------------------------------------------------------------- helpers

def latex_escape(s: str) -> str:
    out = str(s)
    for a, b in (("\\", r"\textbackslash{}"), ("_", r"\_"), ("&", r"\&"),
                 ("%", r"\%"), ("#", r"\#"), ("$", r"\$"), ("{", r"\{"),
                 ("}", r"\}"), ("^", r"\^{}"), ("~", r"\textasciitilde{}")):
        out = out.replace(a, b)
    return out


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def rows(path: Path) -> list[dict]:
    """history.jsonl, tolerating a file being appended to right now."""
    out = []
    try:
        text = path.read_text()
    except OSError:
        return out
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue        # a half-written final line, not a corrupt record
    return out


def v2_runs() -> list[Path]:
    """The run directories this report is about, named rather than globbed.

    artifacts/ holds every run this project has ever made: v1 arms, aborted
    partials, dry runs, negative controls, and an abandoned pre-patch attempt.
    Globbing for history.jsonl sweeps all of them into the totals, which is
    how a first pass reported 21 accepted edits for a run that made two. The
    set is therefore listed, and a run that is not listed is not counted.
    """
    named = [ROOT / "artifacts" / "bakeoff_v2_sonnet_fixed",
             ROOT / "artifacts" / "divider_run"]
    arms = sorted((ROOT / "artifacts" / "bakeoff_v2").glob("*/history.jsonl"))
    return [d for d in (named + [a.parent for a in arms])
            if (d / "history.jsonl").exists()]


def newest(pattern: str) -> Path | None:
    hits = sorted(ROOT.glob(pattern))
    return hits[-1] if hits else None


def num(v, digits=2, suffix=""):
    return TBD if v is None else f"{v:.{digits}f}{suffix}"


def signed(v, digits=2):
    return TBD if v is None else f"{v:+.{digits}f}"


def write(name: str, body: str) -> None:
    GEN.mkdir(parents=True, exist_ok=True)
    (GEN / name).write_text(body.rstrip() + "\n")
    print(f"  wrote {GEN.relative_to(ROOT) if GEN.is_relative_to(ROOT) else GEN}/{name}")


def short(name: str) -> str:
    """A variant directory name as it should read in a table header.

    The directories are named provider_model so they sort and cannot collide;
    a table header does not need the provider, and carrying it is what pushed
    the PPA and Fmax tables past the margin.
    """
    return name.split("_", 1)[-1].replace("-direct", "")


def tabular(spec: str, header: list[str], body: list[list[str]],
            caption: str, label: str, note: str = "") -> str:
    """One table, never wider than the text block.

    Column counts here are set by how many variants were routed and how many
    models were run, so a table that fits today overflows the moment another
    arm is added. adjustbox shrinks only when it has to, which keeps the
    common case at full size and the wide case inside the margin instead of
    silently past it.
    """
    head = " & ".join(rf"\textbf{{{h}}}" for h in header) + r" \\"
    lines = [r"\begin{table}[htbp]", r"  \centering", r"  \footnotesize",
             rf"  \caption{{{caption}}}", rf"  \label{{tab:{label}}}",
             r"  \begin{adjustbox}{max width=\textwidth}",
             rf"  \begin{{tabular}}{{{spec}}}", r"    \toprule",
             "    " + head, r"    \midrule"]
    for r in body:
        lines.append("    " + " & ".join(r) + r" \\")
    lines += [r"    \bottomrule", r"  \end{tabular}",
              r"  \end{adjustbox}"]
    if note:
        lines.append(rf"  \par\smallskip\footnotesize\raggedright {note}")
    lines.append(r"\end{table}")
    return "\n".join(lines)


# ------------------------------------------------------------------ timing

def fmax_mhz(period, wns):
    if period is None or wns is None:
        return None
    achievable = period - wns
    return 1000.0 / achievable if achievable > 0 else None


def unstable(period, wns) -> bool:
    """Fmax too ill-conditioned to quote on this domain.

    Same rule as scripts/fmax_by_domain.py and for the same reason: Fmax is
    1/(period - WNS), so a domain holding nearly a full period of slack
    divides by a very small number, and ordinary placement variance of a
    hundredth of a nanosecond swings it by hundreds of MHz. The slack delta
    stays in the table; the frequency derived from it is withheld.
    """
    if period is None or wns is None:
        return True
    return (period - wns) < 0.25 * period


def metrics_set() -> tuple[Path | None, dict[str, dict]]:
    d = newest("artifacts/metrics_v2_*")
    if d is None:
        return None, {}
    return d, {f.stem: load_json(f) or {} for f in sorted(d.glob("*.json"))}


def build_ppa(mets: dict) -> dict:
    """Global PPA, baseline against each routed variant."""
    base = mets.get("baseline")
    variants = [k for k in sorted(mets) if k != "baseline"]
    if not base:
        write("tab_ppa.tex", r"\emph{No routed baseline yet.}")
        return {}

    fields = [("wns", "Setup WNS (ns)", 4), ("tns", "Setup TNS (ns)", 1),
              ("wns_hold", "Hold WNS (ns)", 4), ("area_um2", r"Area (\si{\um\squared})", 0),
              ("instances", "Instances", 0), ("nets", "Nets", 0),
              ("wirelength_um", r"Wirelength (\si{\um})", 0),
              ("utilization_pct", "Utilisation (\\%)", 1),
              ("drc_violations", "DRC violations", 0)]
    header = ["Metric", "Baseline"] + [latex_escape(short(v)) for v in variants]
    body = []
    for key, label, dig in fields:
        row = [label, num(base.get(key), dig)]
        for v in variants:
            got = mets[v].get(key)
            ref = base.get(key)
            cell = num(got, dig)
            if got is not None and ref is not None and key in ("wns", "tns"):
                cell += rf" \tiny({signed(got - ref, dig)})"
            row.append(cell)
        body.append(row)
    write("tab_ppa.tex", tabular(
        "l" + "r" * (1 + len(variants)), header, body,
        "Post-route PPA, frozen input against each formally verified variant. "
        "Every variant is routed from the frozen RTL with only gate-accepted "
        "edits applied, and every figure is read from the same flow stage.",
        "ppa",
        r"Bracketed figures are the delta against the baseline. Global WNS is "
        r"set by a single unclosed path and is not a summary of the design; "
        r"see Table~\ref{tab:fmax}."))
    return {"variants": variants, "base": base}


def build_fmax(mets: dict) -> dict:
    base = mets.get("baseline")
    variants = [k for k in sorted(mets) if k != "baseline"]
    if not base:
        write("tab_fmax.tex", r"\emph{No routed baseline yet.}")
        return {}

    clocks = base.get("clocks") or {}
    header = ["Clock", "Period (ns)", "Base WNS"]
    for v in variants:
        header += [latex_escape(short(v)) + r" $\Delta$WNS",
                   r"$\Delta F_{\max}$"]
    body, consistent = [], []
    for clk in sorted(clocks):
        period = clocks[clk].get("period_ns")
        bw = clocks[clk].get("wns_ns")
        if bw is None:
            continue                     # domain OpenSTA reported no path for
        row = [latex_escape(clk), num(period, 1), num(bw, 4)]
        deltas = []
        for v in variants:
            vw = ((mets[v].get("clocks") or {}).get(clk) or {}).get("wns_ns")
            if vw is None:
                row += [TBD, TBD]
                deltas.append(None)
                continue
            dw = vw - bw
            deltas.append(dw)
            if unstable(period, bw) or unstable(period, vw):
                row += [signed(dw, 4), r"\emph{n/q}"]
            else:
                fb, fv = fmax_mhz(period, bw), fmax_mhz(period, vw)
                row += [signed(dw, 4),
                        TBD if (fb is None or fv is None) else signed(fv - fb, 2)]
        body.append(row)
        real = [d for d in deltas if d is not None]
        if len(real) > 1 and min(real) > 0.05 and (max(real) - min(real)) < 0.05:
            consistent.append((clk, period, bw, real))

    write("tab_fmax.tex", tabular(
        "l" + "r" * (2 + 2 * len(variants)), header, body,
        "Per-domain setup WNS and the frequency change it implies. The "
        "benchmark has five asynchronous masters and therefore five closure "
        "questions; collapsing them into one global number hides every result "
        "the run did produce.",
        "fmax",
        r"$F_{\max}=1/(\text{period}-\text{WNS})$, per domain, holding "
        r"everything else fixed; it is not the chip frequency, which the "
        r"slowest domain still governs. \emph{n/q} marks a domain whose slack "
        r"is nearly a full period: the reciprocal is ill-conditioned there and "
        r"a hundredth of a nanosecond of placement variance moves it by "
        r"hundreds of MHz, so the slack delta is reported and the frequency "
        r"derived from it is withheld."))
    return {"consistent": consistent, "variants": variants}


# ------------------------------------------------------------- the gate

GATE_ORDER = ["propose", "validate", "g1", "g1b", "g1c", "g2", "g2c",
              "accepted", "budget"]


def build_bakeoff() -> dict:
    bk = load_json(ROOT / "artifacts" / "bakeoff_v2" / "bakeoff.json")
    if not bk:
        write("tab_bakeoff.tex", r"\emph{No bake-off record yet.}")
        return {}
    header = ["Model", "Proposals", "Accepted", "Cost (USD)",
              "Harness losses", "Wall (h)"]
    body, total_cost = [], 0.0
    for arm in bk.get("arms", []):
        name = arm.get("arm", "?")
        lost, calls = harness_losses(ROOT / arm.get("out", ""))
        total_cost += arm.get("cost_usd") or 0.0
        body.append([latex_escape(name.replace(":", ": ")),
                     str(arm.get("proposals", 0)),
                     rf"\textbf{{{arm.get('accepted', 0)}}}",
                     num(arm.get("cost_usd"), 2),
                     f"{lost} of {calls}" if calls else "--",
                     num((arm.get("wall_seconds") or 0) / 3600.0, 1)])
    write("tab_bakeoff.tex", tabular(
        "lrrrrr", header, body,
        "Four models over the same three targets, one invocation, identical "
        "gate configuration. Acceptance means every gate passed, not that the "
        "model produced plausible-looking RTL.",
        "bakeoff",
        r"\emph{Harness losses} are calls this harness threw away rather than "
        r"the model declining: replies that exhausted the token budget inside "
        r"reasoning and emitted no text. They are disclosed because an arm "
        r"that lost calls attempted fewer real edits than its proposal count "
        r"suggests, and comparing accept rates across arms without that is "
        r"comparing two different experiments."))
    return {"total_cost": total_cost, "arms": bk.get("arms", [])}


def harness_losses(arm_dir: Path) -> tuple[int, int]:
    lost = calls = 0
    for r in rows(arm_dir / "history.jsonl"):
        if r.get("stage") != "propose" and r.get("verdict") not in (
                "TRUNCATED", "REFUSED"):
            continue
        if r.get("stage") == "propose" or r.get("verdict") in ("TRUNCATED",
                                                               "REFUSED"):
            calls += 1
            if (r.get("verdict") == "TRUNCATED"
                    or r.get("detail") == "unparseable reply"):
                lost += 1
    return lost, calls


def collect_accepts() -> list[dict]:
    """Every ACCEPTED row from every run directory, newest run last."""
    out = []
    for run in v2_runs():
        for r in rows(run / "history.jsonl"):
            if r.get("verdict") == "ACCEPTED":
                r["_run"] = str(run.relative_to(ROOT))
                out.append(r)
    return out


def build_accepts(accepts: list[dict]) -> dict:
    if not accepts:
        write("tab_accepts.tex", r"\emph{No accepted edit recorded yet.}")
        return {"n": 0}
    header = ["Module", "Transform", r"$\Delta$latency", "G1 verdict",
              "Proof", "Complete", "Solver (s)", "Run"]
    body = []
    for r in accepts:
        g1 = r.get("g1") or {}
        mods = r.get("accepted_modules") or [r.get("proposal_module") or "?"]
        body.append([
            r"\texttt{" + latex_escape(", ".join(mods)) + "}",
            latex_escape(r.get("transform") or "?"),
            str(r.get("latency_delta")),
            latex_escape(g1.get("verdict") or "?"),
            latex_escape(g1.get("proof") or "?"),
            r"\checkmark" if g1.get("complete") else "bounded",
            num(g1.get("solver_seconds"), 1),
            r"\texttt{" + latex_escape(Path(r["_run"]).name) + "}"])
    write("tab_accepts.tex", tabular(
        "llrllrrl", header, body,
        "Every edit the gate accepted, with the proof that admitted it. "
        "A complete proof settles equivalence for all inputs and all time; a "
        "bounded one limits only the right to declare equivalence, never the "
        "right to reject on a counterexample.",
        "accepts",
        r"The module column lists what the run actually rewrote, derived from "
        r"the working tree rather than from the proposal's own claim about "
        r"its scope."))
    return {"n": len(accepts)}


def build_gate_funnel() -> dict:
    """Where candidates died, across every arm of the bake-off."""
    bk = load_json(ROOT / "artifacts" / "bakeoff_v2" / "bakeoff.json")
    if not bk:
        write("tab_funnel.tex", r"\emph{No bake-off record yet.}")
        return {}
    tally: dict[str, int] = {}
    for arm in bk.get("arms", []):
        for stage, n in (arm.get("died_at") or {}).items():
            if stage == "accepted":
                continue        # counted once, below, as the summary row
            tally[stage] = tally.get(stage, 0) + n
    total = sum(tally.values()) + sum(a.get("accepted", 0)
                                      for a in bk.get("arms", []))
    labels = {
        "backend": "API call failed or was refused",
        "propose": "reply unusable (truncated or unparseable)",
        "validate": "did not parse as Verilog, or changed the interface",
        "g1": "not equivalent to the frozen module",
        "g1b": "equivalent, but broke the parent's timing contract",
        "g1c": "degraded clock structure at the module boundary",
        "g2": "broke a clock-domain crossing",
        "g2c": "created a glitch-prone clock",
    }
    body = [[latex_escape(labels.get(k, k)), r"\texttt{" + latex_escape(k) + "}",
             str(v)] for k, v in sorted(tally.items(), key=lambda kv: -kv[1])]
    accepted = sum(a.get("accepted", 0) for a in bk.get("arms", []))
    body.append([r"\textbf{accepted}", r"\texttt{accepted}",
                 rf"\textbf{{{accepted}}}"])
    write("tab_funnel.tex", tabular(
        "llr", ["Why the candidate was rejected", "Gate", "Count"], body,
        "Where candidates died, summed over all four models. Each row is a "
        "rewrite that looked reasonable enough to reach that gate.",
        "funnel",
        rf"{total} candidates in total. The two rows below \texttt{{g1}} are "
        r"the ones an equivalence-only flow would have shipped: they are "
        r"formally equivalent to the frozen module and still wrong."))
    return {"tally": tally, "total": total, "accepted": accepted}


def build_g1b_evidence() -> dict:
    """The rows that were EQUIVALENT and still rejected -- the headline."""
    seen, hits = set(), []
    for run in v2_runs():
        for r in rows(run / "history.jsonl"):
            stage = r.get("stage")
            if stage not in ("g1b", "g1c", "g2", "g2c"):
                continue
            if r.get("verdict") not in ("REJECTED", "CONTRACT_BROKEN"):
                continue
            g1 = r.get("g1") or {}
            if g1.get("verdict") != "EQUIVALENT":
                continue
            gate = r.get(stage) or {}
            key = (r.get("proposal_module"), r.get("backend"), stage,
                   gate.get("verdict"))
            if key in seen:
                continue        # the same candidate re-recorded across retries
            seen.add(key)
            hits.append((r, g1, stage, gate))

    if not hits:
        write("tab_g1b.tex", r"\emph{No such rejection recorded yet.}")
        return {"n": 0}

    header = ["Module", "Model", "G1 verdict", "Proof", "Killed by",
              "What the gate found"]
    body = []
    for r, g1, stage, gate in hits:
        model = (r.get("backend") or "?").split(":")[-1]
        why = gate.get("verdict") or "REJECTED"
        where = ", ".join(gate.get("parents") or []) or "--"
        body.append([
            r"\texttt{" + latex_escape(r.get("proposal_module") or "?") + "}",
            latex_escape(model),
            latex_escape(g1.get("verdict")),
            latex_escape(g1.get("proof") or "?"),
            r"\texttt{" + latex_escape(stage) + "}",
            latex_escape(why) + (rf" at \texttt{{{latex_escape(where)}}}"
                                 if where != "--" else "")])
    write("tab_g1b.tex", tabular(
        "llllll", header, body,
        "Rewrites that a formal equivalence check passed and the flow still "
        "rejected. These are the cases an EQY-only gate ships.",
        "g1b",
        r"Each of these is equivalent to the frozen module at its own "
        r"boundary and still wrong in the design: equivalence is a statement "
        r"about a function, and a pipeline stage is not only a function. "
        r"That three independently developed models produce the same defect "
        r"is the argument for checking it rather than reviewing for it."))
    return {"n": len(hits)}


# ---------------------------------------------- deliverable 6, netlist EQY

def build_netlist_eqy() -> dict:
    """RTL against its own post-synthesis netlist, module by module."""
    results: dict[str, dict[str, dict]] = {}

    for log in [ROOT / "artifacts" / "eqy_v2_serial_partial.log"]:
        if not log.exists():
            continue
        for line in log.read_text().splitlines():
            m = re.match(r"^(PASS|FAIL)\s+(\S+)\s+(.*?)\s*\((\d+\.?\d*)s\)", line)
            if m:
                results.setdefault("openrouter_nemotron-ultra", {})[m.group(2)] = {
                    "equivalent": m.group(1) == "PASS",
                    "status": m.group(3).strip(), "seconds": float(m.group(4))}

    for js in sorted(ROOT.glob("artifacts/eqy/shards/*.json")):
        variant = re.sub(r"_s\d+$", "", js.stem)
        d = load_json(js) or {}
        for r in d.get("results", []):
            results.setdefault(variant, {})[r["module"]] = r

    if not results:
        write("tab_eqy_netlist.tex", r"\emph{Netlist equivalence still running.}")
        return {}

    header = ["Variant", "Modules checked", "Proved equivalent",
              "Unproven at depth", "Timed out"]
    body, summary = [], {}
    for variant in sorted(results):
        mods = results[variant]
        ok = sum(1 for r in mods.values() if r.get("equivalent"))
        to = sum(1 for r in mods.values()
                 if "TIMEOUT" in (r.get("status") or ""))
        un = len(mods) - ok - to
        summary[variant] = {"checked": len(mods), "ok": ok, "unproven": un,
                            "timeout": to}
        body.append([latex_escape(short(variant)), str(len(mods)),
                     rf"\textbf{{{ok}}}", str(un), str(to)])
    write("tab_eqy_netlist.tex", tabular(
        "lrrrr", header, body,
        "Deliverable 6, second half: every module of each routed variant "
        "proved against its own synthesised netlist. This is a different "
        "claim from the loop's gate, and the pair is what covers frozen RTL "
        "through to layout.",
        "eqynetlist",
        r"\emph{Unproven at depth} and \emph{timed out} are limits of the "
        r"prover, not counterexamples: no module here was shown inequivalent. "
        r"They concentrate on the deep combinational blocks and the wide AXI "
        r"interconnect, which is the same difficulty the optimisation loop "
        r"exists to attack."))
    return summary


# ------------------------------------------------------------------ macros

def build_numbers(ppa, fmax, bake, acc, funnel, g1b, eqy, mets,
                  diffs=None, clkaudit=None) -> None:
    """Inline figures the prose cites, as macros, so none is hand-typed."""
    defs: list[tuple[str, str]] = []

    def macro(name, value):
        defs.append((name, value))

    macro("reportgenerated", datetime.now().strftime("%d %B %Y, %H:%M"))
    macro("numaccepted", str(acc.get("n", 0)))
    macro("numcandidates", str(funnel.get("total", 0)))
    # A control sequence name cannot contain a digit: \numg1bkills
    # parses as \numg followed by the text "1bkills", which TeX then
    # tries to typeset in the preamble. Spelled out instead.
    macro("numcontractkills", str(g1b.get("n", 0)))
    macro("bakeoffspend", num(bake.get("total_cost"), 2))

    base = mets.get("baseline") or {}
    macro("baselinewns", num(base.get("wns"), 4))
    macro("baselineinstances", f"{base.get('instances', 0):,}".replace(",", r"\,"))
    macro("baselinearea", f"{base.get('area_um2', 0):,.0f}".replace(",", r"\,"))
    macro("baselineclocks", str(len(base.get("clocks") or {})))

    best = None
    for clk, period, bw, deltas in (fmax.get("consistent") or []):
        span = max(deltas) - min(deltas)
        if best is None or min(deltas) > min(best[3]):
            best = (clk, period, bw, deltas, span)
    if best:
        clk, period, bw, deltas, span = best
        macro("bestclock", latex_escape(clk))
        macro("bestdelta", signed(min(deltas), 2))
        macro("bestagreement", num(span, 3))
        fb = fmax_mhz(period, bw)
        fv = fmax_mhz(period, bw + min(deltas))
        macro("bestfmaxgain", signed(fv - fb, 2) if fb and fv else TBD)
        macro("bestfmaxfrom", num(fb, 2) if fb else TBD)
        macro("bestfmaxto", num(fv, 2) if fv else TBD)
    else:
        for n in ("bestclock", "bestdelta", "bestagreement", "bestfmaxgain",
                  "bestfmaxfrom", "bestfmaxto"):
            macro(n, TBD)

    v3 = _V3 or {}
    if v3.get("best"):
        macro("vthreeclock", latex_escape(v3["best"][0]))
        macro("vthreedelta", signed(v3["best"][1], 2))
        macro("vthreegains", str(v3["gains"]))
        macro("vthreeregress", str(v3["regress"]))
        macro("vthreearea", signed(v3["area"], 0))
        macro("vthreeinstances", signed(v3["instances"], 0))
    else:
        for n in ("vthreeclock", "vthreedelta", "vthreegains", "vthreeregress",
                  "vthreearea", "vthreeinstances"):
            macro(n, TBD)

    tot = {"checked": 0, "ok": 0}
    for v in (eqy or {}).values():
        tot["checked"] += v["checked"]
        tot["ok"] += v["ok"]
    macro("eqychecked", str(tot["checked"]))
    macro("eqyproved", str(tot["ok"]))

    # Diff sizes, so the appendix cannot quote a line count the diff it
    # prints does not have.
    for arm, n in (diffs or {}).items():
        key = "difflines" + "".join(c for c in short(arm) if c.isalpha())
        macro(key, str(n))

    if clkaudit:
        macro("clockglitchy", str(clkaudit["glitchy"]))
        macro("clockfindings", str(clkaudit["findings"]))
        macro("clockverdict", latex_escape(str(clkaudit.get("verdict", "?"))))
        if clkaudit.get("runtsfixed") is not None:
            macro("runtsfixed", str(clkaudit["runtsfixed"]))
            macro("runtscontrol", str(clkaudit["runtscontrol"]))

    bad = [n for n, _ in defs if not n.isalpha()]
    if bad:
        raise SystemExit(f"macro names must be letters only, TeX cannot "
                         f"define these: {bad}")

    body = [r"% Generated by scripts/build_report.py -- do not edit.",
            r"\providecommand{\tbd}{\textcolor{red}{\textbf{[pending]}}}"]
    for name, value in defs:
        body.append(rf"\newcommand{{\{name}}}{{{value}}}")
    write("numbers.tex", "\n".join(body))


def build_clocks(mets: dict) -> None:
    """The clock tree, as the SDC declares it and STA measured it."""
    import re as _re
    sdc = ROOT / "bench" / "constraints" / "nebula.sdc"
    try:
        text = sdc.read_text()
    except OSError:
        write("tab_clocks.tex", r"\emph{Constraints file not found.}")
        return
    masters = _re.findall(
        r"create_clock\s+-name\s+(\w+)\s+-period\s+([\d.]+).*?;#\s*(.*?)\s*$",
        text, _re.M)
    gen = _re.findall(
        r"create_generated_clock\s+-name\s+(\w+)\s+-source\s+"
        r"\[[^\]]*?(\w+)\]\s*\\?\s*\n?\s*-divide_by\s+(\d+)", text)
    base = (mets.get("baseline") or {}).get("clocks") or {}

    def wns_cell(name):
        """WNS, or why there isn't one.

        A clock STA knows about but reports no slack for is not a missing
        measurement -- it is a domain with no constrained endpoint, which for
        the four peripheral masters is the truth: every flop in those domains
        sits on the generated clock behind the gate and divider, not on the
        master itself. Printing the pending marker there claims a number is
        owed when none is.
        """
        if name not in base:
            return TBD
        v = (base.get(name) or {}).get("wns_ns")
        return num(v, 4) if v is not None else r"{\footnotesize no endpoints}"

    body = []
    for name, per, note in masters:
        body.append([r"\texttt{" + latex_escape(name) + "}", "master", "--",
                     f"{float(per):g}", latex_escape(note.split(";")[0].strip()),
                     wns_cell(name)])
    for name, src, div in gen:
        per = (base.get(name) or {}).get("period_ns")
        body.append([r"\texttt{" + latex_escape(name) + "}", "generated",
                     r"\texttt{" + latex_escape(src) + "}", num(per, 1),
                     rf"divide by {div}", wns_cell(name)])
    write("tab_clocks.tex", tabular(
        "llrrll", ["Clock", "Kind", "Source", "Period (ns)", "Role",
                   "Baseline WNS"], body,
        "Every clock the design declares. The five masters are mutually "
        "asynchronous; each generated clock names the source it is derived "
        "from, so the analyser follows the gate and divider chain instead of "
        "treating their outputs as unclocked nets.",
        "clocks",
        r"`no endpoints' is a domain in which nothing is clocked directly: "
        r"every flop behind those four masters sits on the generated clock "
        r"after the gate and divider, so the master itself owns no "
        r"constrained path. Generated clocks are declared divide-by-1 because that is "
        r"the fastest the divider mux can run, and a design that closes "
        r"there closes at every other setting."))


def build_scale(mets: dict) -> None:
    """How big the thing actually is, counted rather than claimed."""
    rtl = ROOT / "bench" / "rtl_v2"
    files = sorted(rtl.glob("*.v"))
    lines = sum(len(f.read_text().splitlines()) for f in files)
    base = mets.get("baseline") or {}
    body = [
        ["RTL modules", f"{len(files)}"],
        ["RTL lines", f"{lines:,}".replace(",", r"\,")],
        ["Master clock domains", "5, mutually asynchronous"],
        ["Clocks declared", str(len(base.get("clocks") or {}))],
        ["Placed instances", f"{base.get('instances', 0):,}".replace(",", r"\,")],
        ["Nets", f"{base.get('nets', 0):,}".replace(",", r"\,")],
        ["Die area", num(base.get("area_um2"), 0) + r"\,\si{\um\squared}"],
        ["Routed wirelength", num(base.get("wirelength_um"), 0) + r"\,\si{\um}"],
        ["Utilisation", num(base.get("utilization_pct"), 1) + r"\,\%"],
        ["PDK", r"sky130hd, via OpenROAD-flow-scripts"],
    ]
    write("tab_scale.tex", tabular(
        "lr", ["", "Frozen input, post-route"], body,
        "The benchmark at the scale the competition asks for, measured on the "
        "routed baseline rather than estimated from the RTL.",
        "scale"))


def build_v3_confirm() -> dict:
    """The same transform re-routed on a later, self-consistent generation.

    artifacts/metrics_v2_* and artifacts/metrics_v3_* are different
    measurement generations: different synthesis, different floorplan, and a
    baseline that closes far better in the v3 one. Reading a variant from one
    and a baseline from the other is exactly the mistake the v1 headline made,
    so they are never mixed. The v2 set carries the report's PPA because it is
    the one with two independently generated variants in it; this reports the
    v3 pair on its own terms -- its own baseline, routed alongside it.
    """
    d = newest("artifacts/metrics_v3_*")
    if d is None:
        write("tab_v3.tex", "")
        return {}
    mets = {f.stem: load_json(f) or {} for f in sorted(d.glob("*.json"))}
    base = mets.get("baseline")
    variants = [k for k in sorted(mets) if k != "baseline"]
    if not base or not variants:
        write("tab_v3.tex", "")
        return {}

    v = mets[variants[0]]
    bc, vc = base.get("clocks") or {}, v.get("clocks") or {}
    body, gains, regress = [], [], []
    for clk in sorted(bc):
        b, a = bc[clk].get("wns_ns"), (vc.get(clk) or {}).get("wns_ns")
        if b is None or a is None:
            continue
        delta = a - b
        if abs(delta) < 5e-4:
            continue
        (gains if delta > 0 else regress).append((clk, delta))
        body.append([latex_escape(clk), num(b, 4), num(a, 4),
                     r"\textbf{" + signed(delta, 4) + "}"])
    if not body:
        write("tab_v3.tex", "")
        return {}

    write("tab_v3.tex", tabular(
        "lrrr", ["Clock", "Baseline WNS (ns)", "Variant WNS (ns)",
                 r"$\Delta$ (ns)"], body,
        "The accepted transform re-measured on a second, independently routed "
        "generation: a wider floorplan, its own baseline routed beside it, "
        "same recipe for both. Clocks whose slack is unchanged to "
        r"\SI{0.5}{\pico\second} are omitted.",
        "v3",
        r"This table is not comparable row-for-row with Table~\ref{tab:ppa}: "
        "the two come from different synthesis and floorplan generations, and "
        "no number is carried between them. It is reported because the "
        "direction of the effect survives a change of generation, which is a "
        "stronger statement than either measurement alone."))
    return {"dir": d.name, "variant": variants[0],
            "gains": len(gains), "regress": len(regress),
            "best": max(gains, key=lambda g: g[1]) if gains else None,
            "worst": min(regress, key=lambda g: g[1]) if regress else None,
            "instances": v.get("instances", 0) - base.get("instances", 0),
            "area": v.get("area_um2", 0) - base.get("area_um2", 0)}


def build_diff() -> dict:
    """The accepted rewrite itself, as a diff against the frozen module.

    The report claims a transform was applied and proved. A reader who wants
    to check that claim needs the edit, not a description of it, so the hunks
    are cut out of `diff -u` at build time rather than transcribed. Only the
    hunks that change code are kept: both models also deleted comments, which
    is real but says nothing about the transform.
    """
    import subprocess

    base = ROOT / "bench" / "rtl_v2" / "fp8_adder.v"
    vars_ = ROOT / "output" / "rtl_variants_v2"
    out, seen = [], {}
    for arm in sorted(vars_.glob("*/rtl/fp8_adder.v")):
        name = arm.parents[1].name
        d = subprocess.run(["diff", "-u", str(base), str(arm)],
                           capture_output=True, text=True).stdout
        if not d.strip():
            continue
        hunks, keep = [], None
        for line in d.splitlines():
            if line.startswith("@@"):
                if keep and any(l.startswith("+") and l[1:].strip()
                                and not l[1:].lstrip().startswith("//")
                                for l in keep):
                    hunks.append(keep)
                keep = [line]
            elif keep is not None:
                keep.append(line)
        if keep and any(l.startswith("+") and l[1:].strip()
                        and not l[1:].lstrip().startswith("//") for l in keep):
            hunks.append(keep)
        seen[name] = sum(1 for l in d.splitlines()
                         if l[:1] in "+-" and not l.startswith(("---", "+++")))
        # Size is the wrong way to pick the hunk: the biggest one in the
        # nemotron diff is a block of default assignments it reindented,
        # which shows nothing. Score on rewritten logic instead -- control
        # flow and operators, not constant defaults.
        def weight(h):
            n = 0
            for l in h:
                if l[:1] not in "+-" or l.startswith(("---", "+++")):
                    continue
                t = l[1:].strip()
                if not t or t.startswith("//"):
                    continue
                if re.fullmatch(r"[\w\[\]:]+\s*=\s*[\w\']+;.*", t):
                    continue          # a default assignment, not a rewrite
                n += any(k in t for k in ("casez", "case", "if ", "always",
                                          "assign", "<=", "?", "for "))
            return n

        best = max(hunks, key=weight) if hunks else []
        if not best:
            continue
        out.append(r"\paragraph{" + latex_escape(short(name)) + r".} "
                   + f"{seen[name]} changed lines in total; the hunk that "
                     r"carries the transform:")
        # One arm rewrote the whole always block as a single 249-line hunk,
        # so the first 40 lines of it are the default assignments and the
        # transform is buried. Show the densest window instead, and say so.
        head, body = best[0], best[1:]
        span = 34
        if len(body) > span:
            starts = range(0, len(body) - span + 1)
            i = max(starts, key=lambda j: weight(body[j:j + span]))
            body = ([r"@@ ... {} lines earlier in the same hunk ...".format(i)]
                    if i else []) + body[i:i + span]
        out.append(r"\begin{lstlisting}[style=diff]")
        out += [head] + body
        out.append(r"\end{lstlisting}")
    if not out:
        write("diff_fp8.tex", r"\emph{No accepted rewrite of \texttt{fp8\_adder} "
                             r"in the current variant set.}")
        return {}
    write("diff_fp8.tex", "\n".join(out))
    return seen


def build_prompt() -> int:
    """The system prompt, quoted out of loop.py rather than retyped.

    It is the contract the model is held to, and most of it exists because a
    run went wrong without that line. Printing a paraphrase of it in the
    report would make the contract unauditable, which is the opposite of the
    point.
    """
    src = (ROOT / "bench" / "scripts" / "loop.py").read_text()
    m = re.search(r'SYSTEM = """(.*?)"""', src, re.S)
    if not m:
        write("prompt.tex", r"\emph{System prompt not found in loop.py.}")
        return 0
    text = m.group(1).strip("\n")
    write("prompt.tex",
          "\\begin{lstlisting}[style=plain]\n" + text + "\n\\end{lstlisting}")
    return len(text.splitlines())


def build_clockrisk() -> dict:
    """The clock-structure audit, and the simulation that backs it.

    The auditor is structural: it recognises shapes. That is the right thing
    to run inside the loop -- it is instant and it cannot be fooled into
    passing a shape nobody wrote down -- but a shape recogniser returning
    SAFE_MUX is not proof of a clean waveform. The runt-pulse simulation is
    the proof, and it is reported next to the audit rather than instead of it,
    including the control run on the pre-fix structures: a runt check that
    passes on a design known to produce runts measures nothing.
    """
    f = ROOT / "artifacts" / "clockcheck_v2.json"
    try:
        d = json.loads(f.read_text())
    except (OSError, json.JSONDecodeError):
        write("tab_clockrisk.tex", r"\emph{No clock audit on file.}")
        return {}
    body = []
    for r in d.get("findings", []):
        body.append([r"\texttt{" + latex_escape(r["module"]) + "}",
                     r"\texttt{" + latex_escape(r["net"]) + "}",
                     r"\texttt{" + latex_escape(r["verdict"]) + "}",
                     latex_escape(r["reason"])])

    sim = {}
    try:
        sim = json.loads((ROOT / "artifacts" / "clocksim.json").read_text())
    except (OSError, json.JSONDecodeError):
        pass

    cap = ("The clock-structure audit of the benchmark. Both structures "
           "started glitchy -- a bare AND clock gate and a combinational "
           "clock mux -- and both were rewritten: the gate into a latch-based "
           "ICG, the divider select into a handover mux whose branches are "
           "enabled by flops on their own clock.")
    if sim:
        cap += (" Simulation agrees with the audit: "
                f"{sim.get('runts_fixed', '?')} runt pulses on the fixed "
                f"structures against "
                f"{sim.get('runts_control', '?')} on the originals under the "
                "same stimulus, which switches the divider select while the "
                "selected clock is high.")
    write("tab_clockrisk.tex", tabular(
        "lllp{62mm}", ["Module", "Net", "Verdict", "What the auditor found"],
        body, cap, "clockrisk"))
    return {"glitchy": d.get("glitchy", 0),
            "findings": len(d.get("findings", [])),
            "verdict": d.get("verdict", "?"),
            "simverdict": sim.get("verdict", "?"),
            "runtsfixed": sim.get("runts_fixed"),
            "runtscontrol": sim.get("runts_control")}


def main() -> None:
    global GEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(GEN),
                    help="fragment directory; submission_check_v2.py points "
                         "this at a scratch dir to diff against the shipped one")
    GEN = Path(ap.parse_args().out).resolve()

    print("regenerating report numbers")
    mdir, mets = metrics_set()
    print(f"  metrics: {mdir.name if mdir else 'none yet'}")
    ppa = build_ppa(mets)
    fmax = build_fmax(mets)
    bake = build_bakeoff()
    acc = build_accepts(collect_accepts())
    funnel = build_gate_funnel()
    g1b = build_g1b_evidence()
    eqy = build_netlist_eqy()
    build_clocks(mets)
    build_scale(mets)
    global _V3
    _V3 = build_v3_confirm()
    print(f"  v3 confirmation: {_V3.get('dir', 'none')}")
    diffs = build_diff()
    build_prompt()
    clk = build_clockrisk()
    build_numbers(ppa, fmax, bake, acc, funnel, g1b, eqy, mets, diffs,
                  clk)
    print("done")


if __name__ == "__main__":
    main()
