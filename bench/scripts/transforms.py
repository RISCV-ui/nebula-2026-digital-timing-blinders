#!/usr/bin/env python3
"""
transforms.py -- the catalog, and the checks a proposal must survive to become
a candidate design.

The catalog is deliberately small. A model asked to "make this faster" answers
with anything; a model asked to pick one of four named transforms and declare
its latency answers with something a script can check. That declaration is the
whole mechanism: the model writes the Verilog, but it must also say which
transform it applied and how many cycles it added, and every later gate tests
that claim rather than trusting it.

  * latency_delta 0 is proven by a plain miter
  * latency_delta N is proven by a miter that delays the golden outputs N flops

A proposal that quietly pipelines while declaring 0 therefore fails G1. It does
not need to be caught here.

What IS caught here is cheap and structural, because a proposal that cannot
possibly be right should never cost a synthesis run:

  1. the module keeps its exact port list -- same names, directions and widths
  2. it still parses
  3. it does not touch a clock-domain-crossing module
  4. a latency-preserving claim did not add a clocked block

Check 4 is a heuristic, not a proof. It is here because it is nearly free and
rejects the most common way a model gets this wrong.
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

RTL_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "rtl"))

# Editing any of these is refused outright. A clock-domain crossing is correct
# by structure -- two flops, a gray-coded pointer, no logic between the stages
# -- and none of that is an equivalence property, so a rewrite that breaks it
# passes formal equivalence and fails in silicon. G2 checks the crossings that
# survive; this list stops the ones we can refuse for free.
CDC_MODULES = {"asynchronous_fifo_gen"}

CATALOG = {
    "logic_restructure": {
        "latency": "preserving",
        "summary": "Rewrite combinational logic into a shallower but "
                   "functionally identical form.",
        "examples": [
            "a priority chain written as a for loop, rewritten as a casez tree",
            "a chain of the same associative operator, rebalanced into a tree",
            "logic pushed ahead of a mux so it evaluates in parallel with the "
            "select",
            "a wide priority mux rebuilt as a balanced mux tree",
        ],
        "rules": [
            "Do not add, remove or move any always @(posedge ...) block.",
            "Outputs must be identical on every cycle, not merely eventually.",
        ],
        "latency_delta": 0,
    },
    "retime": {
        "latency": "preserving",
        "summary": "Move work across an existing register boundary to balance "
                   "two pipeline stages. The register count and the latency "
                   "both stay the same.",
        "examples": [
            "a stage that only latches its inputs, given the first level of "
            "the reduction tree that follows it",
            "a late stage doing an add and a compare, with the add moved back "
            "one stage",
        ],
        "rules": [
            "The number of pipeline stages must not change.",
            "Do not add a register. Move the logic around the ones present.",
            "Every existing output must still appear on the same cycle.",
        ],
        "latency_delta": 0,
    },
    # The fourth technique the problem statement names. It is the only one
    # whose correctness argument is not obvious from the diff: re-encoding
    # changes the bits the state register holds, so the candidate and the
    # golden module disagree about their own state on every cycle and still
    # have to agree about every output. That is exactly what a miter asks --
    # G1 compares outputs, never state bits -- so an encoding change is
    # provable by the gate already in place, with one caveat recorded in
    # bench/DECISIONS.md: an FSM has loops in its state graph, so G1 returns a
    # bounded proof here rather than the complete one it gives feed-forward
    # logic.
    "fsm_encode": {
        "latency": "preserving",
        "summary": "Re-encode a state machine's states -- binary, one-hot or "
                   "gray -- so the next-state and output logic get shallower. "
                   "The set of states, the transitions between them and the "
                   "cycle every output changes on all stay exactly as they "
                   "are; only the bit pattern each state is stored as "
                   "changes.",
        "examples": [
            "a binary-encoded state register whose next-state logic needs a "
            "decoder, re-encoded one-hot so each next-state term becomes a "
            "flat OR of a few state bits with no decode in front of it",
            "a deep output mux selected by a binary state, re-encoded one-hot "
            "so the outputs are driven by an AND-OR of state bits directly",
            "a wide one-hot register that is not on the critical path, "
            "re-encoded binary to give the area back",
            "a state sequence that advances one step at a time, gray-encoded "
            "so one bit toggles per transition",
        ],
        "rules": [
            "The state register's own width may change. Nothing in the port "
            "list may change, including a state output if the module has one.",
            "Do not add, remove, merge or rename a state, and do not change "
            "any transition. This transform re-encodes an FSM; it does not "
            "redesign one.",
            "Every output must be identical on every cycle, starting from "
            "reset. Re-encoding changes how the state is stored, never when "
            "an output moves.",
            "The reset state must still be the reset state, written in the "
            "new encoding.",
            "Do not add an always @(posedge ...) block. A re-encoded FSM has "
            "the same number of clocked blocks as the original.",
            "State the encoding you moved from and to in `reason`, because "
            "one-hot is not automatically faster -- it trades register bits "
            "for logic depth, and that is only a win when the depth is what "
            "is failing.",
        ],
        "latency_delta": 0,
    },
    "pipeline": {
        "latency": "changing",
        "summary": "Insert N register stages inside a long combinational path, "
                   "splitting it into N+1 shorter ones. Outputs appear N "
                   "cycles later than before.",
        "examples": [
            "a three-level adder tree with a register after each level",
            "a multiplier's partial-product reduction split across two cycles",
        ],
        "rules": [
            "Declare N in latency_delta. It must be at least 1.",
            "Every output of the module must shift by the same N cycles. A "
            "module whose outputs move by different amounts is not a pipeline "
            "and cannot be proven.",
            "Any valid/ready/done signal the module carries must be delayed by "
            "the same N stages as the data.",
            "State the parent-module change required, because the parent's "
            "consumers still expect the old timing.",
        ],
        "latency_delta": None,   # supplied by the proposal
    },
    "duplicate_driver": {
        "latency": "preserving",
        "summary": "Split a high-fanout net by duplicating the logic that "
                   "drives it, so each copy drives fewer loads.",
        "examples": [
            "one decoder feeding thirty two consumers, duplicated into two "
            "decoders feeding sixteen each",
        ],
        "rules": [
            "The duplicated logic must be combinational and side-effect free.",
            "Do not add a register.",
        ],
        "latency_delta": 0,
    },
}

# Deliberately absent: FSM re-encoding. Changing a state assignment leaves the
# two designs with no correspondence between their internal states, which is
# exactly the case structural equivalence induction cannot close -- six modules
# on the previous design came back UNPROVEN for this reason. Proving it needs an
# input/output bisimulation, which is not in scope here. The technique is
# reported as future work rather than shipped with a gate that cannot judge it.

PORT_KEYWORDS = ("input", "output", "inout")


def module_source(name, rtl_dir=RTL_DIR):
    """Return (path, source) of the module, or (None, None)."""
    for fn in sorted(os.listdir(rtl_dir)):
        if not fn.endswith(".v"):
            continue
        p = os.path.join(rtl_dir, fn)
        text = open(p, errors="ignore").read()
        m = re.search(r"\bmodule\s+" + re.escape(name) + r"\b.*?\bendmodule\b",
                      text, re.S)
        if m:
            return p, m.group(0)
    return None, None


def ports(src):
    """
    Port name -> "direction width", from both declaration styles this design
    uses: ANSI headers and separate input/output statements.
    """
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", " ", src)
    out = {}
    for m in re.finditer(
            r"\b(input|output|inout)\b\s*(?:reg|wire|logic)?\s*(?:signed\s*)?"
            r"(\[[^\]]*\])?[ \t]*([A-Za-z_][\w$]*(?:[ \t]*,[ \t]*[A-Za-z_][\w$]*)*)",
            src):
        direction, width = m.group(1), (m.group(2) or "").replace(" ", "")
        for nm in m.group(3).split(","):
            nm = nm.strip()
            # A comma list must not run past the end of its own declaration.
            # Restricting the separator to spaces and tabs stops "src_a," from
            # swallowing the "input" that opens the next line, and this guard
            # catches anything the regex still lets through.
            if nm and nm not in ("input", "output", "inout",
                                 "reg", "wire", "logic", "signed"):
                out[nm] = f"{direction} {width}"
    return out


def clocked_blocks(src):
    return len(re.findall(r"always\s*@\s*\(\s*posedge", src))


def parses(src, name):
    """Yosys front end only -- a syntax gate, not elaboration."""
    with tempfile.NamedTemporaryFile("w", suffix=".v", delete=False) as f:
        f.write(src)
        p = f.name
    try:
        r = subprocess.run(["yosys", "-q", "-p", f"read_verilog {p}"],
                           capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(p)
    return r.returncode == 0, (r.stderr or r.stdout)[-1500:]


def instantiators(child, rtl_dir=RTL_DIR):
    """Every module in the tree that instantiates `child`."""
    hits = set()
    for f in sorted(glob.glob(os.path.join(rtl_dir, "*.v"))):
        src = open(f, errors="ignore").read()
        for m in re.finditer(r"^\s*module\s+([A-Za-z_][\w$]*)", src, re.M):
            body = src[m.end():]
            end = body.find("endmodule")
            if end < 0:
                continue
            if re.search(rf"\b{re.escape(child)}\s+"
                         rf"(?:#\s*\([^;]*\)\s*)?[A-Za-z_][\w$]*\s*\(",
                         body[:end]):
                hits.add(m.group(1))
    return hits


def changed_modules(proposal):
    """{name: rtl} for every module this proposal rewrites, target first."""
    out = {proposal["module"]: proposal["rtl"]}
    out.update(proposal.get("submodules") or {})
    return out


def _write_modules(proposal, rtl_dir):
    for name, text in changed_modules(proposal).items():
        path, original = module_source(name, rtl_dir)
        if original is None:
            raise SystemExit(f"{name} not found in {rtl_dir}")
        body = open(path).read()
        open(path, "w").write(body.replace(original, text.strip(), 1))


def validate(proposal, rtl_dir=RTL_DIR):
    """
    proposal = {"transform","module","latency_delta","rtl","reason", ...}
    Returns (ok, [problems]). Problems are written to be handed straight back
    to the model as a repair prompt.
    """
    bad = []
    t = proposal.get("transform")
    mod = proposal.get("module")
    rtl = proposal.get("rtl") or ""
    delta = proposal.get("latency_delta")

    if t not in CATALOG:
        return False, [f"transform must be one of {sorted(CATALOG)}, got {t!r}"]
    spec = CATALOG[t]

    if mod in CDC_MODULES:
        return False, [f"{mod} carries a clock-domain crossing and cannot be "
                       f"edited; target a module on the path that does not"]

    path, original = module_source(mod, rtl_dir)
    if original is None:
        return False, [f"no module named {mod!r} in {rtl_dir}"]

    if not re.search(r"\bmodule\s+" + re.escape(mod) + r"\b", rtl):
        bad.append(f"the rtl field must define module {mod}")
    if "endmodule" not in rtl:
        bad.append("the rtl field must be the complete module, ending in "
                   "endmodule")

    want, got = ports(original), ports(rtl)
    for nm, sig in want.items():
        if nm not in got:
            bad.append(f"port {nm} is missing")
        elif got[nm] != sig:
            bad.append(f"port {nm} was {sig}, proposal has {got[nm]}")
    for nm in got:
        if nm not in want:
            bad.append(f"port {nm} is new; the port list must not change")

    # A transform may need to change a module and the child it wraps in the
    # same breath -- pipelining a combinational unit puts the stage registers
    # inside the child and the valid-shift control in the parent, and neither
    # half is correct alone. So `submodules` is allowed, under one hard rule:
    # a child whose ports change may not be instantiated by anything outside
    # the set being rewritten. Otherwise the edit silently breaks a caller no
    # gate in this flow is looking at.
    subs = proposal.get("submodules") or {}
    if not isinstance(subs, dict):
        bad.append("submodules must be an object of {module name: rtl}")
        subs = {}
    changed = {mod} | set(subs)
    for nm, text in subs.items():
        if nm == mod:
            bad.append(f"{nm} is the target module; put it in `rtl`, not "
                       f"`submodules`")
            continue
        if nm in CDC_MODULES:
            bad.append(f"{nm} carries a clock-domain crossing and cannot be "
                       f"edited")
            continue
        if module_source(nm, rtl_dir)[1] is None:
            bad.append(f"no module named {nm!r} in the design")
            continue
        if not re.search(r"\bmodule\s+" + re.escape(nm) + r"\b", text or ""):
            bad.append(f"submodules[{nm}] must define module {nm}")
        if "endmodule" not in (text or ""):
            bad.append(f"submodules[{nm}] must end in endmodule")
        callers = instantiators(nm, rtl_dir)
        if not callers:
            bad.append(f"{nm} is not instantiated anywhere; it is not part of "
                       f"the module you are rewriting")
        elif callers - changed:
            bad.append(f"{nm} is also instantiated by "
                       f"{', '.join(sorted(callers - changed))}, which you are "
                       f"not rewriting; changing it here would break them")

    if spec["latency"] == "preserving":
        if delta not in (0, None):
            bad.append(f"{t} preserves latency, so latency_delta must be 0")
        if clocked_blocks(rtl) > clocked_blocks(original):
            bad.append(f"{t} preserves latency but the proposal adds a clocked "
                       f"block ({clocked_blocks(original)} -> "
                       f"{clocked_blocks(rtl)})")
    else:
        if not isinstance(delta, int) or delta < 1:
            bad.append(f"{t} changes latency, so latency_delta must be an "
                       f"integer of 1 or more, got {delta!r}")

    if not bad:
        ok, err = parses(rtl, mod)
        if not ok:
            bad.append("the proposal does not parse:\n" + err)

    return (not bad), bad


def splice(proposal, rtl_dir):
    """Swap the proposed module into an existing tree, in place."""
    _write_modules(proposal, rtl_dir)
    return rtl_dir


def apply(proposal, out_dir, rtl_dir=RTL_DIR):
    """
    Copy the RTL tree, swapping the proposed module in. Returns out_dir.

    out_dir and rtl_dir must differ: the copy starts by deleting out_dir, so
    passing the same path for both destroys the source before it is read.
    Folding an accepted edit back into the working tree is `splice`.
    """
    if os.path.abspath(out_dir) == os.path.abspath(rtl_dir):
        raise SystemExit("apply() would delete its own source; use splice()")
    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    shutil.copytree(rtl_dir, out_dir)
    _write_modules(proposal, out_dir)
    return out_dir


def prompt_catalog():
    """The catalog as the model sees it. Stable text, so it caches."""
    out = []
    for name, s in CATALOG.items():
        out.append(f"### {name}  ({s['latency']} latency)")
        out.append(s["summary"])
        out.append("Applies to, for example:")
        out += [f"  - {e}" for e in s["examples"]]
        out.append("Rules:")
        out += [f"  - {r}" for r in s["rules"]]
        out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "catalog":
        print(prompt_catalog())
    elif len(sys.argv) > 1 and sys.argv[1] == "validate":
        p = json.load(open(sys.argv[2]))
        ok, bad = validate(p)
        print("OK" if ok else "REJECTED")
        for b in bad:
            print("  -", b)
        sys.exit(0 if ok else 1)
    else:
        print(__doc__)
        print(f"{len(CATALOG)} transforms: {', '.join(CATALOG)}")
