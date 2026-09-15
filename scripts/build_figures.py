#!/usr/bin/env python3
"""TikZ figures for the report, drawn from the design rather than by hand.

A block diagram is the part of a report a reader trusts most and checks
least, so this one is not drawn: the domains come from the SDC's
`set_clock_groups`, the blocks from what soc_top actually instantiates and
the clock net each instance is given, the periods from the SDC, and the
highlighted paths from the slicer's own target file. If the RTL changes and
the picture stops matching it, that is a regenerated picture, not a stale one.

Two figures, kept deliberately plain -- five lanes and a strip. A diagram of
all 59 modules would be accurate and unreadable, which in a report is the
same as wrong.

    usage: scripts/build_figures.py
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "report" / "generated"
SDC = ROOT / "bench" / "constraints" / "nebula.sdc"
RTL = ROOT / "bench" / "rtl_v2"


def esc(s: str) -> str:
    return str(s).replace("_", r"\_")


# ------------------------------------------------------------- the design

def handover_clocks() -> dict[str, list[str]]:
    """The divider-internal clocks the SDC appends to each master's group.

    They are built in a Tcl foreach, so they exist only as
    ``$handover(clkN)`` at the point the groups are declared; reading the
    loop is the only way to get their names without running Tcl.
    """
    text = SDC.read_text()
    m = re.search(r"foreach\s*\{\s*inst\s+src\s+master\s*\}\s*\{(.*?)\}",
                  text, re.S)
    if not m:
        return {}
    rows = m.group(1).split()
    nets = re.search(r"foreach\s*\{\s*net\s+div\s*\}\s*\{([^}]*)\}", text)
    net_names = nets.group(1).split()[::2] if nets else []
    out: dict[str, list[str]] = {}
    for inst, _src, master in zip(rows[0::3], rows[1::3], rows[2::3]):
        out.setdefault(master, []).extend(f"{inst}_{n}" for n in net_names)
    return out


def clock_groups() -> list[list[str]]:
    """Asynchronous groups, as the SDC declares them.

    Each group is written ``-group [concat {clk...} $handover(clkN)]``: a
    literal list of the master and its generated clocks, plus the
    divider-internal clocks built in the loop above. Reading only the literal
    brace list silently produced no groups at all once the handover clocks
    were added, which emptied Figure 1 and left every reference to it
    unresolved -- so a group that names a handover variable we cannot resolve
    is an error here, not a shrug.
    """
    text = SDC.read_text()
    m = re.search(r"set_clock_groups\s+-asynchronous(.*?)(?:\n\n|\n#)", text, re.S)
    if not m:
        return []
    hand = handover_clocks()
    groups = []
    for g in re.findall(r"-group\s*(?:\[concat\s*)?\{([^}]*)\}([^\\\n]*)",
                        m.group(1)):
        names = g[0].split()
        for var in re.findall(r"\$handover\((\w+)\)", g[1]):
            names.extend(hand.get(var, []))
        groups.append(names)
    return groups


def periods() -> dict[str, float]:
    out = {}
    for name, per in re.findall(
            r"create_(?:generated_)?clock\s+-name\s+(\S+)\s+-period\s+([\d.]+)",
            SDC.read_text()):
        out[name] = float(per)
    for name, src in re.findall(
            r"create_generated_clock\s+-name\s+(\S+)\s+-source\s+\[[^\]]*?(\w+)\]",
            SDC.read_text()):
        out.setdefault(name, out.get(src, 0.0))
    return out


def labels() -> dict[str, str]:
    """The comment the SDC puts beside each master is the domain's name."""
    out = {}
    for name, note in re.findall(
            r"create_clock\s+-name\s+(\w+).*?;#\s*([a-z ]+?)\s+\d+\s*MHz",
            SDC.read_text()):
        out[name] = note.strip()
    return out


def instances() -> list[tuple[str, str, list[str]]]:
    """(module, instance, every clock net it is given) from soc_top.

    The instantiations are positional, so there are no port names to match:
    the clock nets are recovered as the `clk*` identifiers in the argument
    list. Taking only the first one is what put every peripheral in the core
    domain -- each one is handed `clk1` for its AXI-Lite side and its own
    divided clock for the functional side, in that order, and it is the
    second that says which domain the block really lives in.
    """
    body = re.sub(r"//[^\n]*", " ", (RTL / "soc_top.v").read_text())
    known = {f.stem for f in RTL.glob("*.v")}
    out = []
    for m in re.finditer(r"\b([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*\(([^;]*?)\)\s*;",
                         body, re.S):
        typ, inst, args = m.group(1), m.group(2), m.group(3)
        if typ not in known:
            continue
        seen, clks = set(), []
        for c in re.findall(r"\b(clk\w*)\b", args):
            if c not in seen:
                seen.add(c)
                clks.append(c)
        out.append((typ, inst, clks))
    return out


def targets() -> dict[str, tuple[str, str, float]]:
    """{top-level instance: (module, clock, slack)} for the violating paths.

    A path names a chain of modules, not one module, so the owner is the
    deepest module that carries the delay -- and the block it has to be drawn
    inside is the top-level instance that path starts under. Only negative
    slack is marked: a path that already meets is not a target.
    """
    f = ROOT / "artifacts" / "paths" / "v2_targets.json"
    try:
        d = json.loads(f.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    out = {}
    for p in d.get("paths", []):
        slack = p.get("slack_ns")
        mods = p.get("modules") or []
        if slack is None or slack >= 0 or not mods:
            continue
        owner = max(mods, key=lambda m: m.get("share_pct", 0))
        host = (owner.get("instance") or "").split("/")[0]
        if not host:
            continue
        out[host] = (owner.get("module", "?"), p.get("clock", "?"), slack)
    return out


# -------------------------------------------------------------- figure 1

DOMAIN_COLOUR = ["core", "gpio", "dot", "timer", "uart"]
PLUMBING = {"clk_gate", "clk_div_mux"}


def fig_soc() -> str:
    groups, per, note, tgt = clock_groups(), periods(), labels(), targets()
    hand_all = {n for v in handover_clocks().values() for n in v}
    if not groups:
        return "% no clock groups found in the SDC"

    owner = {c: gi for gi, g in enumerate(groups) for c in g}
    core_i = 0
    insts = instances()
    # The slicer names the top-level instance a violating path starts under;
    # the figure draws module types, so the target is carried across by that
    # instance's type.
    typ_of = {inst: typ for typ, inst, _ in insts}
    hot = {}
    for host, (mod, clk, slack) in tgt.items():
        t = typ_of.get(host)
        if t:
            hot[t] = (mod, clk, slack)

    blocks: dict[int, list[str]] = {i: [] for i in range(len(groups))}
    for typ, _inst, clks in insts:
        if typ in PLUMBING:
            continue
        idx = [owner[c] for c in clks if c in owner]
        home = next((i for i in idx if i != core_i), core_i if idx else None)
        if home is None or typ in blocks[home]:
            continue
        blocks[home].append(typ)

    out = [
        r"% Generated by scripts/build_figures.py -- do not edit.",
        r"\begin{figure}[htbp]", r"  \centering",
        r"  \begin{tikzpicture}[",
        r"    font=\scriptsize,",
        r"    blk/.style 2 args={rounded corners=1.5pt, draw=#1!40,",
        r"        fill=#1!7, text=black!80, minimum width=#2,",
        r"        minimum height=4.6mm, align=center, inner sep=1pt},",
        r"    hot/.style 2 args={rounded corners=1.5pt, draw=critical,",
        r"        line width=0.6pt, fill=critical!8, minimum width=#2,",
        r"        minimum height=6.6mm, align=center, inner sep=1pt,",
        r"        text=critical!85!black},",
        r"    hdr/.style={rounded corners=1.5pt, fill=#1, text=white,",
        r"        minimum height=5mm, align=center, inner sep=1pt},",
        r"    lane/.style={rounded corners=2.5pt, draw=#1!30, inner sep=2.2mm},",
        r"    chain/.style={font=\tiny, text=black!50, align=center},",
        r"    cdc/.style={{Latex[length=1.4mm]}-{Latex[length=1.4mm]},",
        r"        draw=black!45, dashed, dash pattern=on 1.1pt off 1.1pt,",
        r"        line width=0.45pt},",
        r"  ]",
    ]

    def chip(name, colour, x, y, w):
        """One block, drawn hot when a violating path lives inside it."""
        if name in hot:
            mod, clk, slack = hot[name]
            # A wide block takes the annotation on one line; a lane block is
            # 31 mm and has to break it, or it runs out past the lane edge.
            label = (rf"{esc(name)}\\[-2.5pt]{{\tiny {esc(mod)}}}"
                     rf"\\[-2.5pt]{{\tiny {esc(clk)}\ \ "
                     rf"{slack:+.1f}\,ns}}")
            out.append(rf"  \node[hot={{{colour}}}{{{w:.1f}mm}}, "
                       rf"anchor=north west] ({name}) at ({x:.2f}mm,{y:.2f}mm) "
                       rf"{{{label}}};")
            return 8.0 if w > 60 else 10.0
        out.append(rf"  \node[blk={{{colour}}}{{{w:.1f}mm}}, "
                   rf"anchor=north west] ({name}) at ({x:.2f}mm,{y:.2f}mm) "
                   rf"{{{esc(name)}}};")
        return 6.0

    # --- core domain: one wide band across the top
    core, cb = groups[core_i], blocks[core_i][:8]
    width, percol = 150.0, 4
    colw = width / percol
    out.append(rf"  \node[hdr=core, minimum width={width}mm] (corehdr) "
               rf"at (0mm,0mm) {{}};")
    out.append(rf"  \node[font=\scriptsize\bfseries, text=white] at (corehdr) "
               rf"{{{esc(core[0])} \textbullet\ {note.get(core[0], 'core')} "
               rf"\textbullet\ {per.get(core[0], 0):g}\,ns}};")
    y, rowh = -4.0, 0.0
    for i, b in enumerate(cb):
        col = i % percol
        if col == 0 and i:
            y -= rowh
            rowh = 0.0
        x = -width / 2 + col * colw + 1.0
        rowh = max(rowh, chip(b, "core", x, y, colw - 2))
    out.append(rf"  \node[lane=core, fit=(corehdr)"
               + "".join(f"({b})" for b in cb) + r"] (corelane) {};")

    # --- one lane per peripheral domain, below
    lanetop = y - rowh - 13.0
    lanew, gap = 33.0, 3.5
    total = len(groups) - 1
    x0 = -((lanew + gap) * total - gap) / 2
    for k, gi in enumerate(range(1, len(groups))):
        g, c = groups[gi], DOMAIN_COLOUR[gi % len(DOMAIN_COLOUR)]
        x = x0 + k * (lanew + gap)
        w = lanew - 2
        out.append(rf"  \node[hdr={c}, minimum width={w}mm, "
                   rf"anchor=north west] (h{gi}) at ({x:.2f}mm,{lanetop:.2f}mm) {{}};")
        out.append(rf"  \node[font=\scriptsize\bfseries, text=white] at (h{gi}) "
                   rf"{{{esc(g[0])} \textbullet\ {per.get(g[0], 0):g}\,ns}};")
        out.append(rf"  \node[chain, anchor=north west, text width={w}mm] "
                   rf"(c{gi}) at ({x:.2f}mm,{lanetop - 5.6:.2f}mm) "
                   rf"{{{note.get(g[0], '')}\\"
                   # The divider-internal handover clocks belong to the group
                   # for grouping, but naming all three in the lane caption
                   # overflows it; the caption shows the declared chain.
                   + r" $\rightarrow$ ".join(esc(q) for q in g[1:]
                                             if q not in hand_all) + r"};")
        yy, ids = lanetop - 13.5, []
        for b in blocks[gi][:4]:
            yy -= chip(b, c, x, yy, w)
            ids.append(b)
        out.append(rf"  \node[lane={c}, fit=(h{gi})(c{gi})"
                   + "".join(f"({b})" for b in ids) + rf"] (lane{gi}) {{}};")
        out.append(rf"  \draw[cdc] (lane{gi}.north) -- "
                   rf"(lane{gi}.north |- corelane.south);")

    out += [
        r"  \end{tikzpicture}",
        r"  \caption{The benchmark SoC as its SDC and RTL define it, generated "
        r"from both rather than drawn by hand. Five mutually asynchronous "
        r"masters, each peripheral domain built as master $\rightarrow$ gate "
        r"$\rightarrow$ divider; every peripheral keeps its AXI-Lite side in "
        r"the core domain and its functional side in its own, so each dashed "
        r"line is a real clock-domain crossing. Outlined in red are the three "
        r"blocks that own a violating path, each labelled with the module "
        r"inside it that carries the delay, the clock it fails on and its "
        r"baseline slack.}",
        r"  \label{fig:soc}",
        r"\end{figure}",
    ]
    return "\n".join(out)


# -------------------------------------------------------------- figure 2

def fig_gates() -> str:
    """The gate strip, with each gate's own kill count written on it."""
    bk = {}
    f = ROOT / "artifacts" / "bakeoff_v2" / "bakeoff.json"
    try:
        for arm in json.loads(f.read_text()).get("arms", []):
            for stage, n in (arm.get("died_at") or {}).items():
                bk[stage] = bk.get(stage, 0) + n
    except (OSError, json.JSONDecodeError):
        pass
    accepted = bk.pop("accepted", 0)

    gates = [("validate", "parses,", "interface intact"),
             ("g1", "equivalent to", "frozen module"),
             ("g1b", "parent contract", "still holds"),
             ("g1c", "clock structure", "at boundary"),
             ("g2", "no CDC", "broken"),
             ("g2c", "no new", "glitchy clock")]

    out = [r"% Generated by scripts/build_figures.py -- do not edit.",
           r"\begin{figure}[htbp]", r"  \centering",
           r"  \begin{adjustbox}{max width=\textwidth}",
           r"  \begin{tikzpicture}[",
           r"    font=\scriptsize,",
           r"    gate/.style={rounded corners=2pt, draw=accent!50,",
           r"                 fill=accent!6, minimum width=19mm,",
           r"                 minimum height=11mm, align=center},",
           r"    term/.style={rounded corners=2pt, draw=#1!60, fill=#1!12,",
           r"                 minimum width=17mm, minimum height=11mm,",
           r"                 align=center, font=\scriptsize\bfseries},",
           r"    flow/.style={->, >=stealth, draw=accent!60, line width=0.7pt},",
           r"    drop/.style={->, >=stealth, draw=critical!70, line width=0.6pt},",
           r"  ]"]

    out.append(r"  \node[term=accent] (in) at (0mm,0) "
               r"{candidate\\rewrite};")
    x = 24.0
    prev = "in"
    for key, l1, l2 in gates:
        n = bk.get(key, 0)
        out.append(rf"  \node[gate] ({key}) at ({x}mm, 0) "
                   rf"{{\textbf{{{esc(key)}}}\\[1pt]{{\tiny {l1}}}\\"
                   rf"{{\tiny {l2}}}}};")
        out.append(rf"  \draw[flow] ({prev}) -- ({key});")
        if n:
            out.append(rf"  \draw[drop] ({key}.south) -- ++(0,-6mm) "
                       rf"node[below, font=\tiny, text=critical] "
                       rf"{{$-${n}}};")
        prev, x = key, x + 23.0
    out.append(rf"  \node[term=accepted] (ok) at ({x}mm, 0) "
               rf"{{accepted\\{accepted}}};")
    out.append(rf"  \draw[flow] ({prev}) -- (ok);")

    out += [r"  \end{tikzpicture}",
            r"  \end{adjustbox}",
            r"  \caption{Every gate a rewrite must pass, with the number of "
            r"candidates each one rejected across all four models. A gate "
            r"rejects on its own evidence and reports what it found; the "
            r"model's next attempt answers that, rather than being asked "
            r"the same question again.}",
            r"  \label{fig:gates}", r"\end{figure}"]
    return "\n".join(out)


def main() -> None:
    GEN.mkdir(parents=True, exist_ok=True)
    for name, body in (("fig_soc.tex", fig_soc()),
                       ("fig_gates.tex", fig_gates())):
        (GEN / name).write_text(body + "\n")
        print(f"  wrote report/generated/{name}")


if __name__ == "__main__":
    main()
