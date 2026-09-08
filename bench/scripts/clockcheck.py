#!/usr/bin/env python3
"""
clockcheck.py -- is every generated clock in this design glitch-free?

The third blind spot, after the two the flow already covers.

Equivalence checking cannot see it. A combinational clock mux and a
flop-based one compute the same function of `sel`; they differ only in what
the waveform does *between* the cycles the solver samples, and a SAT-based
miter has no notion of a runt pulse. Both structures are equivalent, and one
of them silently destroys the chip.

STA cannot see it either. OpenSTA is told `clk_out` is a clock, believes it,
and reports timing against a clean idealised waveform. The tool is not wrong;
it was never asked whether the waveform is producible.

So it needs its own check, structural and cheap, and this design turns out to
contain two textbook instances of it.

**Combinational clock mux** (`clk_div_mux.v`):

    always @(*)
        case(sel)
            2'b00: clk_out = clk;
            2'b01: clk_out = clk_div2;
            ...

`sel` changing while the selected clock is high truncates that pulse and may
start the next one early. A pulse shorter than the library's minimum width is
not a slow clock edge -- it is a flop that captures metastable data or misses
the cycle entirely, anywhere in the fanout. The safe form registers `sel` in
each source domain and gates each branch so a switch can only take effect
while both the outgoing and incoming clocks are low.

**Bare AND clock gating** (`clk_gate.v`):

    assign clk_out = clk_in & clk_en ;

`clk_en` rising or falling while `clk_in` is high chops the pulse. The safe
form is the standard integrated clock gate: latch `clk_en` on the low phase,
then AND the latched enable with the clock, so the enable can only change
while the clock is already low.

    always @(*) if (!clk_in) en_lat = clk_en;
    assign clk_out = clk_in & en_lat;

What this checker does NOT claim: it is structural, and a structural check
recognises the shapes it knows. A hand-built gate in a form it has not been
taught reads as unsafe, and the report says `UNRECOGNISED` rather than
`GLITCHY` for anything it cannot classify either way. Recognising a safe form
is a proof of nothing; failing to recognise one is a prompt to look.

Two modes:

    audit      every clock-producing structure in a tree, classified.
               This is the mode that found the two bugs above.
    regression a candidate may not degrade a structure the golden had safe.
               This is the mode the loop runs, alongside G2.

Usage:
    clockcheck.py --rtl bench/rtl --json
    clockcheck.py --golden bench/rtl --candidate artifacts/loop/rtl
"""
import argparse, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hierarchy as H                                     # noqa: E402
import g2_cdc as G2                                       # noqa: E402
import transforms as T                                    # noqa: E402

# A name is not evidence, but on a clock net it is the strongest hint there is,
# and every clock in this design is named for what it is. Anchored at the
# start on purpose: a substring match anywhere in the name pulls in data buses
# like `data_out_clk2`, which is a 32-bit FIFO output and not a clock, and one
# false clock net turns the whole audit into noise.
CLOCKISH = re.compile(r"^(clk|clock|gclk|sclk)", re.I)

# ...and these are the names that start like a clock and are not one. An
# enable or a select is what *gates* a clock; counting it as a clock source
# turns every clock gate in the design into a two-source "mux".
NOT_A_CLOCK = re.compile(r"(_en|_enable|_sel|_gate|_valid|_req)$", re.I)


def clock_nets(body, ports):
    """
    Signals this module treats as clocks.

    Three sources, because no single one is complete. A net used in a
    `posedge`/`negedge` is a clock by construction. An output whose name says
    clock is a clock the module *produces*, and that is the interesting case
    here -- `clk_div_mux` drives `clk_out` and never clocks anything with it,
    so an edge-only scan misses the module entirely. Inputs named for clocks
    are included so a mux between them is recognisable as a mux between
    clocks.
    """
    nets = set()
    for m in re.finditer(r"\b(?:pos|neg)edge\s+([A-Za-z_][\w$]*)", body):
        nets.add(m.group(1))

    # A clock is one bit wide. That single test is what separates the real
    # clock nets from everything else whose name happens to start with "clk":
    # `soc_top` holds `clkcfg_rdata`, `clk_config_reg` and `clk_en_reg`, all
    # clock-*configuration* registers, all buses, and a name-only rule reports
    # the AXI read mux over them as a glitchy clock mux.
    wide = set()
    for m in re.finditer(r"\b(?:input|output|inout|wire|reg|logic)\b"
                         r"(?:\s+(?:reg|wire|signed))?\s*\[[^\]]*\]\s*"
                         r"([A-Za-z_][\w$,\s]*);?", body):
        wide |= {x.strip() for x in m.group(1).split(",") if x.strip()}

    # Internal nets, not only ports. `clk_div_mux` selects between `clk` and
    # three internal `clk_div2/4/8` wires; restricted to ports, the mux looks
    # like a single-source assignment and the bug is invisible.
    for name in G2.idents(body) | set(ports):
        if (CLOCKISH.match(name) and not NOT_A_CLOCK.search(name)
                and name not in wide
                and "[" not in ports.get(name, "")):
            nets.add(name)
    return nets


def comb_drivers(body):
    """
    {lhs: rhs} for continuous assigns and combinational always blocks only.

    Sequential drivers are deliberately excluded: a clock produced by a flop
    -- a divider, a registered mux output -- is glitch-free by construction,
    because a flop output changes only on an edge of its own clock and cannot
    produce a fragment of a pulse.
    """
    out = {}
    for m in re.finditer(
            r"\bassign\s+([A-Za-z_][\w$]*)\s*(?:\[[^\]]*\])*\s*=\s*([^;]*);", body):
        out.setdefault(m.group(1), []).append(m.group(2).strip())

    # Combinational always blocks: everything `always @(*)` or `always @(a or b)`
    # with no edge in the sensitivity list.
    for m in re.finditer(r"always\s*@\s*\(([^)]*)\)", body):
        if re.search(r"\b(?:pos|neg)edge\b", m.group(1)):
            continue
        rest = body[m.end():]
        bm = re.match(r"\s*begin\b", rest)
        if not bm:
            text = rest[:rest.find(";") + 1]
        else:
            depth, text = 0, ""
            tok = re.compile(r"\b(begin|case|casez|casex|end|endcase)\b")
            for t in tok.finditer(body, m.end()):
                w = t.group(1)
                depth += 1 if w in ("begin", "case", "casez", "casex") else -1
                if depth == 0:
                    text = body[m.end():t.end()]
                    break
        for lhs, rhs in G2.assignments(text):
            out.setdefault(lhs, []).append(rhs.strip())
    return out


def latched_enable(body, enable):
    """
    True when `enable` is the output of a low-phase latch -- the ICG shape.

    Recognises `always @(*) if (!clk) en_lat = en;` and its `~clk` spelling,
    which is the one structure that makes an AND-gated clock safe.
    """
    return bool(re.search(
        rf"always\s*@\s*\([^)]*\)\s*(?:begin\s*)?if\s*\(\s*[!~]\s*[A-Za-z_][\w$]*\s*\)"
        rf"\s*{re.escape(enable)}\s*<?=", body))


def classify(module, body, ports):
    """
    Every combinationally-driven clock net in this module, with a verdict.

    SAFE_ICG        AND of a clock and a low-phase-latched enable
    GLITCHY_MUX     combinational select among two or more clock sources
    GLITCHY_GATE    clock ANDed with an enable that is not latched
    UNRECOGNISED    combinationally driven, shape not known to this checker
    """
    nets = clock_nets(body, ports)
    drivers = comb_drivers(body)
    findings = []
    for net in sorted(nets):
        rhss = drivers.get(net)
        if not rhss:
            continue                     # sequential or a bare input: fine
        srcs = set()
        for rhs in rhss:
            srcs |= {s for s in G2.idents(rhs) if s in nets and s != net}
        detail = "; ".join(r[:80] for r in rhss[:4])

        if len(srcs) >= 2:
            v = "GLITCHY_MUX"
            why = (f"{net} is selected combinationally among "
                   f"{', '.join(sorted(srcs))}; a select change mid-pulse "
                   f"truncates it")
        elif len(srcs) == 1 and any("&" in r or "&&" in r for r in rhss):
            clk = next(iter(srcs))
            ens = set()
            for rhs in rhss:
                ens |= G2.idents(rhs) - {clk}
            if ens and all(latched_enable(body, e) for e in ens):
                v, why = "SAFE_ICG", (f"{net} = {clk} & latched enable "
                                      f"({', '.join(sorted(ens))})")
            else:
                v = "GLITCHY_GATE"
                why = (f"{net} = {clk} & {', '.join(sorted(ens)) or '?'} with "
                       f"no low-phase latch on the enable; an enable change "
                       f"while {clk} is high chops the pulse")
        else:
            v = "UNRECOGNISED"
            why = (f"{net} is driven by combinational logic in a shape this "
                   f"checker does not classify")
        findings.append({"module": module, "net": net, "verdict": v,
                         "sources": sorted(srcs), "driver": detail,
                         "reason": why})
    return findings


def audit(rtl_dir):
    mods = H.load_modules(rtl_dir)
    out = []
    for name in sorted(mods):
        body = mods[name]["body"]
        out += classify(name, body, T.ports(body))
    bad = [f for f in out if f["verdict"].startswith("GLITCHY")]
    return {"rtl": rtl_dir, "findings": out,
            "glitchy": len(bad),
            "verdict": "GLITCH_RISK" if bad else "CLEAN"}


def regression(golden_dir, candidate_dir):
    """
    A transform may not make a clock structure worse.

    Same stance as G2's crossing check and for the same reason: this design's
    baseline already contains two glitchy structures, and a gate that failed
    every candidate for a bug the candidate did not introduce would be turned
    off within a day. Inherited findings are reported as warnings and named as
    inherited; only a net that was safe and is no longer fails.
    """
    g = {(f["module"], f["net"]): f for f in audit(golden_dir)["findings"]}
    c = {(f["module"], f["net"]): f for f in audit(candidate_dir)["findings"]}
    fails, warns = [], []
    for k, f in sorted(c.items()):
        base = g.get(k)
        if f["verdict"].startswith("GLITCHY"):
            if base is None or not base["verdict"].startswith("GLITCHY"):
                fails.append(f"{k[0]}: {f['reason']}")
            else:
                warns.append(f"{k[0]}: {f['reason']} (inherited from baseline)")
    for k, f in sorted(g.items()):
        if k not in c and f["verdict"] == "SAFE_ICG":
            fails.append(f"{k[0]}: safe clock gate on {k[1]} disappeared")
    return {"verdict": "FAIL" if fails else "PASS",
            "failures": fails, "warnings": warns}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rtl", help="audit mode: classify every clock structure")
    ap.add_argument("--golden")
    ap.add_argument("--candidate")
    ap.add_argument("--out")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    if a.rtl:
        res = audit(a.rtl)
    elif a.golden and a.candidate:
        res = regression(a.golden, a.candidate)
    else:
        raise SystemExit("need --rtl, or --golden with --candidate")

    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(json.dumps(res, indent=2) + "\n")
    if a.json:
        print(json.dumps(res, indent=2))
    else:
        print(res["verdict"])
        for f in res.get("findings", []):
            if f["verdict"] != "UNRECOGNISED":
                print(f'  {f["verdict"]:<14} {f["module"]}.{f["net"]}')
                print(f'      {f["reason"]}')
        for f in res.get("failures", []):
            print("  FAIL", f)
        for w in res.get("warnings", []):
            print("  warn", w)
    sys.exit(0 if res["verdict"] in ("CLEAN", "PASS") else 1)


if __name__ == "__main__":
    main()
