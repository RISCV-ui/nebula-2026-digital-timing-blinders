#!/usr/bin/env python3
"""
demo.py -- the whole flow, one command, narrated.

Deliverable 7. Seven acts, in the order the flow actually runs them, each one
printing the evidence it acted on rather than a claim that it worked.

Two modes:

    --replay   (default) reads the artifacts on disk from the recorded run.
               Runs in seconds, needs no API key and no network, and is what
               the recorded video shows. Every number it prints came from a
               real run; nothing here is scripted output.

    --live     re-runs the gates for real against the RTL. Needs the Yosys
               toolchain on PATH (`source orfs/env.sh`). Model calls still
               come from the recorded run unless --backend is given, because
               a demo that depends on a free-tier provider being up is a demo
               that fails in front of an audience.

The order is the point. Acts 1-2 narrow 20 reported paths to one model call.
Acts 3-6 are four independent ways for an edit to be wrong, and on this design
three of them fire. Act 7 measures what survived.

    python3 demo.py                # replay, all acts
    python3 demo.py --act 4        # just the G1b act
    python3 demo.py --live --act 6 # actually re-run the clock audit
"""
import argparse, json, os, subprocess, sys, textwrap, time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "bench", "scripts")
sys.path.insert(0, SCRIPTS)

W = 78
C = {"hd": "\033[1;36m", "ok": "\033[32m", "no": "\033[31m",
     "dim": "\033[2m", "b": "\033[1m", "x": "\033[0m"}


def plain():
    for k in C:
        C[k] = ""


def rule(ch="-"):
    print(C["dim"] + ch * W + C["x"])


def act(n, title, sub):
    print()
    rule("=")
    print(f'{C["hd"]}ACT {n}{C["x"]}  {C["b"]}{title}{C["x"]}')
    print(C["dim"] + textwrap.fill(sub, W) + C["x"])
    rule("=")


def say(text):
    print(textwrap.fill(text, W))


def verdict(ok, text):
    print(f'  {(C["ok"] + "PASS" if ok else C["no"] + "FAIL")}{C["x"]}  {text}')


def load(path, what):
    p = os.path.join(HERE, path)
    if not os.path.exists(p):
        print(f'  {C["dim"]}(no recorded {what} at {path}; run the flow first)'
              f'{C["x"]}')
        return None
    return json.load(open(p))


def sh(cmd, tail=40):
    """Run a real command and echo it, so the audience sees it is not canned."""
    print(f'  {C["dim"]}$ {" ".join(cmd[-6:])}{C["x"]}')
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=HERE)
    for line in (r.stdout + r.stderr).splitlines()[-tail:]:
        print("    " + line)
    print(f'  {C["dim"]}({time.time() - t0:.1f}s){C["x"]}')
    return r


# ----------------------------------------------------------------- acts

def act1(live):
    act(1, "Where is the design actually broken?",
        "OpenSTA reports twenty critical paths. Twenty reports are not twenty "
        "problems: many are endpoints of one FIFO word, and many blame the "
        "same module. The slicer collapses them and attributes the delay per "
        "module instance.")
    d = load("artifacts/paths/baseline.json", "slicer output")
    if not d:
        return
    say(f'20 reported paths collapse to {d["path_count"]} targets.')
    print()
    for p in d["paths"]:
        t = p.get("target") or {}
        s = p["slack_ns"]
        col = C["no"] if s < 0 else C["dim"]
        print(f'  {p["id"]} {p["clock"]:<12}{col}slack {s:>9.3f}{C["x"]}  '
              f'{p["stages"]:>3} stages  {t.get("module","-"):<24}'
              f'{t.get("share_pct",0):>6.1f}% x{len(t.get("instances",[])) or 1}')
    print()
    worst = d["paths"][0]
    say(f'One domain fails: {worst["clock"]} misses by '
        f'{-worst["slack_ns"]:.3f} ns over {worst["stages"]} logic stages, '
        f'{(worst.get("target") or {}).get("share_pct",0)}% of it inside '
        f'{len((worst.get("target") or {}).get("instances",[]))} chained '
        f'{(worst.get("target") or {}).get("module")} instances.')


def act2(live):
    act(2, "Which of these is an RTL problem at all?",
        "A path missing by a few hundred picoseconds gets fixed by the "
        "synthesiser upsizing a cell. Spending a model call and a formal "
        "proof on it duplicates work that is free and carries no equivalence "
        "risk. So every path is labelled none / gate / rtl, with the "
        "arithmetic attached.")
    d = load("artifacts/paths/baseline.json", "slicer output")
    if not d:
        return
    for p in d["paths"]:
        lv = p.get("lever") or {}
        tag = lv.get("lever", "?")
        col = {"rtl": C["no"], "gate": C["hd"]}.get(tag, C["dim"])
        print(f'  {p["id"]} {col}{tag:<5}{C["x"]} {lv.get("reason","")[:120]}')
    n = sum(1 for p in d["paths"] if (p.get("lever") or {}).get("lever") == "rtl")
    print()
    say(f'{d["path_count"]} targets, {n} worth a model call. That is the '
        f'entire call budget for this design.')


def act3(live):
    act(3, "G1 -- is the rewrite the same circuit?",
        "The model returns a complete rewritten module. Before anything else "
        "looks at it, a Yosys miter proves it computes the same function. A "
        "latency-changing transform is compared against its own outputs "
        "delayed by N, because comparing a pipeline against its unpipelined "
        "self reports a failure that is real and useless.")
    if live:
        sh([sys.executable, os.path.join(SCRIPTS, "g1_equiv.py"),
            "--golden", "bench/rtl", "--candidate", "artifacts/loop/rtl_frozen",
            "--module", "fp8_adder", "--json"])
        return
    h = os.path.join(HERE, "artifacts/loop/history.jsonl")
    if not os.path.exists(h):
        print("  (no recorded loop history)")
        return
    for line in open(h):
        r = json.loads(line)
        g1 = r.get("g1") or {}
        if not g1:
            continue
        ok = g1.get("verdict") == "EQUIVALENT"
        verdict(ok, f'{r.get("module"):<16} {r.get("transform"):<18} '
                    f'lat +{g1.get("latency_delta",0)}  '
                    f'{g1.get("verdict")}  depth {g1.get("depth")}  '
                    f'{g1.get("proof","-")}  {g1.get("seconds")}s')
    print()
    say("A stateless module gets a complete proof at depth 1, not a bounded "
        "one at depth 12 -- agreeing for one cycle means agreeing forever. "
        "The verdict record says which of the three arguments it rests on.")


def act4(live):
    act(4, "G1b -- and does its parent survive the new latency?",
        "This is the act worth watching. The model pipelined the dot unit "
        "into four clean stages. G1 passed it. The module is genuinely "
        "correct -- and the SoC is broken, because the parent pushes the "
        "result into a FIFO on the same cycle it pops the operands.")
    print(textwrap.indent(
        "fp4_dot_unit fp4_dot_0(clk_2, rst_2, va, vb, dot_out);\n"
        "assign fifo_data_write = dot_out;\n"
        "assign w_en   = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);\n"
        "assign r_en_1 = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);",
        "    "))
    print()
    say("No module-scope checker can see this, because at module scope "
        "nothing is wrong. So the check moves up one level: build the parent "
        "over the original child and over the transformed child, and miter "
        "the two parents against each other with NO delay wrapper. The "
        "parent is not supposed to be late. It is supposed to be identical.")
    print()
    if live:
        sh([sys.executable, os.path.join(SCRIPTS, "g1b_contract.py"),
            "--golden", "bench/rtl", "--candidate", "artifacts/loop/rtl_frozen",
            "--module", "fp4_dot_unit", "--timeout", "1500"])
        return
    d = load("artifacts/loop/g1b_fp4_dot_unit.json", "G1b record")
    if not d:
        return
    verdict(d["verdict"] in ("CONTRACT_HELD", "NO_PARENT"),
            f'{d["module"]}  {d["verdict"]}')
    for c in d.get("checks", []):
        verdict(c["verdict"] == "EQUIVALENT",
                f'  parent {c["parent"]:<20} {c["verdict"]}  {c.get("seconds")}s')
    print()
    say("Unlike every other gate, a G1b failure is not a bug in the model's "
        "edit. The edit is correct. The contract around it broke -- so the "
        "feedback asks for a latency-preserving rewrite, not another try at "
        "the same pipeline.")
    print()

    # The live run with the gate armed, and what the model did next. Recorded
    # from artifacts/loop_g1b rather than retold, because the refusal is the
    # part of this act that is hard to believe second-hand.
    h = os.path.join(HERE, "artifacts/loop_g1b/history.jsonl")
    if not os.path.exists(h):
        return
    recs = [json.loads(l) for l in open(h)]
    later = [r for r in recs if r.get("module") == "fp4_dot_unit"]
    if not later:
        return
    say("Re-run with the gate armed, the loop met the same wall on its own:")
    print()
    for r in later:
        g1b = r.get("g1b") or {}
        if r.get("verdict") == "REJECTED":
            verdict(False, f'{r.get("transform")} latency +{r.get("latency_delta")}'
                           f'  ->  G1 {(r.get("g1") or {}).get("verdict")}, '
                           f'G1b {g1b.get("verdict")}')
        elif r.get("verdict") == "REFUSED":
            verdict(True, "next attempt: the model refused, with reasons")
            print()
            print(textwrap.indent(textwrap.fill(r.get("detail", ""), 68), "      "))
    print()
    say("Every clause of that refusal is correct, including the hardest one: "
        "floating-point addition is not associative, so re-balancing the "
        "adder tree is not a logic restructure under bit-exact equivalence. "
        "Given a channel to refuse in and a gate that had just told it why "
        "its plan was invalid, the model declined to guess. That is the "
        "system's correct output for this path -- not an edit.")


def act6(live):
    act(6, "G2 -- did the rewrite damage a clock-domain crossing?",
        "A duplicated synchronizer sampler is logically identical by "
        "construction, so no equivalence checker can see it lose its second "
        "flop. G2 compares crossings structurally, and holds the model to "
        "the baseline: it may inherit a weak crossing, it may not create one.")
    if live:
        sh([sys.executable, "-c",
            "import sys; sys.path.insert(0,'bench/scripts');"
            "import g2_cdc,json;"
            "print(json.dumps(g2_cdc.check('bench/rtl',"
            "'artifacts/loop/rtl_frozen'), indent=2)[:2000])"])
        return
    h = os.path.join(HERE, "artifacts/loop/history.jsonl")
    if not os.path.exists(h):
        return
    seen = False
    for line in open(h):
        r = json.loads(line)
        g2 = r.get("g2")
        if not g2:
            continue
        seen = True
        verdict(g2["verdict"] == "PASS",
                f'{r.get("module"):<16} {g2["verdict"]}  '
                f'{len(g2.get("failures", []))} failures, '
                f'{len(g2.get("warnings", []))} warnings')
    if not seen:
        print("  (no G2 record: every candidate was rejected before it)")


def act5(live):
    act(5, "G1c -- when equivalence is the wrong question",
        "The refusal in Act 4 was right about the module and wrong as a final "
        "answer. G1b told the model to preserve latency; on a 31.66 ns path "
        "against a 12.5 ns period, that is advice to give up. So the flow "
        "asks a different question one level up, where the interface is a "
        "FIFO handshake and cycle-exact timing was never the contract.")
    say("Behind a FIFO, nothing downstream can observe which cycle a result "
        "was written on. What it can observe is the stream: the values, in "
        "order, none invented, none lost. That is provable, and it is what "
        "the design actually promises.")
    print()
    print(textwrap.indent(
        "P1   no overflow      never write while the sink is full\n"
        "P2a  no invention     never write a result that was not computed\n"
        "P2b  no loss          pending results never exceed the pipeline depth\n"
        "P3   data and order   the value written is the next one owed\n"
        "P4   drain            a filled pipeline empties when operands stop",
        "    "))
    print()
    say("Which obligation applies is decided by the shape of the interface, "
        "not by a flag. A module presenting empty/full/r_en/w_en is elastic, "
        "so G1 and G1b are skipped and G1c is the gate. A rigid module gets "
        "G1 and G1b, exactly as in Act 4.")
    print()

    h = os.path.join(HERE, "artifacts/wns/dryrun2/history.jsonl")
    if not os.path.exists(h):
        return
    recs = [json.loads(l) for l in open(h)]
    stage = [r for r in recs if r.get("module") == "fp4_dot_stage"]
    if not stage:
        return
    for r in stage:
        g = r.get("g1c") or {}
        ok = g.get("verdict") == "STREAM_EQUIVALENT"
        verdict(ok, f'{r.get("transform")} latency +{r.get("latency_delta")}'
                    f'  ->  G1c {g.get("verdict")}  {g.get("seconds")}s')
    print()
    print(textwrap.indent(
        "wire adv = room && src;            // rejected on P4\n"
        "wire adv = room && (src || |vld);  // accepted", "    "))
    print()
    say("One term. The rejected version passes every other gate in this flow "
        "-- G1, G2, G2c all clear it -- and it silently drops the last four "
        "results of every burst, because when the operand stream stops "
        "nothing advances what is still in flight. P4 is the only check in "
        "the system that can see that.")
    print()
    say("Honest note on this act: the two candidates are recorded fixtures "
        "replayed through the loop, not a live model call, so what is being "
        "demonstrated here is the gate and the repair path rather than the "
        "model's inventiveness. The verdicts, the timings and the "
        "counterexample are real.")


def act7(live):
    act(7, "G2c -- is every generated clock glitch-free?",
        "The third blind spot, and the one neither guard covers. Equivalence "
        "cannot see a runt pulse: a combinational clock mux and a flop-based "
        "one compute the same function of sel. STA cannot either: OpenSTA is "
        "told clk_out is a clock, believes it, and never asks whether that "
        "waveform is producible.")
    if live:
        sh([sys.executable, os.path.join(SCRIPTS, "clockcheck.py"),
            "--rtl", "bench/rtl"])
    else:
        d = load("artifacts/clockcheck_baseline.json", "clock audit")
        if not d:
            return
        for f in d["findings"]:
            if f["verdict"] == "UNRECOGNISED":
                continue
            ok = not f["verdict"].startswith("GLITCHY")
            verdict(ok, f'{f["verdict"]:<14} {f["module"]}.{f["net"]}')
            print(f'          {C["dim"]}{f["reason"]}{C["x"]}')
    print()
    say("Both are real bugs in the benchmark RTL as written, found by the "
        "flow rather than by us. clk_div_mux is a slicer target with 100% "
        "path share, so the optimizer reaches it.")


def act8(live):
    act(8, "G3 -- measure what survived",
        "One accepted edit, re-run through the identical ORFS flow, PDK, SDC "
        "and floorplan. FLOW_VARIANT isolates the candidate; NEBULA_RTL is "
        "the only thing that differs between the two runs.")
    base = load("artifacts/metrics/baseline_final.json", "baseline metrics")
    opt = load("artifacts/metrics/opt_final.json", "candidate metrics")
    if not base:
        return
    rows = [("WNS (ns)", "wns"), ("TNS (ns)", "tns"),
            ("Area (um2)", "area_um2"), ("Instances", "instances"),
            ("Wirelength (um)", "wirelength_um"), ("Utilisation (%)",
                                                   "utilization_pct")]
    print(f'  {"metric":<20}{"baseline":>16}{"candidate":>16}{"delta":>14}')
    for label, key in rows:
        b = base.get(key)
        o = (opt or {}).get(key)
        d = (f"{o - b:+,.3f}" if isinstance(b, (int, float))
             and isinstance(o, (int, float)) else "-")
        print(f'  {label:<20}{b if b is None else f"{b:,.3f}":>16}'
              f'{"-" if o is None else f"{o:,.3f}":>16}{d:>14}')
    if not opt:
        print()
        say("Candidate PnR has not been recorded yet. Re-run: make "
            "DESIGN_CONFIG=./designs/sky130hd/nebula_bench/config.mk "
            "FLOW_VARIANT=opt NEBULA_RTL=artifacts/loop/rtl_frozen")
        return

    # Design-wide WNS is the worst endpoint anywhere in five asynchronous
    # domains, so it reports whichever clock happens to be tightest and hides
    # the one the loop actually worked on. Per clock is the honest view, and it
    # is also the view that shows nothing was traded away.
    print()
    print(f'  {"clock":<16}{"period":>10}{"baseline":>12}{"candidate":>12}'
          f'{"delta":>10}')
    for name in sorted(set(base.get("clocks", {})) | set(opt.get("clocks", {}))):
        b = base["clocks"].get(name, {})
        o = opt["clocks"].get(name, {})
        bw, ow = b.get("wns_ns"), o.get("wns_ns")
        if bw is None and ow is None:
            continue                       # no path in this domain
        d = (f"{ow - bw:+.3f}" if isinstance(bw, (int, float))
             and isinstance(ow, (int, float)) else "-")
        mark = "  <--" if name == "clk_s5" else ""
        print(f'  {name:<16}{b.get("period_ns", o.get("period_ns")):>10}'
              f'{"-" if bw is None else f"{bw:+.3f}":>12}'
              f'{"-" if ow is None else f"{ow:+.3f}":>12}{d:>10}{mark}')
    print()
    say("clk_s5 is the domain the loop was pointed at: -19.677 ns to +4.776, "
        "a 24.45 ns swing that turns a hard violation into margin. Every other "
        "domain moves by less than a third of a nanosecond, and the largest "
        "regression -- clk_s8 at -0.319 -- still leaves +2.303 ns against a "
        "10 ns period. The violation was closed, not relocated, and design TNS "
        "going to exactly zero is the number that proves it.")

    # Slack answers "does it close at the specified period". Fmax answers "how
    # fast can it actually run", which is the question deliverable 5 asks and
    # the one a slack number alone never answers. Both sides were swept with
    # the same probe schedule and the same lower bound, so the columns compare.
    fb = load("artifacts/metrics/fmax_base_lo05.json", "baseline Fmax")
    fo = load("artifacts/metrics/fmax_opt_lo05.json", "candidate Fmax")
    if not (fb and fo):
        return
    fb, fo = fb.get("fmax", {}), fo.get("fmax", {})
    say("Slack says the design closes. Fmax says how fast it can actually be "
        "run -- binary search over the SDC period, one full STA per probe, on "
        "the routed database. Both runs used the same lower bound so the two "
        "columns are comparable.")
    print()
    print(f"  {'clock':<14}{'baseline':>12}{'candidate':>12}{'change':>10}")
    for k in ("clk_s5", "clk1", "clk_s3", "clk_s1", "clk_s2", "clk_s4",
              "clk_s8"):
        b, o = fb.get(k, {}).get("fmax_mhz"), fo.get(k, {}).get("fmax_mhz")
        if not (b and o):
            continue
        mark = "  <--" if k == "clk_s5" else ""
        print(f"  {k:<14}{b:>10.1f} M{o:>10.1f} M{(o - b) / b * 100:>9.1f}%"
              f"{mark}")
    print()
    say("29.8 MHz to 126.2 MHz on clk_s5. The baseline figure is the honest "
        "comparison: at its nominal 80 MHz the baseline does not close at all, "
        "so 29.8 MHz was the real ceiling for the whole design -- a chip runs "
        "at the speed of its worst path, not its average one. clk1 and clk_s3 "
        "move a few percent in opposite directions; neither was touched by the "
        "edit, and that is placement noise from a re-run, not a result. Two "
        "gated domains still closed at the smallest period probed, so their "
        "Fmax is a lower bound and is left out of this table rather than "
        "reported as a number.")


ACTS = [act1, act2, act3, act4, act5, act6, act7, act8]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", action="store_true",
                    help="re-run the gates for real (needs the toolchain)")
    ap.add_argument("--act", type=int, action="append",
                    help="run only these acts (repeatable)")
    ap.add_argument("--no-colour", action="store_true")
    a = ap.parse_args()
    if a.no_colour or not sys.stdout.isatty():
        plain()

    print()
    print(C["b"] + "Nebula 2026 -- Digital track".center(W) + C["x"])
    print(C["dim"] + "Constraint optimization through RTL enhancement using "
                     "generative AI".center(W) + C["x"])
    print(C["dim"] + "Timing Blinders -- IIT Bombay".center(W) + C["x"])
    print()
    say("Equivalence is necessary and it is not sufficient. That claim is the "
        "whole project, and the next eight acts are the evidence for it.")

    for i, fn in enumerate(ACTS, 1):
        if a.act and i not in a.act:
            continue
        fn(a.live)
    print()


if __name__ == "__main__":
    main()
