#!/usr/bin/env python3
"""
Module-by-module formal equivalence: RTL versus the post-synthesis netlist.

This is the other half of the equivalence story. run_eqy.py proves one RTL
against another RTL, which is what the LLM loop needs to gate an edit.
This script proves that SYNTHESIS itself did not change the design: every
module in the netlist is checked against the module of the same name in the
RTL, one at a time, so a failure names the module that broke instead of
saying "the chip is different somewhere".

Three things make the module-by-module form work:

  * Hierarchy must survive synthesis. run_synth.py never flattens, so the
    netlist still has one module per RTL module to compare against.

  * The fsm pass must be off (run_synth.py --no-fsm). FSM re-encoding
    changes the state bits, so the netlist's registers no longer correspond
    to the RTL's and a module-level proof has nothing to match.

  * The hard macros are blackboxed on BOTH sides, from the same stub file.
    The prover then treats each SRAM as the same uninterpreted function in
    gold and gate, which is exactly right: synthesis cannot have changed the
    inside of a macro, so there is nothing there to prove. What gets proved
    is the logic around it.

Each module is tried twice, in this order, and the first PASS is the answer:

  1. EQY's own partitioning. It splits the module into one proof per output
     cone, cutting at signals it matched between the two sides. Cheap, and
     what EQY is built to do.

  2. `merge *`, which collapses those back into a single partition and
     proves the module as one object.

The second pass exists because partitioning can report a failure that is not
a real difference. `alu.zero` is the example: the RTL computes it from
alu_result, the netlist recomputes it straight from the operands, and the
partitioned proof feeds those two cones inconsistent values and calls the
module unequal. Proving the whole module at once removes the cut and the
false counterexample with it.

The first pass exists because `merge *` is not always available: on modules
where one net (a clock, typically) matches more than one thing, merging
everything makes the match ambiguous and EQY refuses to partition at all.
axi_interconnect_2m_8s is that case here.

  3. A plain Yosys `equiv_make` / `equiv_induct` proof, run directly rather
     than through EQY. This is the fallback for modules EQY cannot even set
     up: where a clock port drives a flop directly, EQY's id matcher finds
     the same gold bit reachable as both the port `clk` and the cell pin
     `_4_.CLK`, calls that a conflicting match, and refuses to partition.
     Yosys matches the two designs itself and never hits that.

A PASS from any pass is sound -- partitioning only ever invents failures,
never proofs. A module is only reported as failing if every pass agrees it
fails, and the JSON records which pass produced the verdict.

Usage:
    python3 scripts/eqy_netlist.py \
        --rtl <dir-or-files> --netlist artifacts/synth/soc_top_macro.v \
        --liberty sta/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib \
        --macro-stub macros/macro_blackbox_stubs.v \
        --out artifacts/eqy/soc_top_modules.json

Exit code: 0 only if every checked module proved equivalent.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# The `sby` strategy shells out to an SMT solver by name, and when that name is
# not on PATH the engine dies without a status, EQY reports the partition
# unproven, and the whole run degrades to the depth-5 yosys fallback -- silently
# and with no line anywhere saying "no solver". A full 54-module run was spent
# that way before the log was read closely enough to notice. The solvers ship
# inside oss-cad-suite, so put its bin on PATH here rather than depending on
# whoever launched the script having sourced the right environment, and refuse
# to start if the engine still is not there.
SUITE_BIN = REPO_ROOT / "oss-cad-suite" / "bin"
if SUITE_BIN.is_dir():
    os.environ["PATH"] = f"{SUITE_BIN}:{os.environ.get('PATH', '')}"

SMT_ENGINE = "bitwuzla"


def require_solver():
    if shutil.which(SMT_ENGINE) is None:
        raise SystemExit(
            f"{SMT_ENGINE} is not on PATH and is not in {SUITE_BIN}. EQY's sby "
            f"strategy needs it; without it every sequential partition comes "
            f"back unproven for a reason that has nothing to do with the "
            f"design. Install it, or source oss-cad-suite/environment.")

CFG = """\
[gold]
{stub_gold}read_verilog {rtl}
prep -top {module}

[gate]
{stub_gate}read_liberty -ignore_miss_func {liberty}
read_verilog {netlist}
prep -top {module}
{partition}
[strategy sat]
use sat
depth {depth}

[strategy sby]
use sby
depth {depth}
engine smtbmc {engine}
timeout 600
"""

# (label, partition section). Tried in order; first PASS wins.
PASSES = [
    ("partitioned", "\n"),
    ("merged", "\n[partition *]\nmerge *\n\n"),
]

YOSYS = REPO_ROOT / "oss-cad-suite" / "bin" / "yosys"

# Fallback proof, no EQY involved. -flatten on both sides so the comparison
# is of one module's logic and its submodules, with the macros still boxed.
#
# Flattening the submodules in is not a stylistic choice, it is forced. The
# obvious alternative -- keep the hierarchy and blackbox the child modules,
# so each module is proved against boxed children -- was tried and does not
# work here: equiv_induct needs a SAT model for every cell it sees, and a
# blackbox has none, so it stops with
#   ERROR: No SAT model available for cell fifo_timer_r_gate (...)
# The macros survive as boxes only because they are cut out of the cone
# entirely on both sides, not because equiv_induct can reason about a box.
# memory_map turns any surviving $mem_v2 into flops and muxes: the SAT solver
# has no model for a memory cell, and the netlist side is already flops, so
# mapping both sides is what makes the two comparable at all.
#
# `setattr -mod -unset keep_hierarchy` is not cosmetic. run_synth.py sets
# `keep_hierarchy` on every module so the netlist stays hierarchical for this
# very check -- and `flatten` honours that attribute, so `prep -flatten` walks
# straight past every child and leaves it as an unflattened hierarchical cell.
# equiv_induct then meets a cell it has no SAT model for and stops with the
# same message a real blackbox produces:
#   ERROR: No SAT model available for cell mul_unit_ex_gate (multiplier_pipelined).
# That error was read as "compositional boxing does not work here" for twelve
# modules of the first full sweep. It was the attribute, not the boxing.
EQUIV_YS = """\
{stub}read_verilog {rtl}
setattr -mod -unset keep_hierarchy
prep -flatten -top {module}
memory_map
opt -fast
design -stash gold

{stub}read_liberty -ignore_miss_func {liberty}
read_verilog {netlist}
setattr -mod -unset keep_hierarchy
prep -flatten -top {module}
memory_map
opt -fast
design -stash gate

design -copy-from gold -as gold {module}
design -copy-from gate -as gate {module}
equiv_make gold gate equiv
hierarchy -top equiv
equiv_simple -seq {depth}
equiv_induct -seq {depth}
equiv_status -assert
"""


def run_yosys_equiv(module, rtl, netlist, liberty, stub, depth, timeout, workroot):
    ys = EQUIV_YS.format(
        stub=f"read_verilog -lib {stub}\n" if stub else "",
        rtl=" ".join(str(f) for f in rtl),
        netlist=netlist,
        liberty=liberty,
        module=module,
        depth=depth,
    )
    ys_path = workroot / f"{module}.equiv.ys"
    ys_path.write_text(ys)

    t0 = time.time()
    try:
        proc = subprocess.run(
            [str(YOSYS), "-s", str(ys_path)],
            cwd=workroot,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        log = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired:
        return {
            "module": module,
            "pass": "yosys-equiv",
            "equivalent": False,
            "status": f"TIMEOUT after {timeout}s",
            "seconds": round(time.time() - t0, 1),
            "failed_partitions": [],
            "log_tail": [],
        }

    ok = "Equivalence successfully proven!" in log
    if ok:
        status = "PROVED_EQUIVALENT"
    else:
        unproven = re.search(r"(\d+) are unproven", log)
        err = re.search(r"^ERROR:.*$", log, re.M)
        if unproven and unproven.group(1) != "0":
            # equiv_induct leaving cells unproven is not a counterexample:
            # it means induction at this depth could not close them. Report
            # it as unproven so it is never read as a proof of difference.
            status = f"UNPROVEN ({unproven.group(1)} cells) at depth {depth}"
        elif err:
            status = f"YOSYS_ERROR: {err.group(0)[:120]}"
        else:
            status = "AMBIGUOUS"
    return {
        "module": module,
        "pass": "yosys-equiv",
        "equivalent": ok,
        "status": status,
        "seconds": round(time.time() - t0, 1),
        "failed_partitions": [],
        "log_tail": log.strip().splitlines()[-8:] if not ok else [],
    }


def netlist_modules(netlist: Path) -> list[str]:
    """Module names in the netlist, in file order.

    `$paramod$<hash>\\name` modules are parameterized instances; they have no
    same-named counterpart in the RTL, so they are skipped here and covered
    instead by the proof of whichever module instantiates them.
    """
    names = []
    for m in re.finditer(r"^module\s+([A-Za-z_][\w$\\]*)\s*\(", netlist.read_text(), re.M):
        name = m.group(1)
        if name.startswith("$paramod"):
            continue
        names.append(name)
    return names


def run_one(module, rtl, netlist, liberty, stub, depth, timeout, workroot, label, partition):
    workdir = workroot / f"{module}.{label}"
    shutil.rmtree(workdir, ignore_errors=True)
    workdir.parent.mkdir(parents=True, exist_ok=True)
    cfg = CFG.format(
        stub_gold=f"read_verilog -lib {stub}\n" if stub else "",
        stub_gate=f"read_verilog -lib {stub}\n" if stub else "",
        rtl=" ".join(str(f) for f in rtl),
        netlist=netlist,
        liberty=liberty,
        module=module,
        depth=depth,
        partition=partition,
        engine=SMT_ENGINE,
    )
    cfg_path = workroot / f"{module}.{label}.eqy"
    cfg_path.write_text(cfg)

    t0 = time.time()
    try:
        proc = subprocess.run(
            ["eqy", "-f", "-d", str(workdir), str(cfg_path)],
            cwd=workroot,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        log = proc.stdout + proc.stderr
        rc = proc.returncode
    except subprocess.TimeoutExpired:
        return {
            "module": module,
            "pass": label,
            "equivalent": False,
            "status": f"TIMEOUT after {timeout}s",
            "seconds": round(time.time() - t0, 1),
            "failed_partitions": [],
            "log_tail": [],
        }

    # EQY gives a reason for every partition it could not close, and the three
    # reasons are not the same claim. "partitions not equivalent" is a
    # counterexample: the designs really do differ. "equivalence unknown" and
    # "timeout" are the solver running out of depth or clock, which says
    # nothing about the design. Collapsing all three into NOT_EQUIVALENT
    # reports a disproof the tool never made -- and on this benchmark it did:
    # `timer` was labelled NOT_EQUIVALENT on the strength of a partition whose
    # own log line read "equivalence unknown".
    reasons = set(re.findall(
        r"Could not prove equivalence of partition '[^']+' using strategy "
        r"'[^']+': (partitions not equivalent|equivalence unknown|timeout)",
        log))
    if re.search(r"Successfully proved designs? equivalent", log):
        status, ok = "PROVED_EQUIVALENT", True
    elif "partitions not equivalent" in reasons:
        status, ok = "NOT_EQUIVALENT", False
    elif reasons:
        why = "timeout" if "timeout" in reasons else "equivalence unknown"
        status, ok = f"UNPROVEN_EQY ({why}) at depth {depth}", False
    elif re.search(r"Failed to prove equivalence", log):
        status, ok = "NOT_EQUIVALENT", False
    else:
        # eqy exited without a clear verdict -- never call that a pass
        err = re.search(r"^ERROR:.*$", log, re.M)
        status = f"EQY_ERROR: {err.group(0)[:120]}" if err else f"AMBIGUOUS (rc={rc})"
        ok = False

    failed = re.findall(r"Failed to prove equivalence of partition (\S+)", log)
    return {
        "module": module,
        "pass": label,
        "equivalent": ok,
        "status": status,
        "seconds": round(time.time() - t0, 1),
        "failed_partitions": failed[:10],
        "log_tail": log.strip().splitlines()[-8:] if not ok else [],
    }


def check_module(module, rtl, netlist, liberty, stub, depth, timeout, workroot,
                 eqy_passes=True):
    """
    `eqy_passes=False` goes straight to the plain yosys miter.

    That is the right order once cut-points are in play. EQY's partitioned and
    merged passes each burn a full timeout on a module whose children are
    boxed, and then the fallback proves it in seconds -- fp4_dot_unit spent
    1800s failing two passes before yosys-equiv finished it in 5.4s. Boxing the
    children is what made the module easy; paying for the partitioner to
    rediscover that is pure waste.
    """
    attempts = []
    for label, partition in (PASSES if eqy_passes else []):
        r = run_one(
            module, rtl, netlist, liberty, stub, depth, timeout, workroot, label, partition
        )
        attempts.append(r)
        if r["equivalent"]:
            break
    if not attempts or not attempts[-1]["equivalent"]:
        attempts.append(
            run_yosys_equiv(module, rtl, netlist, liberty, stub, depth, timeout, workroot)
        )
    final = dict(attempts[-1])
    final["attempts"] = [
        {"pass": a["pass"], "status": a["status"], "seconds": a["seconds"]} for a in attempts
    ]
    # The reported verdict is the last attempt's, because a later pass is
    # strictly stronger than the one before it -- partitioning invents failures
    # that merging and the flat miter do not have. But a partitioned pass
    # claiming NOT_EQUIVALENT is still the only signal in the whole wrapper
    # that points at a genuine difference, and burying it inside `attempts`
    # means a real broken edit would be reported under whatever the flat miter
    # happened to say. Surface the claim without promoting it to the verdict:
    # it is a lead to chase, not a disproof, and the field name says so.
    claimed = [a["pass"] for a in attempts
               if not a["equivalent"] and a["status"] == "NOT_EQUIVALENT"]
    if claimed and not final["equivalent"]:
        final["counterexample_claimed_by"] = claimed
    final["seconds"] = round(sum(a["seconds"] for a in attempts), 1)
    return final


def main():
    require_solver()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rtl", nargs="+", required=True, help="RTL files, or a directory of them")
    ap.add_argument("--netlist", required=True)
    ap.add_argument("--liberty", required=True)
    ap.add_argument("--macro-stub", help="blackbox stubs, read on both sides")
    ap.add_argument("--modules", nargs="*", help="check only these (default: all in the netlist)")
    ap.add_argument("--skip", nargs="*", default=[], help="module names to leave out")
    ap.add_argument("--no-eqy-passes", action="store_true",
                    help="skip EQY's partitioned/merged passes and use the "
                         "plain yosys miter directly; right choice when child "
                         "modules are cut out via --macro-stub")
    ap.add_argument("--depth", type=int, default=5)
    ap.add_argument("--timeout", type=int, default=900, help="per module, seconds")
    ap.add_argument("--workdir", default="artifacts/eqy/netlist_work")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    rtl = []
    for entry in args.rtl:
        p = Path(entry)
        rtl.extend(sorted(p.glob("*.v")) if p.is_dir() else [p])
    rtl = [f.resolve() for f in rtl]

    stub = Path(args.macro_stub).resolve() if args.macro_stub else None
    if stub:
        # A macro's behavioural model must never be read alongside its
        # blackbox stub -- the same module would be declared twice and EQY
        # fails while combining the two designs. Drop any RTL file that
        # defines a module the stub already declares.
        boxed = set(re.findall(r"^module\s+(\w+)", stub.read_text(), re.M))
        dropped = [f for f in rtl if boxed & set(re.findall(r"^module\s+(\w+)", f.read_text(), re.M))]
        for f in dropped:
            print(f"skipping {f.name}: blackboxed by {stub.name}", file=sys.stderr)
        rtl = [f for f in rtl if f not in dropped]

    netlist = Path(args.netlist).resolve()
    liberty = Path(args.liberty).resolve()
    modules = args.modules or netlist_modules(netlist)
    modules = [m for m in modules if m not in args.skip]

    workroot = Path(args.workdir).resolve()
    workroot.mkdir(parents=True, exist_ok=True)

    results = []
    for module in modules:
        r = check_module(module, rtl, netlist, liberty, stub, args.depth,
                         args.timeout, workroot,
                         eqy_passes=not args.no_eqy_passes)
        results.append(r)
        mark = "PASS" if r["equivalent"] else "FAIL"
        print(
            f"{mark:4}  {module:32} {r['status']}  [{r['pass']}]  ({r['seconds']}s)",
            file=sys.stderr,
            flush=True,
        )

    passed = [r for r in results if r["equivalent"]]
    summary = {
        "netlist": str(netlist),
        "modules_checked": len(results),
        "modules_equivalent": len(passed),
        "all_equivalent": len(passed) == len(results),
        "skipped": args.skip,
        "results": results,
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, indent=2))
    print(f"\n{len(passed)}/{len(results)} modules proved equivalent -> {out}", file=sys.stderr)
    sys.exit(0 if summary["all_equivalent"] else 1)


if __name__ == "__main__":
    main()
