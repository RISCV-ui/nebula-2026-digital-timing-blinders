#!/usr/bin/env python3
"""
bakeoff.py -- run the same loop against many models and lay the results side by side.

The deliverable asks for a comparison across open-source models and then
against paid Claude. The comparison is only worth reading if every arm is
handed exactly the same problem, so this drives `loop.py` with identical
targets, identical gates, identical budgets, and changes one thing: `--backend`.

Each arm gets its own output directory, and inside it its own `rtl/` tree. The
frozen input RTL is never written to by anything here -- `loop.py` copies it
and edits the copy -- so at the end there is one original and one optimised
tree per model, which is the shape the organisers asked for:

    bench/rtl                      <- frozen input, never edited
    artifacts/bakeoff/qwen-free/rtl  <- what Qwen produced
    artifacts/bakeoff/r1-free/rtl    <- what R1 produced
    artifacts/bakeoff/opus-direct/rtl

What gets compared is not "who wrote prettier Verilog". Every arm's proposals
went through the same gate chain, so the interesting number is *where each
model dies*: a model that refuses to answer, one that proposes a transform
that fails structural validation, and one that gets all the way to G1 and is
caught by a counterexample are three different kinds of bad, and averaging
them into one score would hide exactly the finding worth reporting.

Model slugs drift as providers add and retire variants, and a wrong slug comes
back from OpenRouter as a 404 rather than a useful error. `--probe` checks
every arm against OpenRouter's published model list before any run starts, so
a typo costs a second instead of surfacing three arms into an overnight sweep.

    bakeoff.py --probe --arms openrouter:qwen-free openrouter:r1-free
    bakeoff.py --targets artifacts/paths/targets.json \\
               --arms openrouter:qwen-free openrouter:deepseek-free \\
                      gemini:gemini-flash anthropic:opus-direct
"""

import argparse, json, os, shutil, subprocess, sys, time, urllib.request
from collections import Counter, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import llm as LLM

OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"

# The order gates fire in. A record's `stage` is where the proposal died, so
# ordering the columns this way makes each arm's row read left to right as
# "how far did this model get before something stopped it".
STAGES = ["backend", "propose", "memo", "validate", "audit",
          "g1", "g1b", "g1c", "g2", "g2c", "accepted"]


def probe(arms):
    """
    Ask OpenRouter which models exist, and check every openrouter: arm against
    that list. Gemini and Anthropic arms are left alone -- they are not routed
    through OpenRouter and their ids are stable.

    This needs no key: the model list is public. That is deliberate, because
    the whole point is to catch a typo *before* anyone spends a key on it.
    """
    want = OrderedDict()
    for spec in arms:
        provider, alias = spec.split(":", 1)
        want[spec] = (provider, LLM.MODELS.get(alias, alias))

    try:
        with urllib.request.urlopen(OPENROUTER_MODELS_URL, timeout=30) as r:
            known = {m["id"] for m in json.load(r)["data"]}
    except Exception as e:
        print(f"could not reach OpenRouter's model list ({e}); "
              f"skipping validation", file=sys.stderr)
        known = None

    ok = True
    for spec, (provider, model) in want.items():
        if provider != "openrouter":
            print(f"  --      {spec:34s} {model}   (not routed via OpenRouter)")
            continue
        if known is None:
            print(f"  ?       {spec:34s} {model}")
        elif model in known:
            print(f"  ok      {spec:34s} {model}")
        else:
            ok = False
            near = sorted(k for k in known
                          if k.split("/")[-1].split(":")[0][:8]
                          == model.split("/")[-1].split(":")[0][:8])[:4]
            print(f"  MISSING {spec:34s} {model}"
                  + (f"\n              did you mean: {', '.join(near)}" if near else ""))
    return ok


def run_arm(spec, args):
    """One loop run. Returns the arm's summary, whether it succeeded or not."""
    out = os.path.join(args.out, spec.replace(":", "_").replace("/", "_"))
    if os.path.exists(out) and args.fresh:
        shutil.rmtree(out)
    cmd = [sys.executable, os.path.join(HERE, "loop.py"),
           "--targets", args.targets, "--rtl", args.rtl, "--out", out,
           "--backend", spec, "--max-targets", str(args.max_targets),
           "--retries", str(args.retries)]
    if args.clock:
        cmd += ["--clock", args.clock]
    cmd += args.loop_arg

    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True)
    wall = time.time() - t0

    log = os.path.join(out, "loop.log")
    os.makedirs(out, exist_ok=True)
    with open(log, "w") as fh:
        fh.write(p.stdout + p.stderr)

    return summarise(spec, out, wall, p.returncode, args.rtl)


def _accepted_audit(recs, out, golden):
    """Identify historical accepts that changed nothing or missed the target."""
    current = golden
    valid, invalid = [], []
    for r in recs:
        if r.get("verdict") != "ACCEPTED":
            continue
        cand = os.path.join(out, f"cand_{r.get('iteration')}_{r.get('attempt')}")
        reasons = []
        actual = (r.get("proposal_module") or
                  (r.get("g1") or {}).get("module"))
        if actual and actual != r.get("module"):
            reasons.append(f"target {r.get('module')} but rewrote {actual}")
        if os.path.isdir(current) and os.path.isdir(cand):
            d = diff_tree(current, cand)
            if not any(d[k] for k in ("changed", "added", "removed")):
                reasons.append("no RTL bytes changed")
        if reasons:
            invalid.append({"iteration": r.get("iteration"),
                            "attempt": r.get("attempt"),
                            "reasons": reasons})
        else:
            valid.append(r)
        # Reconstruct what the historical loop actually carried forward even
        # when the acceptance is invalid, so the next comparison is faithful.
        if os.path.isdir(cand):
            current = cand
    return valid, invalid


def summarise(spec, out, wall, rc, golden=None):
    """
    Read one arm's history and reduce it to the row that goes in the table.

    Deliberately not a single score. `died_at` counts proposals by the gate
    that stopped them, because "refused to answer" and "answered and was
    formally disproved" are opposite failures and a mean would erase both.
    """
    hist = os.path.join(out, "history.jsonl")
    recs = []
    if os.path.exists(hist):
        with open(hist) as fh:
            for ln in fh:
                ln = ln.strip()
                if ln:
                    try:
                        recs.append(json.loads(ln))
                    except json.JSONDecodeError:
                        pass

    died = Counter(r.get("stage", "?") for r in recs)
    raw_accepted = [r for r in recs if r.get("verdict") == "ACCEPTED"]
    accepted, invalid = ((raw_accepted, []) if not golden else
                         _accepted_audit(recs, out, golden))
    if invalid:
        died["accepted"] -= len(invalid)
        died["audit"] += len(invalid)

    # First-attempt accepts say something the total does not: whether the model
    # got it right unaided, or only after a gate handed back a rejection to
    # quote at it. The retry path is a feature of the harness, not of the model.
    first_try = [r for r in accepted if r.get("attempt", 0) == 0]

    return {
        "arm": spec,
        "out": out,
        "rtl": os.path.join(out, "rtl"),
        "returncode": rc,
        "wall_seconds": round(wall, 1),
        "proposals": len(recs),
        "accepted": len(accepted),
        "raw_accepted": len(raw_accepted),
        "invalid_accepts": invalid,
        "accepted_first_attempt": len(first_try),
        "accept_rate": round(len(accepted) / len(recs), 3) if recs else None,
        "died_at": {s: died.get(s, 0) for s in STAGES if died.get(s)},
        "transforms": dict(Counter(r.get("transform") for r in accepted
                                   if r.get("transform")).most_common()),
        "modules_changed": sorted({r["module"] for r in accepted
                                   if r.get("module")}),
    }


def diff_tree(golden, cand):
    """Which files the arm actually changed, relative to the frozen input."""
    if not os.path.isdir(cand):
        return {"changed": [], "added": [], "note": "no rtl tree produced"}
    g = {f for f in os.listdir(golden) if f.endswith(".v")}
    c = {f for f in os.listdir(cand) if f.endswith(".v")}
    changed = [f for f in sorted(g & c)
               if open(os.path.join(golden, f), "rb").read()
               != open(os.path.join(cand, f), "rb").read()]
    return {"changed": changed, "added": sorted(c - g), "removed": sorted(g - c)}


def markdown(rows, golden):
    L = ["| model | proposals | accepted | 1st try | accept rate | wall s | died at |",
         "|---|---|---|---|---|---|---|"]
    for r in rows:
        died = ", ".join(f"{k} {v}" for k, v in r["died_at"].items()
                         if k != "accepted") or "--"
        L.append(f"| `{r['arm']}` | {r['proposals']} | {r['accepted']} | "
                 f"{r['accepted_first_attempt']} | "
                 f"{r['accept_rate'] if r['accept_rate'] is not None else '--'} | "
                 f"{r['wall_seconds']} | {died} |")
    L += ["", f"Frozen input RTL: `{golden}` (never written to).", "",
          "| model | optimised RTL | files changed | files added |",
          "|---|---|---|---|"]
    for r in rows:
        d = r["tree_diff"]
        L.append(f"| `{r['arm']}` | `{r['rtl']}` | "
                 f"{', '.join(f'`{x}`' for x in d['changed']) or '--'} | "
                 f"{', '.join(f'`{x}`' for x in d['added']) or '--'} |")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arms", nargs="+", required=True,
                    help="backend specs, e.g. openrouter:qwen-free")
    ap.add_argument("--targets", help="slicer --out JSON (required unless --probe)")
    ap.add_argument("--rtl", default="bench/rtl", help="frozen input RTL")
    ap.add_argument("--out", default="artifacts/bakeoff")
    ap.add_argument("--max-targets", type=int, default=4)
    ap.add_argument("--retries", type=int, default=2)
    ap.add_argument("--clock", default=None)
    ap.add_argument("--fresh", action="store_true",
                    help="delete an arm's directory before re-running it")
    ap.add_argument("--probe", action="store_true",
                    help="validate model ids and exit, without running anything")
    ap.add_argument("--loop-arg", action="append", default=[],
                    help="extra flag passed through to loop.py")
    a = ap.parse_args()

    for spec in a.arms:
        if spec != "mock" and ":" not in spec:
            sys.exit(f"arm {spec!r} must be mock or <provider>:<model>")

    if a.probe:
        return 0 if probe([s for s in a.arms if s != "mock"]) else 1

    if not a.targets:
        sys.exit("--targets is required unless --probe")

    # Probe first regardless. A run that dies on arm three because of a typo in
    # arm three's slug has wasted every arm before it.
    if not probe([s for s in a.arms if s != "mock"]):
        sys.exit("fix the model ids above, or pass --probe to inspect them")

    os.makedirs(a.out, exist_ok=True)
    rows = []
    for i, spec in enumerate(a.arms, 1):
        print(f"\n=== arm {i}/{len(a.arms)}: {spec} ===", flush=True)
        r = run_arm(spec, a)
        r["tree_diff"] = diff_tree(a.rtl, r["rtl"])
        rows.append(r)
        print(f"    {r['accepted']}/{r['proposals']} accepted "
              f"in {r['wall_seconds']}s -> {r['rtl']}", flush=True)

    report = {"golden": a.rtl, "targets": a.targets,
              "max_targets": a.max_targets, "retries": a.retries,
              "arms": rows}
    with open(os.path.join(a.out, "bakeoff.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    md = markdown(rows, a.rtl)
    with open(os.path.join(a.out, "bakeoff.md"), "w") as fh:
        fh.write(md + "\n")

    print("\n" + md)
    print(f"\nwrote {a.out}/bakeoff.json and {a.out}/bakeoff.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
