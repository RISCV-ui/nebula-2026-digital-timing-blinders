#!/usr/bin/env python3
"""
cdc_classify.py -- what protocol is this multi-bit crossing relying on?

G2 can prove a one-bit crossing has two flops and no logic between them. On a
*bus* it can only warn, and it says so honestly: "multi-bit; gray or handshake
encoding assumed, not proven". Two flops per bit is not a synchronizer for a
bus -- the bits resolve independently, so a value in flight can be sampled as a
combination that never existed on the source side. What makes a bus crossing
safe is the encoding around it, and an encoding is not a structure a
depth-counting checker can recognise.

So this tool classifies the encoding, and it does so in two layers with a hard
line between them.

**Structural evidence (sound, no model).** Gray coding leaves a signature: a
value XORed with itself shifted right by one, or a Johnson/one-hot counter with
a single-bit update rule. A handshake leaves `req`/`ack`/`valid`/`ready` pairs
crossing in opposite directions. A dual-clock FIFO leaves an instantiation. Any
of these is reported as `structural` and is worth what the pattern is worth.

**Model classification (advisory, never a verdict).** Where the structure is
not one of the shapes above, the surrounding RTL is handed to a model and the
answer is recorded as `advisory: true`. This never gates anything and never
appears in a pass/fail line.

That split is deliberate and it is the opposite of how the model is used
everywhere else in this flow. An LLM proposes edits and formal tools judge
them; here the model is judging, so its answer cannot be trusted as a proof.
A model that says "this is gray-coded" has produced a hypothesis for a human to
check, not a guarantee -- and a CDC bug that a model waved through is exactly
the failure mode this whole project argues against. The output format enforces
it: an advisory classification carries no verdict field at all.

Usage:
    cdc_classify.py --rtl bench/rtl --out artifacts/cdc_classes.json
    cdc_classify.py --rtl bench/rtl --backend gemini:gemini-flash
"""
import argparse, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import g2_cdc as G2                                       # noqa: E402
import hierarchy as H                                     # noqa: E402
import llm as LLM                                         # noqa: E402

SYSTEM = """You classify clock-domain-crossing schemes in Verilog RTL.

You are given one multi-bit signal that crosses from one clock domain to
another, and the source of the module it crosses in. Say which protection
scheme, if any, the crossing relies on.

Answer with JSON only:
{"scheme": "gray" | "handshake" | "fifo" | "mux_recirculate" | "none" | "unclear",
 "confidence": "high" | "medium" | "low",
 "evidence": "<the specific lines or signals that made you say so>",
 "risk": "<what breaks if you are wrong, in one sentence>"}

Rules:
- "gray" only if consecutive values differ in exactly one bit BY CONSTRUCTION,
  not merely because a counter happens to increment.
- "none" is a real and useful answer. A bus crossing with two flops per bit and
  no encoding is unsafe, and saying so is more valuable than guessing a scheme.
- "unclear" if the module source does not contain enough to tell. Do not invent
  a scheme from the signal's name.
"""

# Both spellings of a binary-to-gray conversion. `x ^ (x >> 1)` is the
# textbook one; `x ^ {1'b0, x[msb:1]}` is the one this design actually uses,
# and a checker that only knows the first reports the FIFO's gray-coded
# pointers as unclassified -- which is worse than useless, because it sends a
# crossing that IS protected off to a model to guess about.
GRAY = re.compile(
    r"\b([A-Za-z_][\w$]*)\s*\^\s*"
    r"(?:\(\s*\1\s*>>\s*1\s*\)"
    r"|\{\s*1'b0\s*,\s*\1\s*\[[^\]]*:\s*1\s*\]\s*\})")
HANDSHAKE = re.compile(r"\b\w*(req|ack|valid|ready)\w*\b", re.I)
FIFO_INST = re.compile(r"^\s*\w*fifo\w*\s+(?:#\s*\([^;]*\)\s*)?[A-Za-z_][\w$]*\s*\(",
                       re.M | re.I)


def structural(signal, body):
    """
    A scheme this can recognise from the source, with the evidence for it.

    Returns None when nothing matches -- which is the case that goes to the
    model, labelled advisory.
    """
    # Look at the driver of *this* signal, not at any gray conversion anywhere
    # in the module: a FIFO holds two counters and only one of them may be
    # encoded, and crediting the wrong one is exactly the mistake this gate
    # exists to prevent.
    drv = re.search(rf"\bassign\s+{re.escape(signal)}\s*"
                    rf"(?:\[[^\]]*\])?\s*=\s*([^;]*);", body)
    if drv:
        m = GRAY.search(drv.group(1))
        if m:
            return {"scheme": "gray", "basis": "structural",
                    "evidence": f"{signal} = {m.group(0).strip()} -- value "
                                f"XORed with itself shifted right one, which "
                                f"is the binary-to-gray encoding",
                    "confidence": "high"}
    if FIFO_INST.search(body):
        return {"scheme": "fifo", "basis": "structural",
                "evidence": "a dual-clock FIFO is instantiated in this module",
                "confidence": "medium"}
    hs = sorted({m.group(0) for m in HANDSHAKE.finditer(body)})
    if len(hs) >= 2:
        return {"scheme": "handshake", "basis": "structural",
                "evidence": f"handshake-shaped signals present: "
                            f"{', '.join(hs[:6])}",
                "confidence": "low"}
    return None


def classify(rtl_dir, backend=None):
    mods = H.load_modules(rtl_dir)
    res = G2.check(rtl_dir, rtl_dir)
    out = []
    for name, rec in sorted(res.get("crossings", {}).items()):
        body = mods[name]["body"]
        for x in rec["golden"]:
            if not x.get("multibit"):
                continue
            item = {"module": name, "signal": x["signal"],
                    "src": x["src"], "dst": x["dst"],
                    "sync_depth": x["sync_depth"]}
            st = structural(x["signal"], body)
            if st:
                item.update(st)
            elif backend:
                user = (f"TARGET SIGNAL: {x['signal']}\n"
                        f"crosses from {'/'.join(x['src'])} to {x['dst']}\n"
                        f"synchronizer depth: {x['sync_depth']}\n\n"
                        f"MODULE {name}:\n{body[:12000]}")
                try:
                    raw = backend.propose(SYSTEM, user)
                    d = LLM.extract_json(raw) or {}
                except LLM.BackendUnavailable as e:
                    d = {"scheme": "unclear", "evidence": f"backend down: {e}"}
                d["basis"] = "model"
                d["advisory"] = True
                item.update(d)
            else:
                item.update(scheme="unclear", basis="none",
                            evidence="no structural pattern matched and no "
                                     "model backend was given")
            out.append(item)
    return {"rtl": rtl_dir, "multibit_crossings": len(out), "crossings": out,
            "note": "Advisory. A model classification is a hypothesis for a "
                    "human to check, never a proof, and nothing here gates "
                    "the optimisation loop."}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rtl", required=True)
    ap.add_argument("--backend", default=None,
                    help="e.g. gemini:gemini-flash; omitted = structural only")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    b = LLM.get(a.backend) if a.backend else None
    d = classify(a.rtl, b)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(json.dumps(d, indent=2) + "\n")
    for c in d["crossings"]:
        tag = "advisory" if c.get("advisory") else c.get("basis", "-")
        print(f'  {c["module"]}.{c["signal"]:<18} '
              f'{"/".join(c["src"])} -> {c["dst"]:<8} '
              f'{c.get("scheme","?"):<10} [{tag}] '
              f'{c.get("confidence","-")}')
        print(f'      {c.get("evidence","")[:100]}')
    print(f'\n{d["note"]}')


if __name__ == "__main__":
    main()
