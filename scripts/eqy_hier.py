#!/usr/bin/env python3
"""
eqy_hier.py -- RTL-vs-netlist equivalence, leaf modules first.

The flat check gives up on exactly the modules that matter. `fp4_dot_unit`
instantiates eight `fp4_mul` and seven `fp8_adder`; flattened, that is fifteen
floating-point units in one SAT problem, and it times out at 900s -- even
though every one of those fifteen children was already proved equivalent
minutes earlier, on its own, in seconds.

So prove in dependency order and keep the results. A module that passes is
written out as a `(* blackbox *)` declaration and read on BOTH sides of every
later check, which cuts it out of the cone entirely: the parent's proof then
covers the parent's own logic and wiring, with its children standing as
uninterpreted functions that are known -- separately, by their own proofs -- to
match. `fp4_dot_unit` goes from TIMEOUT at 900s to PROVED_EQUIVALENT in 5.4s
this way.

This is compositional equivalence checking, and it is what commercial tools do
by default; it is the only reason EC scales past small blocks. It also proves
strictly less than a flat check in one specific way, and the report says so:
the chain is sound only because each child carries its own proof, so a child
that fails, times out, or is skipped is NOT boxed for its parents. An unproven
module stays expanded, and its parents inherit the cost.

Usage:
    eqy_hier.py --rtl <dir> --netlist <v> --liberty <lib> \\
                --macro-stub macros/macro_blackbox_stubs.v \\
                --out artifacts/eqy/hier.json
"""
import argparse, json, os, re, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "bench" / "scripts"))
import transforms as T                                   # noqa: E402


def instantiations(src, known):
    """Module names `src` instantiates, restricted to `known`."""
    out = set()
    for name in known:
        if re.search(rf"^\s*{re.escape(name)}\s+(?:#\s*\([^;]*\)\s*)?"
                     rf"[A-Za-z_][\w$]*\s*\(", src, re.M):
            out.add(name)
    return out


def order(rtl_dir, modules):
    """
    Modules leaf-first. Depth = longest instantiation chain below a module, so
    everything a module contains is proved before the module itself.
    """
    src = {}
    for m in modules:
        _, s = T.module_source(m, rtl_dir)
        src[m] = s or ""
    children = {m: instantiations(src[m], set(modules)) - {m} for m in modules}

    depth, visiting = {}, set()
    def d(m):
        if m in depth:
            return depth[m]
        if m in visiting:            # cycle: should not happen in RTL
            return 0
        visiting.add(m)
        depth[m] = 1 + max([d(c) for c in children[m]], default=-1)
        visiting.discard(m)
        return depth[m]
    for m in modules:
        d(m)
    return sorted(modules, key=lambda m: (depth[m], m)), depth, children


def stub_for(module, rtl_dir):
    _, src = T.module_source(module, rtl_dir)
    if src is None:
        return None
    p = T.ports(src)
    L = ["(* blackbox *)", f"module {module}(" + ", ".join(p) + ");"]
    for k, v in p.items():
        v = v.strip()
        L.append(f"    {v};" if v.endswith(k) else f"    {v} {k};")
    L.append("endmodule\n")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rtl", required=True)
    ap.add_argument("--netlist", required=True)
    ap.add_argument("--liberty", required=True)
    ap.add_argument("--macro-stub", required=True)
    ap.add_argument("--modules", nargs="*")
    ap.add_argument("--skip", nargs="*", default=[])
    ap.add_argument("--depth", type=int, default=5)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--workdir", default="artifacts/eqy/hier_work")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    work = Path(a.workdir); work.mkdir(parents=True, exist_ok=True)
    base_stub = Path(a.macro_stub).read_text()
    macro_boxed = set(re.findall(r"^module\s+([A-Za-z_][\w$]*)",
                                 base_stub, re.M))

    netlist_mods = set(re.findall(r"^module\s+([A-Za-z_][\w$]*)",
                                  Path(a.netlist).read_text(), re.M))
    rtl_mods = {p.stem for p in Path(a.rtl).glob("*.v")}
    mods = sorted((set(a.modules) if a.modules
                   else netlist_mods & rtl_mods) - set(a.skip) - macro_boxed)

    seq, depth, children = order(a.rtl, mods)
    print(f"{len(seq)} modules, leaf-first:", file=sys.stderr)
    for m in seq:
        print(f"  d{depth[m]}  {m}"
              + (f"   <- {', '.join(sorted(children[m]))}" if children[m] else ""),
              file=sys.stderr)

    proved, results = [], []
    stub_path = work / "cutpoints.v"
    t_start = time.time()

    for i, m in enumerate(seq, 1):
        # Box this module's own proved children and nothing else.
        #
        # The file used to carry a stub for every module proved so far, on the
        # reasoning that a stub for a module the check never instantiates is
        # inert. It is not. The stubs are read with `read_verilog -lib`, which
        # declares the name on both sides before the RTL is read, so a stub for
        # an unrelated module still shadows that module wherever the flattener
        # later reaches it -- through a path the `children` map, which only
        # matches direct textual instantiations, never saw. equiv_induct then
        # meets a cell with no SAT model and stops.
        #
        # It also made the sweep order-dependent in a way nothing in the method
        # justifies: the stub file was a function of the whole pass/fail
        # history above a module, so an unrelated module flipping verdict
        # changed the file every later module was checked against. Two modules
        # that passed the previous sweep failed this one for exactly that
        # reason -- i_rom_32x256 and id_memory_256x64_wrap, same pass, same
        # depth, different accumulated stub file.
        #
        # Only a child needs to be a cut point, and only a child is what the
        # soundness argument covers, so only a child is written.
        boxed = [c for c in children[m] if c in proved]
        stub_path.write_text(base_stub + "\n" +
                             "\n".join(stub_for(x, a.rtl) or "" for x in boxed))
        cmd = [sys.executable, str(HERE / "eqy_netlist.py"),
               "--rtl", a.rtl, "--netlist", a.netlist, "--liberty", a.liberty,
               "--macro-stub", str(stub_path), "--modules", m,
               "--depth", str(a.depth), "--timeout", str(a.timeout),
               "--workdir", str(work / m), "--out", str(work / f"{m}.json")]
        if boxed:
            # children already proved -> the partitioner has nothing to find
            cmd.append("--no-eqy-passes")
        t0 = time.time()
        subprocess.run(cmd, capture_output=True, text=True)
        try:
            r = json.loads((work / f"{m}.json").read_text())["results"][0]
        except Exception as e:
            r = {"module": m, "status": f"DRIVER_ERROR: {e}", "equivalent": False}

        # A boxed child is a cut point for the *cone*, not for the solver:
        # equiv_induct needs a SAT model for every cell it walks, and a
        # blackbox has none. Where that happens the box is worth nothing, so
        # drop it and re-run the module expanded, with EQY's passes back on.
        # Slower, strictly stronger, and it turns a tool error into a verdict.
        if not r.get("equivalent") and "No SAT model" in r.get("status", ""):
            stub_path.write_text(base_stub)
            cmd2 = [c for c in cmd if c != "--no-eqy-passes"]
            t1 = time.time()
            subprocess.run(cmd2, capture_output=True, text=True)
            try:
                r2 = json.loads((work / f"{m}.json").read_text())["results"][0]
            except Exception as e:
                r2 = {"module": m, "status": f"DRIVER_ERROR: {e}",
                      "equivalent": False}
            r2["retried_expanded"] = True
            r2["boxed_status"] = r["status"]
            r2["boxed_seconds"] = round(t1 - t0, 1)
            r = r2
        r["cut_points"] = sorted(boxed)
        r["seconds"] = round(time.time() - t0, 1)
        results.append(r)
        if r.get("equivalent"):
            proved.append(m)
        print(f"[{i}/{len(seq)}] {'PASS' if r.get('equivalent') else 'FAIL'}  "
              f"{m:<28} {r['status']:<28} {r['seconds']:>7.1f}s"
              + (f"  boxed: {len(boxed)}" if boxed else ""), file=sys.stderr)

    out = {"netlist": os.path.abspath(a.netlist),
           "method": "compositional: a module proved equivalent is boxed "
                     "identically on both sides of every later check",
           "modules_checked": len(results),
           "modules_equivalent": len(proved),
           "all_equivalent": len(proved) == len(results),
           "total_seconds": round(time.time() - t_start, 1),
           "order": seq, "results": results}
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps(out, indent=2) + "\n")
    print(f"\n{len(proved)}/{len(results)} proved equivalent in "
          f"{out['total_seconds']}s -> {a.out}", file=sys.stderr)
    return 0 if out["all_equivalent"] else 1


if __name__ == "__main__":
    sys.exit(main())
