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
           ra_gold=None, ra_gate=None):
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
miter -equiv -flatten -make_assert -make_outputs gold gate miter
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
sat -seq {depth} -prove-asserts -set-init-zero -verify -show-inputs -show-outputs miter
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
        enable=None, reset=None, reset_align=None, observe=False):
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

    ys = os.path.join(tmp, "eq.ys")
    open(ys, "w").write(script(golden, candidate, module, depth,
                               latency, clock, wrapper, ra_gold, ra_gate))
    t0 = time.time()
    try:
        r = subprocess.run(["yosys", "-s", ys],
                           capture_output=True, text=True, timeout=timeout)
        out = r.stdout + r.stderr
        rc = r.returncode
    except subprocess.TimeoutExpired:
        return {"verdict": "TIMEOUT", "seconds": round(time.time() - t0, 1),
                "depth": depth, "latency_delta": latency}

    res = {"seconds": round(time.time() - t0, 1), "depth": depth,
           "latency_delta": latency, "module": module}
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
              a.reset_align, a.observe)
    if a.json:
        print(json.dumps(res, indent=2))
        sys.exit(0 if res["verdict"] == "EQUIVALENT" else 1)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(json.dumps(res, indent=2) + "\n")
    print(f'{res["verdict"]:<16} {a.module:<24} '
          f'depth {res.get("depth")}  latency +{res.get("latency_delta")}  '
          f'{res.get("seconds")}s')
    if res["verdict"] not in ("EQUIVALENT",):
        d = res.get("counterexample") or res.get("detail") or ""
        for line in d.splitlines()[:12]:
            print("   ", line)
    sys.exit(0 if res["verdict"] == "EQUIVALENT" else 1)


if __name__ == "__main__":
    main()
