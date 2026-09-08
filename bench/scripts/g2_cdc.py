#!/usr/bin/env python3
"""
Gate 2: clock-domain-crossing safety.

Gate 1 proves the candidate RTL computes the same function as the golden RTL.
That is not enough, and the benchmark design shows exactly why. The worst
path in this SoC starts and ends inside `asynchronous_fifo_gen`, a two-clock
FIFO. The obvious way to shorten a path that ends on a flop is to add another
flop in front of it -- and if that flop lands on a synchronizer stage, the
result is still formally equivalent to the original, because equivalence is a
statement about logic, not about metastability. The FIFO would pass Gate 1
and fail in silicon.

So Gate 2 asks a different question: does the candidate still cross clock
domains the same way the golden did? It is a structural check, not a proof,
and it says so. Four things are checked:

  1. NO-TOUCH.        Modules that own a crossing are compared byte for byte.
                      A transform may instantiate them; it may not edit them.
  2. No new crossing.  Every (signal, source domain, destination domain) in
                      the candidate must already exist in the golden.
  3. Synchronizer depth >= 2 on every crossing that is synchronized at all.
  4. No logic between synchronizer stages. Each stage must be a bare copy of
                      the previous one; `s2 <= s1 & en;` re-opens the
                      metastability window that s2 exists to close.

What it deliberately does not claim: that an unsynchronized multi-bit
crossing is wrong. Gray-coded pointers and handshake protocols are both
legitimate and neither is provable from the syntax. Those are reported as
WARN, and a WARN does not fail the gate.
"""
import argparse, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hierarchy as H
from transforms import CDC_MODULES

KEYWORDS = {
    "if", "else", "begin", "end", "case", "endcase", "default", "posedge",
    "negedge", "or", "and", "not", "xor", "assign", "always", "wire", "reg",
    "logic", "integer", "for", "while", "repeat", "function", "endfunction",
    "task", "endtask", "b0", "b1", "d0", "d1", "h0",
}
IDENT = re.compile(r"\b([A-Za-z_][\w$]*)\b")
BARE = re.compile(r"^\s*([A-Za-z_][\w$]*)\s*(?:\[[^\]]*\])?\s*$")


def idents(text):
    return {m.group(1) for m in IDENT.finditer(text)
            if m.group(1) not in KEYWORDS and not m.group(1)[0].isdigit()}


def blocks(body):
    """
    [(clock, text)] for every edge-triggered always block.

    The body is scanned brace-free: Verilog nests with begin/end, so the block
    is taken from the sensitivity list to the matching end at depth zero. A
    block with no begin (a one-statement always) runs to the first semicolon.
    """
    out = []
    for m in re.finditer(r"always\s*@\s*\(([^)]*)\)", body):
        sens = m.group(1)
        e = re.search(r"\b(?:pos|neg)edge\s+([A-Za-z_][\w$]*)", sens)
        if not e:
            continue                      # combinational always, not a domain
        i = m.end()
        rest = body[i:]
        bm = re.match(r"\s*begin\b", rest)
        if not bm:
            out.append((e.group(1), rest[:rest.find(";") + 1]))
            continue
        # Scan from the start of `rest`, not from inside the opening `begin`.
        # Starting mid-token loses that first begin, so the depth counter
        # reaches zero at the first nested `end` and the block is cut short --
        # which on this FIFO dropped the entire else branch, i.e. both of the
        # crossings the gate exists to find.
        depth, j = 0, i
        tok = re.compile(r"\b(begin|case|casez|casex|end|endcase)\b")
        for t in tok.finditer(body, j):
            w = t.group(1)
            if w in ("begin", "case", "casez", "casex"):
                depth += 1
            else:
                depth -= 1
                if depth == 0:
                    out.append((e.group(1), body[i:t.end()]))
                    break
    return out


def assignments(text):
    """[(lhs_name, rhs_text)] for every blocking or non-blocking assignment."""
    out = []
    # The operator must be `=` or `<=` and not the tail of a comparison.
    # Without the lookaround, `w_en == 1'b1 && ... mem[..] <= data_in;` parses
    # as one assignment whose right-hand side swallows the real one, and the
    # crossing hidden inside it is never seen.
    for m in re.finditer(
            r"([A-Za-z_][\w$]*)\s*(?:\[[^\]]*\])*\s*(?<![=!<>])<?=(?!=)\s*([^;]*);",
            text):
        out.append((m.group(1), m.group(2)))
    return out


def domains(body):
    """
    {signal: {clocks it is produced under}}.

    Sequential assignments seed the map; continuous assigns then propagate it
    to a fixed point, so `assign counter_1_gray = counter_1 ^ ...` puts the
    gray code in clk_1's domain without it ever appearing on a flop LHS.
    """
    dom = {}
    for clk, text in blocks(body):
        for lhs, _ in assignments(text):
            dom.setdefault(lhs, set()).add(clk)
    conts = [(m.group(1), m.group(2)) for m in
             re.finditer(r"\bassign\s+([A-Za-z_][\w$]*)\s*(?:\[[^\]]*\])*\s*=\s*([^;]*);",
                         body)]
    for _ in range(len(conts) + 1):
        changed = False
        for lhs, rhs in conts:
            src = set()
            for s in idents(rhs):
                src |= dom.get(s, set())
            if src - dom.get(lhs, set()):
                dom.setdefault(lhs, set()).update(src)
                changed = True
        if not changed:
            break
    return dom


def sync_chain(clk, text, first_stage):
    """
    Length of the bare flop chain starting at first_stage, and whether every
    stage is a plain copy. `s1 <= src; s2 <= s1;` is depth 2 and clean;
    `s2 <= s1 | flush;` is depth 2 and dirty.
    """
    pairs = assignments(text)
    depth, clean, cur = 1, True, first_stage
    for _ in range(8):
        nxt = None
        for lhs, rhs in pairs:
            if lhs == cur:
                continue
            if cur in idents(rhs):
                nxt = lhs
                if not BARE.match(rhs):
                    clean = False
                break
        if nxt is None:
            break
        depth += 1
        cur = nxt
    return depth, clean


def crossings(body):
    """
    [{signal, src, dst, sync_depth, clean, width_multibit}] for one module.

    A crossing is a signal read inside a block on clock D when every clock
    that produces it is something other than D. Reset signals are skipped:
    an async reset is a crossing by construction and is handled by reset
    synchronisation, which is not what this gate is about.
    """
    dom = domains(body)
    widths = {m.group(2): bool(m.group(1)) for m in
              re.finditer(r"\b(?:reg|wire)\s*(\[[^\]]*\])?\s*([A-Za-z_][\w$]*)",
                          body)}
    found = []
    for clk, text in blocks(body):
        lhs_here = {l for l, _ in assignments(text)}
        for lhs, rhs in assignments(text):
            for s in idents(rhs):
                src = dom.get(s, set())
                if not src or clk in src or s == clk:
                    continue
                if re.search(r"rst|reset", s, re.I):
                    continue
                if s in lhs_here and src == {clk}:
                    continue
                d, clean = sync_chain(clk, text, lhs)
                found.append({
                    "signal": s, "src": sorted(src), "dst": clk,
                    "first_stage": lhs, "sync_depth": d, "clean": clean,
                    "multibit": widths.get(s, False),
                })
    # Keyed on the receiving flop as well as the signal, because two flops
    # sampling the same asynchronous signal is a different circuit from one
    # flop sampling it, even though the two are logically identical and no
    # equivalence check can tell them apart. Each sampler can resolve
    # metastability the other way on the same edge, so the duplicated pair
    # disagree and the reader sees a value the writer never sent.
    uniq = {}
    for c in found:
        uniq[(c["signal"], tuple(c["src"]), c["dst"], c["first_stage"])] = c
    return sorted(uniq.values(),
                  key=lambda c: (c["dst"], c["signal"], c["first_stage"]))


def check(golden_dir, candidate_dir, edited_module=None):
    g = H.load_modules(golden_dir)
    c = H.load_modules(candidate_dir)
    fails, warns, report = [], [], {}

    # 1. NO-TOUCH
    for m in sorted(CDC_MODULES):
        if m not in c:
            fails.append(f"NO-TOUCH module {m} deleted from candidate")
        elif m not in g:
            fails.append(f"NO-TOUCH module {m} absent from golden")
        elif re.sub(r"\s+", " ", g[m]["body"]) != re.sub(r"\s+", " ", c[m]["body"]):
            fails.append(f"NO-TOUCH module {m} was edited")

    # 2-4. crossing comparison over every module present in both
    for name in sorted(set(g) & set(c)):
        if edited_module and name != edited_module and name not in CDC_MODULES:
            if re.sub(r"\s+", " ", g[name]["body"]) == \
               re.sub(r"\s+", " ", c[name]["body"]):
                continue
        gc = crossings(g[name]["body"])
        cc = crossings(c[name]["body"])
        if not gc and not cc:
            continue
        gkeys = {(x["signal"], tuple(x["src"]), x["dst"], x["first_stage"]) for x in gc}
        report[name] = {"golden": gc, "candidate": cc}
        gmap = {(x["signal"], tuple(x["src"]), x["dst"], x["first_stage"]): x for x in gc}
        for x in cc:
            k = (x["signal"], tuple(x["src"]), x["dst"], x["first_stage"])
            base = gmap.get(k)
            if base is None:
                fails.append(
                    f"{name}: new crossing {x['signal']} "
                    f"{'/'.join(x['src'])} -> {x['dst']}")
                if x["sync_depth"] < 2:
                    fails.append(
                        f"{name}: new crossing {x['signal']} -> {x['dst']} "
                        f"has synchronizer depth {x['sync_depth']}, need >= 2")
                elif not x["clean"]:
                    fails.append(
                        f"{name}: logic between synchronizer stages on new "
                        f"crossing {x['signal']} -> {x['dst']}")
            else:
                # This gate is a regression check, not an audit of the
                # baseline. soc_top already crosses mem_hit from clk_s8 into
                # clk1 through a single flop, into a debug XOR accumulator
                # that drives no control. That is the design's own choice and
                # failing every candidate for it would make the gate useless.
                # What a transform may not do is make a crossing worse.
                if x["sync_depth"] < base["sync_depth"]:
                    fails.append(
                        f"{name}: crossing {x['signal']} -> {x['dst']} "
                        f"synchronizer depth cut "
                        f"{base['sync_depth']} -> {x['sync_depth']}")
                if base["clean"] and not x["clean"]:
                    fails.append(
                        f"{name}: logic inserted between synchronizer stages "
                        f"on {x['signal']} -> {x['dst']}")
                if base["sync_depth"] < 2:
                    warns.append(
                        f"{name}: {x['signal']} -> {x['dst']} crosses on "
                        f"{base['sync_depth']} flop in the baseline too; "
                        f"inherited, not caused by this transform")
            if x["multibit"]:
                warns.append(
                    f"{name}: {x['signal']} -> {x['dst']} is multi-bit; "
                    f"gray or handshake encoding assumed, not proven")
        ckeys = {(y["signal"], tuple(y["src"]), y["dst"], y["first_stage"])
                 for y in cc}
        for x in gc:
            k = (x["signal"], tuple(x["src"]), x["dst"], x["first_stage"])
            if k not in ckeys:
                fails.append(
                    f"{name}: crossing {x['signal']} "
                    f"{'/'.join(x['src'])} -> {x['dst']} disappeared")

    return {"verdict": "FAIL" if fails else "PASS",
            "failures": fails, "warnings": sorted(set(warns)),
            "crossings": report}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--golden", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--module", help="the module the transform edited")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    r = check(a.golden, a.candidate, a.module)
    if a.json:
        print(json.dumps(r, indent=2))
    else:
        print(f"G2 {r['verdict']}")
        for f in r["failures"]:
            print("  FAIL " + f)
        for w in r["warnings"]:
            print("  warn " + w)
        for m, d in r["crossings"].items():
            for x in d["candidate"]:
                print(f"  {m}: {x['signal']} {'/'.join(x['src'])} -> "
                      f"{x['dst']}  depth {x['sync_depth']}"
                      f"{'' if x['clean'] else '  DIRTY'}")
    sys.exit(1 if r["verdict"] == "FAIL" else 0)


if __name__ == "__main__":
    main()
