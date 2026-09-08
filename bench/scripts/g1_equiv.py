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


# `memory_map` is what makes a FIFO provable at all. Left as an array, the
# storage stays a $mem_v2 cell and the solver stops with "No SAT model
# available for cell gate.mem ($mem_v2)". Mapping it to flops and decoders
# costs depth * width * 2^logofdepth extra variables, which is the price of
# checking a module whose whole job is storage.
def script(golden, candidate, module, depth, latency, clock, wrapper_file):
    gold_top = module if not latency else f"__gold_delay_{module}"
    extra = f"read_verilog -defer {wrapper_file}" if latency else ""
    return f"""
{read_cmds(golden)}
{extra}
hierarchy -check -top {gold_top}
proc; opt_expr; opt_clean; memory -nomap; memory_map; opt -fast
flatten; opt -fast
rename -top gold
design -stash gold

{read_cmds(candidate)}
hierarchy -check -top {module}
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
        enable=None, reset=None):
    tmp = tempfile.mkdtemp(prefix="g1_")
    wrapper = ""
    if latency:
        _, src = T.module_source(module, golden)
        if src is None:
            return {"verdict": "ERROR", "detail": f"{module} not in {golden}"}
        wrapper = os.path.join(tmp, "__gold_delay.v")
        open(wrapper, "w").write(
            delay_wrapper(module, src, latency, clock, enable, reset))

    ys = os.path.join(tmp, "eq.ys")
    open(ys, "w").write(script(golden, candidate, module, depth,
                               latency, clock, wrapper))
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
    ap.add_argument("--depth", type=int, default=12)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--out", default=None)
    ap.add_argument("--json", action="store_true",
                    help="print the verdict record on stdout for a caller")
    a = ap.parse_args()

    clock = a.clock
    if a.latency and not clock:
        _, src = T.module_source(a.module, a.golden)
        p = T.ports(src or "")
        clock = next((c for c in CLOCK_NAMES if c in p), None)
        if not clock:
            raise SystemExit(f"could not guess a clock port for {a.module}; "
                             f"pass --clock")

    res = run(a.golden, a.candidate, a.module, a.depth,
              a.latency, clock, a.timeout, a.enable, a.reset)
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
