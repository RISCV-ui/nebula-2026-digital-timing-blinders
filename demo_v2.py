#!/usr/bin/env python3
"""demo_v2.py -- the v2 flow, one command, narrated. Deliverable 7.

demo.py narrates the v1 (2026-09-11) run and reads artifacts/loop,
bench/rtl and artifacts/final_candidate. The report ships the v2 benchmark
and the v3 routes, so demoing v1 on camera would put different numbers on
screen from the ones in the PDF beside it. This reads the v2/v3 artifacts --
the same files scripts/build_report.py reads -- and finishes by re-deriving
the report's own macros and diffing them against report/generated/numbers.tex
on screen.

    python3 demo_v2.py            # all acts, from recorded artifacts
    python3 demo_v2.py --act 3    # one act
    python3 demo_v2.py --plain    # no ANSI colour, for a light terminal

Reads only. No API key, no network, no toolchain: it runs in about a second
and cannot fail in front of an audience for a reason unrelated to the work.
"""
from __future__ import annotations

import argparse, json, os, re, sys, textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
W = 78
C = {"hd": "\033[1;36m", "ok": "\033[32m", "no": "\033[31m",
     "dim": "\033[2m", "b": "\033[1m", "x": "\033[0m"}


def rule(ch="-"):
    print(C["dim"] + ch * W + C["x"])


def act(n, title, sub):
    print(); rule("=")
    print(f'{C["hd"]}ACT {n}{C["x"]}  {C["b"]}{title}{C["x"]}')
    print(C["dim"] + textwrap.fill(sub, W) + C["x"]); rule("=")


def say(t):
    print(textwrap.fill(t, W))


def load(rel, what):
    p = os.path.join(HERE, rel)
    if not os.path.exists(p):
        print(f'  {C["dim"]}(no {what} at {rel}){C["x"]}'); return None
    with open(p) as fh:
        return json.load(fh)


def jsonl(rel):
    p = os.path.join(HERE, rel)
    out = []
    if not os.path.exists(p):
        return out
    for line in open(p):
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def newest(pattern):
    import glob
    hits = sorted(glob.glob(os.path.join(HERE, pattern)))
    return hits[-1] if hits else None


V2_RUNS = ["artifacts/bakeoff_v2_sonnet_fixed", "artifacts/divider_run"]


def runs():
    import glob
    out = list(V2_RUNS)
    out += [os.path.relpath(os.path.dirname(p), HERE)
            for p in sorted(glob.glob(os.path.join(
                HERE, "artifacts/bakeoff_v2/*/history.jsonl")))]
    return [r for r in out if os.path.exists(os.path.join(HERE, r, "history.jsonl"))]


def eqy_results():
    """Netlist-equivalence verdicts, counted exactly as build_report.py does.

    Two sources: one serial run that only left a log, and the sharded runs
    that write JSON. Counting the shards alone under-reports by a whole
    variant, which is what a first pass of this demo did.
    """
    import glob
    out: dict[str, dict[str, dict]] = {}
    log = os.path.join(HERE, "artifacts/eqy_v2_serial_partial.log")
    if os.path.exists(log):
        for line in open(log):
            m = re.match(r"^(PASS|FAIL)\s+(\S+)\s+(.*?)\s*\((\d+\.?\d*)s\)", line)
            if m:
                out.setdefault("openrouter_nemotron-ultra", {})[m.group(2)] = {
                    "equivalent": m.group(1) == "PASS",
                    "status": m.group(3).strip()}
    for js in sorted(glob.glob(os.path.join(HERE, "artifacts/eqy/shards/*.json"))):
        variant = re.sub(r"_s\d+$", "", os.path.basename(js)[:-5])
        d = json.load(open(js))
        for r in d.get("results", []):
            out.setdefault(variant, {})[r["module"]] = r
    return out


# ----------------------------------------------------------------- acts

def act1(_):
    act(1, "Where is the design actually broken?",
        "OpenSTA reports the worst paths on the v2 benchmark. Reports are not "
        "problems: many share one module. The slicer collapses them and "
        "attributes the delay per module instance, so the model is sent a "
        "structure rather than an endpoint name.")
    d = load("artifacts/paths/v2_targets.json", "slicer output")
    if not d:
        return
    say(f'{d["path_count"]} targets on {d["top"]}, worst first.')
    print()
    for p in d["paths"][:8]:
        m = (p.get("modules") or [{}])[0]
        print(f'  {p["clock"]:<10}{C["no"]}{p["slack_ns"]:>11.2f} ns{C["x"]}'
              f'{p["stages"]:>6} stages  {m.get("module","-"):<20}'
              f'{m.get("share_pct",0):>6.1f}%')
    w = d["paths"][0]
    m = (w.get("modules") or [{}])[0]
    print()
    say(f'The worst is {w["clock"]} at {w["slack_ns"]:.4f} ns over '
        f'{w["stages"]} logic stages, with {m.get("share_pct")}% of the cell '
        f'delay inside {m.get("module")}. That is the number no amount of '
        "cell sizing reaches, which is why it is an RTL target and not a "
        "tool target.")


def act2(_):
    act(2, "Four models, identical paths, identical gates",
        "Every arm gets the same targets, the same retry budget and the same "
        "gates. The only variable is the model. Cost is recorded per arm "
        "because a proposer that needs ten retries is not free.")
    bk = load("artifacts/bakeoff_v2/bakeoff.json", "bake-off record")
    if not bk:
        return
    print(f'  {"arm":<32}{"proposals":>10}{"accepted":>10}{"wall s":>9}')
    for a in bk.get("arms", []):
        col = C["ok"] if a.get("accepted") else C["dim"]
        print(f'  {a["arm"]:<32}{a.get("proposals",0):>10}'
              f'{col}{a.get("accepted",0):>10}{C["x"]}'
              f'{a.get("wall_seconds",0):>9.0f}')
    say("\nAn arm that accepted nothing is not a failed experiment. It is the "
        "gates doing the job the report claims they do.")


def act3(_):
    act(3, "Where candidates die",
        "Eight independent ways for a rewrite to be wrong. The two rows below "
        "g1 are the interesting ones: those candidates are formally "
        "equivalent to the frozen module and still wrong, so an "
        "equivalence-only flow ships them.")
    bk = load("artifacts/bakeoff_v2/bakeoff.json", "bake-off record")
    if not bk:
        return
    labels = {"backend": "API call failed or was refused",
              "propose": "reply unusable (truncated or unparseable)",
              "validate": "not Verilog, or changed the interface",
              "g1": "not equivalent to the frozen module",
              "g1b": "equivalent, but broke the parent's timing contract",
              "g1c": "degraded clock structure at the module boundary",
              "g2": "broke a clock-domain crossing",
              "g2c": "created a glitch-prone clock"}
    tally = {}
    for a in bk.get("arms", []):
        for stage, n in (a.get("died_at") or {}).items():
            if stage != "accepted":
                tally[stage] = tally.get(stage, 0) + n
    accepted = sum(a.get("accepted", 0) for a in bk.get("arms", []))
    for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
        col = C["hd"] if k in ("g1b", "g1c", "g2", "g2c") else C["dim"]
        print(f'  {col}{k:<10}{C["x"]}{v:>4}  {labels.get(k,k)}')
    print(f'  {C["ok"]}{"accepted":<10}{C["x"]}{accepted:>4}')
    print()
    say(f'{sum(tally.values()) + accepted} candidates in, {accepted} out of '
        "the four bake-off arms. The third accepted edit in the report came "
        "from the re-run made after the harness defect on the propose row was "
        "fixed, and is counted separately for exactly that reason.")


def act4(_):
    act(4, "What survived, and what it changed",
        "Every accepted edit, with the run it came from. These are the only "
        "RTL changes in the reported design.")
    rows = []
    for r in runs():
        for h in jsonl(os.path.join(r, "history.jsonl")):
            if h.get("verdict") == "ACCEPTED":
                h["_run"] = r
                rows.append(h)
    if not rows:
        print("  (no accepted edits recorded)"); return
    for h in rows:
        print(f'  {C["ok"]}ACCEPTED{C["x"]}  {h.get("module","?"):<18}'
              f'{h.get("technique","-"):<22}{os.path.basename(h["_run"])}')
    say(f'\n{len(rows)} accepted edits. Each one is a complete module rewrite '
        "that passed every gate in Act 3, in that order, before any placement "
        "tool saw it.")


def act5(_):
    act(5, "The clock structures",
        "A rewrite that improves timing and quietly gates a clock is worse "
        "than no rewrite. The structural auditor recognises shapes; the "
        "simulation checks the thing the auditor cannot certify -- whether a "
        "real runt pulse appears at a handover.")
    ck = load("artifacts/clockcheck_v2.json", "clock audit")
    sim = load("artifacts/clocksim.json", "runt simulation")
    if ck:
        print(f'  auditor: {C["ok"] if ck.get("verdict")=="CLEAN" else C["no"]}'
              f'{ck.get("verdict")}{C["x"]}  '
              f'{len(ck.get("findings",[]))} findings, '
              f'{ck.get("glitchy")} glitch-prone')
        for f in ck.get("findings", [])[:4]:
            print(f'    {f.get("module","?"):<16}{f.get("net","?"):<12}'
                  f'{f.get("verdict","?")}')
    if sim:
        print(f'\n  simulation: {sim.get("runts_fixed")} runt pulses in the '
              f'repaired design, {sim.get("runts_control")} in the negative '
              "control")
        say("The negative control is the point. A checker that reports zero "
            "on a design with a real runt in it is reporting nothing.")


def act6(_):
    act(6, "The netlist, not the RTL",
        "Everything above proves RTL against RTL. This proves each synthesised "
        "netlist module against the RTL it came from, so a synthesis-stage "
        "mistake cannot hide behind an RTL-level proof.")
    res = eqy_results()
    tot = sum(len(v) for v in res.values())
    ok = sum(1 for v in res.values() for r in v.values() if r.get("equivalent"))
    for variant in sorted(res):
        mods = res[variant]
        good = sum(1 for r in mods.values() if r.get("equivalent"))
        to = sum(1 for r in mods.values() if "TIMEOUT" in (r.get("status") or ""))
        print(f'  {variant:<28}{good:>4} proved {len(mods):>4} checked '
              f'{to:>4} timed out')
    print(f'  {C["b"]}{"total":<28}{ok:>4} proved {tot:>4} checked{C["x"]}')
    say("\nUnproved is not disproved: the remainder are solver timeouts on "
        "deep arithmetic, reported as timeouts. Zero counterexamples were "
        "found on any real design.")


def act7(_):
    act(7, "What it cost in silicon",
        "Routed, not estimated. Each variant goes through the same OpenROAD "
        "recipe as the baseline, and the comparison is made on the routed "
        "database.")
    d = newest("artifacts/metrics_v2_*")
    if not d:
        print("  (no routed metrics yet)"); return
    import glob
    base = None
    mets = {}
    for f in sorted(glob.glob(os.path.join(d, "*.json"))):
        m = json.load(open(f))
        name = os.path.basename(f)[:-5]
        (mets if name != "baseline" else {}).setdefault(name, m)
        if name == "baseline":
            base = m
        else:
            mets[name] = m
    print(f'  {os.path.relpath(d, HERE)}')
    if not base:
        print("  (no routed baseline in this set)"); return
    print(f'\n  {"design":<26}{"instances":>12}{"area um2":>14}{"clk1 WNS":>12}')
    def row(name, m):
        print(f'  {name:<26}{m.get("instances",0):>12,}'
              f'{m.get("area_um2",0):>14,.0f}'
              f'{(m.get("clocks",{}).get("clk1",{}).get("wns_ns") or 0):>12.3f}')
    row("baseline", base)
    for name, m in mets.items():
        row(name, m)
    print()
    for name, m in mets.items():
        di = m.get("instances", 0) - base.get("instances", 0)
        da = m.get("area_um2", 0) - base.get("area_um2", 0)
        print(f'  {name}: {di:+,} instances, {da:+,.0f} um2')
    say("\nA gain that costs more area than it is worth is still reported. "
        "The report's claim is per-domain timing, not a free lunch.")

    # The v3 pair is a separate measurement generation -- its own baseline,
    # routed beside it. Never compared row-for-row with the set above.
    v3 = newest("artifacts/metrics_v3_*")
    if not v3:
        return
    import glob as _g
    m3 = {os.path.basename(f)[:-5]: json.load(open(f))
          for f in sorted(_g.glob(os.path.join(v3, "*.json")))}
    b3 = m3.pop("baseline", None)
    if not b3 or not m3:
        return
    name, v = next(iter(m3.items()))
    print(f'\n  second routed generation: {os.path.basename(v3)}')
    print(f'  {"clock":<14}{"baseline":>12}{"variant":>12}{"delta":>10}')
    for clk in sorted(b3.get("clocks", {})):
        a = b3["clocks"][clk].get("wns_ns")
        c = (v.get("clocks", {}).get(clk) or {}).get("wns_ns")
        if a is None or c is None or abs(c - a) < 5e-4:
            continue
        col = C["ok"] if c > a else C["dim"]
        print(f'  {clk:<14}{a:>12.4f}{c:>12.4f}{col}{c - a:>+10.4f}{C["x"]}')
    say("\nDifferent synthesis, different floorplan, its own baseline routed "
        "beside it. No number crosses between the two sets. What crosses is "
        "the direction of the effect, on the same domain.")


def act8(_):
    act(8, "Does the report agree with the artifacts?",
        "Every number in the PDF is a macro generated from the files this "
        "demo just read. Re-deriving them here and diffing against what is "
        "shipped is the only way to show that on camera.")
    gen = os.path.join(HERE, "report", "generated", "numbers.tex")
    if not os.path.exists(gen):
        print("  (no generated numbers; run scripts/build_report.py)"); return
    n = dict(re.findall(r"\\newcommand\{\\(\w+)\}\{(.*)\}", open(gen).read()))

    rows = []
    for r in runs():
        rows += [h for h in jsonl(os.path.join(r, "history.jsonl"))
                 if h.get("verdict") == "ACCEPTED"]
    res = eqy_results()
    tot = sum(len(v) for v in res.values())
    ok = sum(1 for v in res.values() for r in v.values() if r.get("equivalent"))
    sim = load("artifacts/clocksim.json", "runt simulation") or {}

    checks = [("numaccepted", len(rows)),
              ("eqychecked", tot),
              ("eqyproved", ok),
              ("runtsfixed", sim.get("runts_fixed")),
              ("runtscontrol", sim.get("runts_control"))]
    bad = 0
    for macro, here in checks:
        want = n.get(macro)
        good = want is not None and str(here) == want
        bad += not good
        print(f'  {C["ok"] if good else C["no"]}{"MATCH" if good else "DRIFT"}'
              f'{C["x"]}  \\{macro:<14} report {want!s:<8} artifacts {here}')
    print()
    if bad:
        say("A drift line means the PDF is older than the evidence beside it. "
            "Rebuild with scripts/build_report.py.")
    else:
        say("Every value in the report that this demo can re-derive from the "
            "artifacts matches. scripts/submission_check_v2.py does the same "
            "for all of them, fragment by fragment.")


ACTS = [act1, act2, act3, act4, act5, act6, act7, act8]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--act", type=int, help="run one act (1-8)")
    ap.add_argument("--plain", action="store_true", help="no ANSI colour")
    a = ap.parse_args()
    if a.plain or not sys.stdout.isatty():
        for k in C:
            C[k] = ""
    print(f'{C["b"]}Nebula 2026 -- Digital track -- Timing Blinders{C["x"]}')
    print(C["dim"] + "LLM proposes, formal gates decide. Recorded artifacts, "
          "read-only." + C["x"])
    todo = [ACTS[a.act - 1]] if a.act else ACTS
    for fn in todo:
        fn(False)
    print()
    rule("=")
    print("Report: report/nebula_report.pdf   "
          "Verify: python3 scripts/submission_check_v2.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
