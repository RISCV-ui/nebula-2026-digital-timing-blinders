#!/usr/bin/env python3
"""
g1b_contract.py -- gate 1b: does the module's parent survive the new latency?

G1 proves the right thing about the wrong scope. A pipelined module is checked
against its own outputs delayed by N, so "correct N cycles later" is exactly
what gets proven -- and that proof is sound. It says nothing at all about
whether anybody upstream is willing to wait N cycles.

This design shows why that gap matters. The loop pipelined `fp4_dot_unit` by
four stages, G1 passed cleanly, and the module is genuinely correct. Its parent
`axi_lite_dot` does this:

    fp4_dot_unit fp4_dot_0(clk_2, rst_2, va, vb, dot_out);
    assign fifo_data_write = dot_out;
    assign w_en = (!fifo_empty_1 && !fifo_empty_2 && !fifo_full);

The same cycle that pops the operands out of the two input FIFOs also pushes
`dot_out` into the result FIFO. That was correct while the dot unit was
combinational. With four pipeline stages in it, `w_en` now writes whatever the
pipeline happens to be holding -- the result of operands popped four cycles
ago, or reset garbage. The module is equivalent; the SoC is broken. No
module-scope equivalence checker can see this, because at module scope nothing
is wrong.

So the check has to move up one level, and there it becomes easy again: build
the parent twice, once over the original child and once over the transformed
one, and miter the two parents against each other with NO delay wrapper. The
parent is not supposed to be late -- it is supposed to be identical.

    EQUIVALENT      the parent absorbs the latency (a handshake, a valid chain,
                    a consumer that already waits) -- the edit is safe to keep
    NOT_EQUIVALENT  the parent assumed the old timing; the counterexample is
                    the cycle where the SoC diverges

A module with no parent in the tree is a top and passes vacuously; that is
recorded as `no_parent`, not as a proof.

This is the one gate in the flow whose failure is *not* a bug in the model's
edit. The edit is correct. The contract around it is what broke, and the repair
belongs in the parent -- which is why the verdict is reported separately from
G1 rather than folded into it.

Usage:
    g1b_contract.py --golden bench/rtl --candidate artifacts/loop/rtl \\
                    --module fp4_dot_unit --json
"""
import argparse, glob, json, os, re, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import g1_equiv as G1                                     # noqa: E402
import transforms as T                                    # noqa: E402


def modules_in(rtl_dir):
    names = []
    for f in sorted(glob.glob(os.path.join(rtl_dir, "*.v"))):
        names += re.findall(r"^\s*module\s+([A-Za-z_]\w*)", open(f).read(), re.M)
    return names


def parents_of(module, rtl_dir):
    """
    Every module in the tree that instantiates `module`.

    Matched on an instantiation, not on a bare mention: a module name inside a
    comment or as a substring of another identifier is not a parent, and
    boxing the search on `<name> [#(...)] <instance> (` is what keeps
    `fp8_adder` from claiming `fp8_adder_tb` as a parent.
    """
    out = []
    for m in modules_in(rtl_dir):
        if m == module:
            continue
        _, src = T.module_source(m, rtl_dir)
        if not src:
            continue
        if re.search(rf"^\s*{re.escape(module)}\s+(?:#\s*\([^;]*\)\s*)?"
                     rf"[A-Za-z_][\w$]*\s*\(", src, re.M):
            out.append(m)
    return out


def check(golden, candidate, module, depth=12, timeout=900):
    """
    Run the parent-scope miter for every parent of `module`.

    Latency is deliberately 0 here even though the child's latency changed.
    Delaying the golden parent would prove the parent is "correct N cycles
    late", which is precisely the claim under dispute -- the question is
    whether the parent's own interface still behaves as it did, and that
    demands an undelayed comparison.
    """
    parents = parents_of(module, golden)
    rec = {"module": module, "parents": parents, "checks": []}
    if not parents:
        rec["verdict"] = "NO_PARENT"
        rec["detail"] = (f"{module} is not instantiated anywhere in {golden}; "
                         f"no latency contract to violate")
        return rec

    for p in parents:
        t0 = time.time()
        r = G1.run(golden, candidate, p, depth, 0, None, timeout)
        r["parent"] = p
        r["seconds"] = round(time.time() - t0, 1)
        rec["checks"].append(r)

    verdicts = [c["verdict"] for c in rec["checks"]]
    rec["verdict"] = ("CONTRACT_HELD" if all(v == "EQUIVALENT" for v in verdicts)
                      else "CONTRACT_BROKEN"
                      if "NOT_EQUIVALENT" in verdicts else "INCONCLUSIVE")
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--golden", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--module", required=True)
    ap.add_argument("--depth", type=int, default=12)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--out", default=None)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    rec = check(a.golden, a.candidate, a.module, a.depth, a.timeout)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(json.dumps(rec, indent=2) + "\n")
    if a.json:
        print(json.dumps(rec, indent=2))
    else:
        print(f'{rec["verdict"]:<16} {a.module}')
        for c in rec["checks"]:
            print(f'   parent {c["parent"]:<20} {c["verdict"]:<16} '
                  f'{c.get("seconds")}s')
            if c["verdict"] == "NOT_EQUIVALENT":
                for line in (c.get("counterexample_summary") or "").splitlines()[:12]:
                    print("      ", line)
    sys.exit(0 if rec["verdict"] in ("CONTRACT_HELD", "NO_PARENT") else 1)


if __name__ == "__main__":
    main()
