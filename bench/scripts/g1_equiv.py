#!/usr/bin/env python3
"""
g1_equiv.py -- gate 1: is the rewritten module the same circuit?

Two proofs, because the catalog has two kinds of transform.

Latency-preserving (logic_restructure, retime, duplicate_driver): a plain
miter. Golden and candidate see the same inputs and must agree on every output
on every cycle.

Latency-changing (pipeline): the same miter, but the golden module's outputs
are passed through N flops first, so "identical N cycles later" is what gets
proven. Comparing a pipelined module against its original directly reports a
failure that is real and useless -- of course they differ, that is what the
transform does -- and a gate that always fires teaches nothing.

The proof is bounded, not unbounded: `sat -seq 12` checks the first twelve
cycles out of reset. On the previous design, raising depth from 10 to 20 left
the unproven cell counts identical while multiplying runtime, so the failures
there were not depth-limited and more depth bought nothing. A pass is therefore
"equivalent for twelve cycles from a zero initial state", and the report says
so rather than claiming more.

A timeout is recorded as TIMEOUT, never as a pass. Three verdicts, no fourth:

    EQUIVALENT   proven to the stated depth
    NOT_EQUIVALENT   a counterexample exists
    TIMEOUT / ERROR  nothing was proven

Usage:
    g1_equiv.py --golden bench/rtl --candidate /tmp/cand --module fp8_adder
    g1_equiv.py --golden bench/rtl --candidate /tmp/cand --module fp4_dot_unit \\
                --latency 3 --clock clk
"""

import argparse
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import transforms as T

CLOCK_NAMES = ("clk", "clock", "clk_i", "clk_1", "clk_2", "i_clk")

# Active-high synchronous resets only. The reset-align wrapper drives the port
# as `(rst) || !__started`, which is an assertion; on an active-low port that
# expression releases reset instead of asserting it, so the wrapper would do
# the opposite of its job in silence. A design using rst_n gets no alignment
# and fsm_encode is refused on it rather than proven against the wrong start
# state -- this benchmark is uniformly active-high, so nothing is lost here.
RESET_NAMES = ("rst", "reset", "rst_i", "i_rst", "reset_i")


# Which solver proves which kind of module.
#
# Yosys `sat` is a pure bit-level SAT engine. It closes a boolean miter in
# seconds and it is what every proof in this project used until now, but it
# has no theory of arithmetic: a 32x32 multiply or an FP add gets bit-blasted
# into a flat CNF with no structure left to exploit, and the solver grinds
# until the timeout. That is not a hypothetical -- every one of the four
# `fp4_dot_unit` pipeline proposals in the Opus run came back ERROR from this
# engine, and those were the best proposals any arm produced.
#
# So the engine is picked from what the module is made of:
#
#   simple logic              SAT            fast, and enough
#   multiplier / FP arith     SMTBMC + Bitwuzla   bit-vector theory, not CNF
#   memory / cache            SMTBMC + Bitwuzla   arrays stay arrays
#   FSM / deep sequential     ABC PDR        unbounded, not depth-limited
#
# Overridable with --engine; --engine sat reproduces every earlier verdict.
ENGINE_FOR_CLASS = {
    "simple":     "sat",
    "arith":      "smtbmc",
    "memory":     "smtbmc",
    "sequential": "pdr",
}

# Name fragments that settle the class without looking at the body. A module
# called fp8_adder is FP arithmetic whether or not a `*` appears in it.
ARITH_NAMES = ("mul", "div", "sqrt", "isqrt", "fp4", "fp8", "float", "dot",
               "adder", "add_", "bcd", "alu", "mac", "accum")
MEMORY_NAMES = ("mem", "ram", "rom", "cache", "fifo", "buffer", "regfile",
                "register_file", "queue")
FSM_NAMES = ("fsm", "ctrl", "controller", "arbiter", "sequencer", "master",
             "slave", "state")


def classify(module, golden):
    """
    What kind of circuit is this, for the purpose of picking a solver.

    Deliberately shallow: module name first, then the operators and shapes in
    its own body. It does not walk the hierarchy -- a wrapper around a
    multiplier reads as whatever the wrapper itself is, and the wrapper is what
    the miter flattens anyway. When nothing matches, "simple" keeps the old
    SAT behaviour, so an unclassified module is never made slower or less
    provable than it was before this function existed.
    """
    name = module.lower()
    _, src = T.module_source(module, golden)
    body = src or ""
    # Strip comments so a sentence about multipliers does not classify a
    # module as one.
    body = re.sub(r"//[^\n]*", "", body)
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)

    if any(f in name for f in MEMORY_NAMES):
        return "memory"
    # A packed array of regs is a memory whatever it is called:
    #   reg [31:0] store [0:255];
    if re.search(r"\breg\s*(\[[^\]]+\]\s*)?\w+\s*\[[^\]]+\]\s*;", body):
        return "memory"

    # Arithmetic needs two things to agree: something that looks arithmetic,
    # and arithmetic actually in the body. The name alone is not enough --
    # `alu_src_a_mux` and `clk_div_mux` match "alu" and "div" and are pure
    # muxes that SAT closes in under a second. The body alone is not enough
    # either, because a module whose arithmetic sits in a submodule (v2's
    # `timer` instantiates `mult_array_32`) has no operator of its own; the
    # instance name carries the hint instead, and the miter flattens that
    # submodule in regardless.
    # An instantiated arithmetic submodule is structural evidence and settles
    # it on its own: `fp4_dot_unit` is eight `fp4_mul` feeding three
    # `fp8_adder` and has not one operator of its own, and it is the module
    # SAT could not close.
    inst = re.findall(r"^\s*(\w+)\s+\w+\s*\(", body, re.M)
    kw = {"module", "input", "output", "inout", "wire", "reg", "assign",
          "always", "if", "else", "case", "for", "begin", "end", "function",
          "task", "parameter", "localparam", "generate", "genvar", "initial"}
    if any(f in i.lower() for i in inst if i not in kw for f in ARITH_NAMES):
        return "arith"

    # A name hint on its own is not enough -- `alu_src_a_mux` and
    # `clk_div_mux` match "alu" and "div" and are pure muxes that SAT closes
    # in under a second. It has to be backed by an operator in the body.
    has_arith_op = bool(re.search(r"[\w)\]]\s*[*/%+-]\s*[\w(]", body))
    if any(f in name for f in ARITH_NAMES) and has_arith_op:
        return "arith"
    # A real multiply, divide or modulo in the body settles it on its own.
    # `<<` is not counted: a constant shift is free, and counting it would
    # classify every mux.
    if re.search(r"[\w)\]]\s*[*/%]\s*[\w(]", body):
        return "arith"

    has_ff = "posedge" in body or "negedge" in body
    if has_ff and (any(f in name for f in FSM_NAMES)
                   or re.search(r"\bcase\s*\(\s*\w*state", body, re.I)
                   or re.search(r"\blocalparam\b.*\bS\d|\bSTATE_", body)):
        return "sequential"

    return "simple"


def read_cmds(rtl_dir):
    files = sorted(glob.glob(os.path.join(rtl_dir, "*.v")))
    return "\n".join(f"read_verilog -defer {f}" for f in files)


def delay_wrapper(module, src, n, clock, enable=None, reset=None):
    """
    A copy of the module whose outputs are n flops late. Inputs pass straight
    through, so the wrapper is transparent apart from the shift.

    `enable` and `reset` exist for one shape the plain shift cannot express: a
    stallable pipeline. A candidate that holds its stages when a downstream
    queue is full has an enable port the golden does not, so the port lists
    differ and the miter will not build; and it clears its stages out of reset,
    so a wrapper without a reset disagrees for the first n cycles for a reason
    that has nothing to do with the transform.

    Giving the wrapper the same enable and reset makes the proven statement
    the right one: not "equal n cycles later", but "equal n *enabled* cycles
    later, from the same cleared state". The enable is a free input to the
    miter, so the stall behaviour is proven and not assumed.
    """
    p = T.ports(src)
    ins = {k: v for k, v in p.items() if v.startswith("input")}
    outs = {k: v for k, v in p.items() if v.startswith("output")}
    if clock not in ins:
        raise SystemExit(
            f"{module} has no clock port among {sorted(ins)}; a latency-changing "
            f"transform needs one to delay against")

    def width(sig):
        m = re.search(r"\[([^\]]*)\]", sig)
        return f"[{m.group(1)}] " if m else ""

    extra = [enable] if enable and enable not in ins else []
    L = [f"module __gold_delay_{module}("
         + ", ".join(list(ins) + extra + list(outs)) + ");"]
    for k, v in ins.items():
        L.append(f"    input {width(v)}{k};")
    for k in extra:
        L.append(f"    input {k};")
    for k, v in outs.items():
        L.append(f"    output {width(v)}{k};")
    for k, v in outs.items():
        L.append(f"    wire {width(v)}__raw_{k};")
        for i in range(n):
            L.append(f"    reg {width(v)}__d{i}_{k};")
    L.append(f"    {module} __inner (")
    L.append("        " + ",\n        ".join(
        [f".{k}({k})" for k in ins] + [f".{k}(__raw_{k})" for k in outs]))
    L.append("    );")
    L.append(f"    always @(posedge {clock}) begin")
    ind = "        "
    if reset:
        L.append(f"        if ({reset}) begin")
        for k, v in outs.items():
            for i in range(n):
                L.append(f"            __d{i}_{k} <= 0;")
        L.append("        end")
        L.append(f"        else if ({enable}) begin" if enable
                 else "        else begin")
        ind = "            "
    elif enable:
        L.append(f"        if ({enable}) begin")
        ind = "            "
    for k in outs:
        L.append(f"{ind}__d0_{k} <= __raw_{k};")
        for i in range(1, n):
            L.append(f"{ind}__d{i}_{k} <= __d{i-1}_{k};")
    if reset or enable:
        L.append("        end")
    L.append("    end")
    for k in outs:
        L.append(f"    assign {k} = __d{n-1}_{k};")
    L.append("endmodule")
    return "\n".join(L)


def reset_align_wrapper(module, src, reset, clock, tag):
    """
    A copy of the module that is held in reset for exactly one cycle, with its
    outputs masked while it is.

    This exists for `fsm_encode`, and without it that transform can never pass.
    The miter starts both halves from all-zeros (`-set-init-zero`), and
    all-zeros means different things under different state encodings: a machine
    whose idle state is 2'b01 starts in a code it does not own and is rescued a
    cycle later by its own `default` arm, while the re-encoded machine, whose
    idle is 1'b0, starts legitimately idle. The two disagree on cycle 0 for a
    reason that has nothing to do with the transform being wrong -- measured,
    not assumed: the binary re-encoding of `read_buffer_i_cache` is rejected in
    0.3 s without this wrapper and proved with it.

    Holding reset on cycle 0 puts each machine in *its own* reset state, which
    is what makes the encodings correspond from cycle 1 on. The outputs are
    masked during that cycle because they are combinational from a state
    neither machine has entered yet. Both halves of the miter get the same
    wrapper, so nothing is being assumed about one side that is not assumed
    about the other.
    """
    p = T.ports(src)
    ins = {k: v for k, v in p.items() if v.startswith("input")}
    outs = {k: v for k, v in p.items() if v.startswith("output")}
    for need, what in ((reset, "reset"), (clock, "clock")):
        if need not in ins:
            raise SystemExit(f"{module} has no {what} port named {need!r}; "
                             f"its inputs are {sorted(ins)}")

    def width(sig):
        m = re.search(r"\[([^\]]*)\]", sig)
        return f"[{m.group(1)}] " if m else ""

    name = f"__ra_{tag}_{module}"
    L = [f"module {name}(" + ", ".join(list(ins) + list(outs)) + ");"]
    for k, v in ins.items():
        L.append(f"    input {width(v)}{k};")
    for k, v in outs.items():
        L.append(f"    output {width(v)}{k};")
    # The initialiser is load-bearing. Without it `opt` sees a flop whose D
    # input is a constant 1 and whose init is unset, treats the init as a
    # don't-care, and replaces the whole register with constant 1 -- long
    # before `sat -set-init-zero` ever runs. The reset is then never asserted
    # and the wrapper silently does nothing, which is exactly what it did on
    # the first attempt.
    L.append("    reg __started = 1'b0;")
    for k, v in outs.items():
        L.append(f"    wire {width(v)}__raw_{k};")
    conn = [f".{k}(({reset}) || !__started)" if k == reset else f".{k}({k})"
            for k in ins]
    conn += [f".{k}(__raw_{k})" for k in outs]
    L.append(f"    {module} __inner (")
    L.append("        " + ",\n        ".join(conn))
    L.append("    );")
    L.append(f"    always @(posedge {clock}) __started <= 1'b1;")
    for k in outs:
        L.append(f"    assign {k} = __started ? __raw_{k} : 0;")
    L.append("endmodule")
    return "\n".join(L)


# `memory_map` is what makes a FIFO provable at all. Left as an array, the
# storage stays a $mem_v2 cell and the solver stops with "No SAT model
# available for cell gate.mem ($mem_v2)". Mapping it to flops and decoders
# costs depth * width * 2^logofdepth extra variables, which is the price of
# checking a module whose whole job is storage.
def tie_wrapper(module, src, port):
    """
    A copy of the module with one bit of one input inverted on the way in.

    This is the probe half of the observability check. A bounded proof at
    depth N says "the two halves agree for N cycles from reset", and that
    sentence is worth nothing if no input can reach an output inside N cycles
    -- both halves then sit on their reset values for the whole window and the
    solver reports EQUIVALENT without having compared anything the transform
    touched. On fp4_dot_unit, whose output is four flops behind its inputs,
    depth 4 accepted a deliberately mis-wired retime in 2.6s; depth 5 rejected
    the same file with a counterexample at cycle 5. The verdict flipped on the
    depth alone, so the depth has to be checked, not assumed.

    Inverting a bit is stronger than tying it low: a tie only differs when the
    solver picks a 1 there, while an inversion differs on every vector, so a
    proof that the two still agree is unambiguous evidence that the bit is
    invisible at this depth.
    """
    p = T.ports(src)
    ins = {k: v for k, v in p.items() if v.startswith("input")}
    outs = {k: v for k, v in p.items() if v.startswith("output")}

    def width(sig):
        m = re.search(r"\[([^\]]*)\]", sig)
        return f"[{m.group(1)}] " if m else ""

    L = [f"module __vac_{module}(" + ", ".join(list(ins) + list(outs)) + ");"]
    for k, v in ins.items():
        L.append(f"    input {width(v)}{k};")
    for k, v in outs.items():
        L.append(f"    output {width(v)}{k};")
    conn = [f".{k}({k} ^ 1'b1)" if k == port else f".{k}({k})" for k in ins]
    L.append(f"    {module} __inner (")
    L.append("        " + ",\n        ".join(conn + [f".{k}({k})" for k in outs]))
    L.append("    );")
    L.append("endmodule")
    return "\n".join(L)


def vac_script(golden, module, depth, vac_file):
    """
    Golden against golden-with-one-input-bit-flipped, same depth, same passes.
    A model found means the flip reached an output inside the window, so the
    window observes the inputs; no model found means it did not.
    """
    return f"""
{read_cmds(golden)}
hierarchy -check -top {module}
proc; opt_expr; opt_clean; memory -nomap; memory_map; opt -fast
flatten; opt -fast
rename -top gold
design -stash gold

{read_cmds(golden)}
read_verilog -defer {vac_file}
hierarchy -check -top __vac_{module}
proc; opt_expr; opt_clean; memory -nomap; memory_map; opt -fast
flatten; opt -fast
rename -top gate
design -stash gate

design -copy-from gold -as gold gold
design -copy-from gate -as gate gate
miter -equiv -flatten -make_assert -make_outputs gold gate miter
hierarchy -top miter
opt_expr
opt_merge -share_all
opt -fast
sat -seq {depth} -prove-asserts -set-init-zero -verify miter
"""


def observable(golden, module, depth, timeout, tmp):
    """
    Does any input bit reach an output within `depth` cycles? Returns
    (verdict, port), verdict one of "yes" / "no" / "unknown".

    Ports are tried widest first because a wide data port is the one a
    datapath actually consumes; a narrow control bit can be legitimately
    unused. Three tries, because the answer is the same for every bit that
    shares a cone and paying for more of them buys nothing.
    """
    _, src = T.module_source(module, golden)
    if src is None:
        return "unknown", None
    p = T.ports(src)
    cand = [k for k, v in p.items() if v.startswith("input")
            and k not in CLOCK_NAMES and k not in RESET_NAMES]

    def w(k):
        m = re.search(r"\[\s*(\d+)", p[k])
        return int(m.group(1)) if m else 0
    for port in sorted(cand, key=w, reverse=True)[:3]:
        f = os.path.join(tmp, f"__vac_{port}.v")
        open(f, "w").write(tie_wrapper(module, src, port))
        ysf = os.path.join(tmp, f"vac_{port}.ys")
        open(ysf, "w").write(vac_script(golden, module, depth, f))
        try:
            r = subprocess.run(["yosys", "-s", ysf], capture_output=True,
                               text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            return "unknown", port
        out = r.stdout + r.stderr
        if "SAT proof finished - model found: FAIL" in out:
            return "yes", port
        if r.returncode != 0:
            return "unknown", port
    return "no", None


def script(golden, candidate, module, depth, latency, clock, wrapper_file,
           ra_gold=None, ra_gate=None, engine="sat", artifact=None):
    gold_top = module if not latency else f"__gold_delay_{module}"
    gate_top = module
    extra = f"read_verilog -defer {wrapper_file}" if latency else ""
    # Both halves get the reset-align wrapper or neither does, so the miter
    # still compares like with like.
    extra_gate = ""
    if ra_gold and ra_gate:
        gold_top = f"__ra_gold_{module}"
        gate_top = f"__ra_gate_{module}"
        extra = (extra + "\n" if extra else "") + f"read_verilog -defer {ra_gold}"
        extra_gate = f"read_verilog -defer {ra_gate}"

    # ABC reads an AIGER file whose primary outputs are the properties: it
    # proves every PO is unreachable-high. `-make_outputs` would add the gold
    # and gate data outputs alongside `trigger`, and those are not supposed to
    # be zero, so PDR would report a counterexample on the first cycle any
    # output went high. The SAT and SMT engines read the $assert cells instead
    # and are unaffected by the extra outputs, which are what makes their
    # counterexample tables readable.
    miter_cmd = ("miter -equiv -flatten -make_assert gold gate miter"
                 if engine == "pdr" else
                 "miter -equiv -flatten -make_assert -make_outputs gold gate miter")

    if engine == "sat":
        tail = (f"sat -seq {depth} -prove-asserts -set-init-zero -verify "
                f"-show-inputs -show-outputs miter")
    elif engine == "smtbmc":
        # `setundef -init -zero` is the SMT-side spelling of sat's
        # `-set-init-zero`: without it the gold delay flops start free and the
        # solver reports a cycle-0 mismatch that says nothing about the edit.
        # write_smt2 only understands plain $dff; a flattened design keeps
        # $sdffe (enable + sync reset folded into the cell), which it refuses
        # outright. dffunmap splits those back into a mux feeding a plain
        # flop -- same circuit, a form the back end can encode.
        tail = (f"setundef -undriven -init -zero\n"
                f"dffunmap\n"
                f"write_smt2 -wires -stbv {artifact}")
    elif engine == "pdr":
        # AIGER is narrower still: one clock, no enables, no async reset.
        # AIGER is an and-inverter graph: two gate types and one flop type,
        # all one bit wide. Everything upstream of here is word-level, so the
        # design has to be taken apart before the backend will look at it --
        # dffunmap splits enables and synchronous resets out of the flop,
        # simplemap turns the word-level cells that remain into single-bit
        # ones ($dff -> $_DFF_P_), and aigmap reduces the combinational logic
        # to ANDs and inverters. Miss any of the three and write_aiger stops
        # on the first cell it does not recognise.
        tail = (f"setundef -undriven -init -zero\n"
                f"dffunmap\n"
                f"simplemap\n"
                f"aigmap\n"
                f"write_aiger -zinit {artifact}")
    else:
        raise ValueError(f"unknown engine {engine}")

    return f"""
{read_cmds(golden)}
{extra}
hierarchy -check -top {gold_top}
proc; opt_expr; opt_clean; memory -nomap; memory_map; opt -fast
flatten; opt -fast
rename -top gold
design -stash gold

{read_cmds(candidate)}
{extra_gate}
hierarchy -check -top {gate_top}
proc; opt_expr; opt_clean; memory -nomap; memory_map; opt -fast
flatten; opt -fast
rename -top gate
design -stash gate

design -copy-from gold -as gold gold
design -copy-from gate -as gate gate
{miter_cmd}
hierarchy -top miter

# Both halves of the miter came from the same RTL, so every cell the
# transform did not touch appears twice, structurally identical, driven by
# the same primary inputs. opt_merge collapses those pairs into one copy
# before the solver ever sees them -- on a pipelined dot product that
# deletes eight multipliers and the whole of level 1 from the SAT problem
# and leaves only the logic whose timing actually changed. `opt -fast`
# skips opt_merge, which is why the first attempt at this proof spent
# 1847s and returned nothing.
opt_expr
opt_merge -share_all
# opt -fast, not opt -full: opt_full's opt_share pass aborts on a miter whose
# halves still hold $mem cells, which is every FIFO in this design. opt_merge
# is the pass that does the work here anyway.
opt -fast
{tail}
"""



def summarize(table):
    """
    The half-dozen lines of a counterexample that are worth sending back.

    `sat` prints the reset state before it prints the trace, and on this design
    that is seventeen rows of `init \\gate.add_0 = 0` ahead of the five rows
    that say what actually went wrong. Truncating the raw table to fit a prompt
    therefore sends the model nothing but zeros -- which is exactly what
    happened on the first two pipelining attempts, and why the repair attempt
    reproduced the same mistake: it was never told what the mistake was.

    So drop the init rows, keep the header and every row at a real cycle, and
    put the mismatched outputs first.
    """
    lines = [l for l in table.splitlines() if l.strip()]
    head = [l for l in lines[:2]]
    rows = [l for l in lines[2:] if not re.match(r"\s*init\b", l.strip())
            and not set(l.strip()) <= set("- ")]
    bad = [l for l in rows if re.search(r"gold|gate|trigger", l)]
    rest = [l for l in rows if l not in bad]
    return "\n".join(head + bad + rest[:20])


def run(golden, candidate, module, depth, latency, clock, timeout,
        enable=None, reset=None, reset_align=None, observe=False,
        engine="auto"):
    tmp = tempfile.mkdtemp(prefix="g1_")
    wrapper = ""
    ra_gold = ra_gate = None
    if reset_align:
        # A re-encoded FSM is not a latency change, and combining the two
        # wrappers has not been thought through, so refuse rather than emit
        # something whose proven statement nobody can state.
        if latency:
            return {"verdict": "ERROR",
                    "detail": "reset alignment and a latency change cannot be "
                              "combined; fsm_encode preserves latency"}
        for tag, tree in (("gold", golden), ("gate", candidate)):
            _, src = T.module_source(module, tree)
            if src is None:
                return {"verdict": "ERROR", "detail": f"{module} not in {tree}"}
            path = os.path.join(tmp, f"__ra_{tag}.v")
            open(path, "w").write(
                reset_align_wrapper(module, src, reset_align, clock, tag))
            if tag == "gold":
                ra_gold = path
            else:
                ra_gate = path
    if latency:
        _, src = T.module_source(module, golden)
        if src is None:
            return {"verdict": "ERROR", "detail": f"{module} not in {golden}"}
        wrapper = os.path.join(tmp, "__gold_delay.v")
        open(wrapper, "w").write(
            delay_wrapper(module, src, latency, clock, enable, reset))

    mclass = classify(module, golden)
    if engine == "auto":
        engine = ENGINE_FOR_CLASS[mclass]
    fallback = None
    if engine in ("smtbmc", "pdr") and not solver_available(engine):
        # Nothing is gained by failing a proof because a binary is missing.
        # Drop to SAT, record that it happened, and let the verdict be read in
        # that light.
        fallback = f"{engine} unavailable"
        engine = "sat"

    artifact = None
    if engine == "smtbmc":
        artifact = os.path.join(tmp, "miter.smt2")
    elif engine == "pdr":
        artifact = os.path.join(tmp, "miter.aig")

    ys = os.path.join(tmp, "eq.ys")
    open(ys, "w").write(script(golden, candidate, module, depth,
                               latency, clock, wrapper, ra_gold, ra_gate,
                               engine=engine, artifact=artifact))
    t0 = time.time()
    try:
        r = subprocess.run(["yosys", "-s", ys],
                           capture_output=True, text=True, timeout=timeout)
        out = r.stdout + r.stderr
        rc = r.returncode
    except subprocess.TimeoutExpired:
        return {"verdict": "TIMEOUT", "seconds": round(time.time() - t0, 1),
                "depth": depth, "latency_delta": latency,
                "engine": engine, "module_class": mclass}

    res = {"seconds": round(time.time() - t0, 1), "depth": depth,
           "latency_delta": latency, "module": module,
           "engine": engine, "module_class": mclass}
    if fallback:
        res["engine_fallback"] = fallback

    # SMTBMC and PDR run as a second process; yosys only writes the problem
    # out. A yosys failure there is a build failure, not a verdict.
    if engine in ("smtbmc", "pdr"):
        if rc != 0 or not os.path.exists(artifact):
            res["verdict"] = "ERROR"
            res["detail"] = (f"yosys could not write the {engine} problem\n"
                             + out[-2000:])
            return res
        left = timeout - (time.time() - t0)
        if left <= 5:
            res["verdict"] = "TIMEOUT"
            res["seconds"] = round(time.time() - t0, 1)
            return res
        solve = solve_smtbmc if engine == "smtbmc" else solve_pdr
        res.update(solve(artifact, depth, left))
        res["seconds"] = round(time.time() - t0, 1)
        return res

    if "SAT proof finished - no model found: SUCCESS" in out or \
       re.search(r"Assert .*passed|proved.*assert", out):
        res["verdict"] = "EQUIVALENT"
        # A bounded window that cannot see the inputs proves nothing about the
        # edit. Check the window before reporting the pass, never after
        # reporting a failure: a counterexample is a witness and stands on its
        # own whatever the depth.
        if observe:
            v, port = observable(golden, module, depth, timeout, tmp)
            res["observability"] = v
            res["observability_port"] = port
            if v == "no":
                res["verdict"] = "INCONCLUSIVE"
                res["detail"] = (
                    f"no input of {module} reaches an output within {depth} "
                    f"cycles, so the bounded proof compared reset values only; "
                    f"raise --depth above the module's own pipeline depth")
            elif v == "unknown":
                res["detail"] = ("could not establish that depth "
                                 f"{depth} observes the inputs")
    elif "SAT proof finished - model found: FAIL" in out:
        res["verdict"] = "NOT_EQUIVALENT"
        m = re.search(r"Signal Name.*?(?=\n\n)", out, re.S)
        raw = m.group(0) if m else out[-8000:]
        res["counterexample"] = raw[:8000]
        res["counterexample_summary"] = summarize(raw)
    elif rc != 0:
        res["verdict"] = "ERROR"
        res["detail"] = out[-2000:]
    else:
        res["verdict"] = "ERROR"
        res["detail"] = "no SAT verdict in yosys output\n" + out[-1500:]
    return res


def run_group(cmd, timeout):
    """
    subprocess.run, except a timeout kills the whole process tree.

    subprocess.run only kills the process it started. `yosys-smtbmc` is a
    driver: it spawns the real solver as a child and talks to it over a pipe,
    so killing the driver on timeout leaves bitwuzla running, detached, at one
    hundred percent of a core, forever. Three of those accumulated during one
    unattended run -- 2h37m, 1h55m and 1h14m past their own 40-minute budget --
    and the cores they held are why the run that spawned them was crawling.

    start_new_session puts the child in its own process group, so the timeout
    path can signal the group and take the solver with it.
    """
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True,
                            stdin=subprocess.DEVNULL, start_new_session=True)

    def kill_group():
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(os.getpgid(proc.pid), sig)
            except (ProcessLookupError, PermissionError):
                return
            try:
                proc.communicate(timeout=5)
                return
            except subprocess.TimeoutExpired:
                continue

    try:
        out, err = proc.communicate(timeout=timeout)
        return proc.returncode, out + err, False
    except subprocess.TimeoutExpired:
        kill_group()
        return None, "", True
    finally:
        # Cleaning up only on the timeout path is not enough. Anything else
        # that ends this function with the solver still running -- a
        # KeyboardInterrupt, a SIGTERM from whatever launched the run, an
        # exception raised above -- leaves the same detached solver behind,
        # which is how a yosys-abc ended up at PPID 1 after an outer timeout
        # killed its parent. The one case still not covered is SIGKILL to this
        # process, which no handler can intercept.
        if proc.poll() is None:
            kill_group()


def solver_available(engine):
    """
    Is the external solver this engine shells out to actually installed?

    SMTBMC needs both the driver and a back-end solver; PDR needs ABC. The OSS
    CAD Suite ships `yosys-abc` and no standalone `abc`, so the bundled name is
    checked too.
    """
    if engine == "smtbmc":
        return bool(shutil.which("yosys-smtbmc")) and bool(smt_solver())
    if engine == "pdr":
        return bool(shutil.which("yosys-abc") or shutil.which("abc"))
    return True


def smt_solver():
    """
    Preferred SMT back end, best first.

    Bitwuzla is the one that matters here: it is the current state of the art
    on quantifier-free bit-vector problems, which is exactly what a flattened
    arithmetic miter becomes. The rest are fallbacks so a machine without it
    still runs.
    """
    for name in ("bitwuzla", "boolector", "yices-smt2", "z3"):
        if shutil.which(name):
            return name
    return None


def solve_smtbmc(smt2, depth, timeout):
    """
    Bounded model check the miter with a bit-vector solver instead of SAT.

    Same statement the SAT engine proves -- no assertion fires in the first
    `depth` cycles from an all-zero start -- reached through QF_BV, where a
    multiply stays a multiply instead of becoming a few hundred thousand CNF
    clauses with no structure left to exploit.
    """
    solver = smt_solver()
    cmd = ["yosys-smtbmc", "-s", solver, "-t", str(depth),
           "--noprogress", "-m", "miter", smt2]
    t0 = time.time()
    rc, out, timed_out = run_group(cmd, max(5, int(timeout)))
    if timed_out:
        return {"verdict": "TIMEOUT", "solver": solver,
                "solver_seconds": round(time.time() - t0, 1)}
    res = {"solver": solver, "solver_seconds": round(time.time() - t0, 1)}
    if "Status: PASSED" in out:
        res["verdict"] = "EQUIVALENT"
    elif "Status: FAILED" in out:
        res["verdict"] = "NOT_EQUIVALENT"
        res["counterexample"] = out[-8000:]
        res["counterexample_summary"] = smtbmc_summary(out)
    else:
        res["verdict"] = "ERROR"
        res["detail"] = out[-2000:]
    return res


def smtbmc_summary(out):
    """
    The lines of an smtbmc run that say what failed.

    smtbmc names the failing assert and the step it fired on; that pair is the
    whole diagnosis, and it is what gets sent back to the model.
    """
    keep = [l for l in out.splitlines()
            if re.search(r"Assert failed|BMC failed|in step|Status:", l)]
    return "\n".join(keep[:20]) or out[-800:]


def solve_pdr(aig, depth, timeout):
    """
    Prove the miter unbounded with ABC's PDR (property-directed reachability).

    SAT and SMTBMC both answer "no mismatch in the first N cycles". On a deep
    FSM that is the wrong question -- the state that separates two encodings
    can sit further out than any N worth waiting for. PDR answers "no mismatch
    ever", by finding an inductive invariant, so a pass here is a complete
    proof and `depth` does not enter into it.

    The AIGER file carries `trigger` as its only primary output (see the
    engine-specific miter in script()), and PDR proves a primary output is
    never high.
    """
    abc = shutil.which("yosys-abc") or shutil.which("abc")
    cmd = [abc, "-c", f"read_aiger {aig}; fold; pdr"]
    t0 = time.time()
    rc, out, timed_out = run_group(cmd, max(5, int(timeout)))
    if timed_out:
        return {"verdict": "TIMEOUT", "solver": "abc-pdr",
                "solver_seconds": round(time.time() - t0, 1)}
    res = {"solver": "abc-pdr", "solver_seconds": round(time.time() - t0, 1)}
    if "Property proved" in out:
        res["verdict"] = "EQUIVALENT"
        # Unbounded, so unlike every other verdict in this file it is not
        # qualified by a depth.
        res["proof"] = "unbounded"
        res["complete"] = True
    elif re.search(r"was asserted in frame|Output .* asserted|"
                   r"Property DISPROVED", out):
        res["verdict"] = "NOT_EQUIVALENT"
        res["counterexample"] = out[-8000:]
        res["counterexample_summary"] = "\n".join(
            l for l in out.splitlines()
            if re.search(r"asserted|frame|DISPROVED", l))[:2000]
    else:
        res["verdict"] = "ERROR"
        res["detail"] = out[-2000:]
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--golden", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--module", required=True)
    ap.add_argument("--latency", type=int, default=0,
                    help="cycles the candidate adds; 0 for a plain miter")
    ap.add_argument("--clock", default=None,
                    help="clock port to delay against (guessed if omitted)")
    ap.add_argument("--enable", default=None,
                    help="candidate-only enable port; the gold delay flops "
                         "get the same one, so a stall is proven not assumed")
    ap.add_argument("--reset", default=None,
                    help="synchronous active-high reset port; clears the gold "
                         "delay flops the way the candidate clears its stages")
    ap.add_argument("--reset-align", default=None, metavar="PORT",
                    help="hold PORT asserted for one cycle on both halves of "
                         "the miter and mask the outputs while it is, so each "
                         "machine starts in its own reset state. Required for "
                         "fsm_encode: under -set-init-zero an all-zero start "
                         "is a different state under a different encoding")
    ap.add_argument("--depth", type=int, default=12)
    ap.add_argument("--observe", action="store_true",
                    help="before reporting a bounded pass, prove that some "
                         "input reaches an output inside --depth cycles; "
                         "without it a window shorter than the module's own "
                         "pipeline depth compares reset values and passes "
                         "anything")
    ap.add_argument("--engine", default="auto",
                    choices=("auto", "sat", "smtbmc", "pdr"),
                    help="proof engine. auto picks from the module's class: "
                         "simple logic -> SAT, multiplier/FP arithmetic and "
                         "memory -> SMTBMC+Bitwuzla, FSM/deep sequential -> "
                         "ABC PDR. sat reproduces every pre-2026-09-13 verdict")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--out", default=None)
    ap.add_argument("--json", action="store_true",
                    help="print the verdict record on stdout for a caller")
    a = ap.parse_args()

    clock = a.clock
    if (a.latency or a.reset_align) and not clock:
        _, src = T.module_source(a.module, a.golden)
        p = T.ports(src or "")
        clock = next((c for c in CLOCK_NAMES if c in p), None)
        if not clock:
            raise SystemExit(f"could not guess a clock port for {a.module}; "
                             f"pass --clock")

    res = run(a.golden, a.candidate, a.module, a.depth,
              a.latency, clock, a.timeout, a.enable, a.reset,
              a.reset_align, a.observe, a.engine)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(json.dumps(res, indent=2) + "\n")
    if a.json:
        print(json.dumps(res, indent=2))
        sys.exit(0 if res["verdict"] == "EQUIVALENT" else 1)
    eng = res.get("engine", "sat")
    if res.get("solver"):
        eng = f'{eng}/{res["solver"]}'
    depth_note = "unbounded" if res.get("proof") == "unbounded" \
                 else f'depth {res.get("depth")}'
    print(f'{res["verdict"]:<16} {a.module:<24} '
          f'[{res.get("module_class")}: {eng}]  {depth_note}  '
          f'latency +{res.get("latency_delta")}  {res.get("seconds")}s')
    if res["verdict"] not in ("EQUIVALENT",):
        d = res.get("counterexample") or res.get("detail") or ""
        for line in d.splitlines()[:12]:
            print("   ", line)
    sys.exit(0 if res["verdict"] == "EQUIVALENT" else 1)


if __name__ == "__main__":
    main()
