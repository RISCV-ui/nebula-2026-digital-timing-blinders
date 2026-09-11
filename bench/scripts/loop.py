#!/usr/bin/env python3
"""
The optimisation loop.

    slice -> propose -> G1 equivalence -> G2 CDC -> (G3 place and route)

Gate order is deliberate and is the cheapest-first rule from DECISIONS D1. A
structural validation costs milliseconds, G1 costs seconds to minutes, G2
costs milliseconds, and G3 costs an hour and a half. Anything a cheap gate can
reject must never reach an expensive one, so G3 runs once at the end over the
accepted set rather than once per proposal.

Every proposal is written to a JSON-lines history whether it was accepted or
not. Rejections are the more useful half of that record: they are what the
report's accept-rate is computed from, they are what the retry prompt quotes
back to the model, and they are what stops the loop paying for the same bad
idea twice.
"""
import argparse
import glob, json, os, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import transforms as T
import g2_cdc
import g1b_contract
import g1c_stream
import g1_equiv as G1
import clockcheck
import llm as LLM

SYSTEM = """You optimise Verilog RTL to close timing. You are given one
critical path from a placed and routed design, the RTL module that owns most
of its delay, and a catalogue of transforms you may apply.

Reply with a single JSON object and nothing else:

  {"transform": "<catalogue name>",
   "module": "<module you are rewriting>",
   "latency_delta": <integer cycles the module's outputs are delayed by>,
   "rtl": "<the complete rewritten module, module...endmodule>",
   "submodules": {"<child module name>": "<its complete rewritten source>"},
   "reason": "<one or two sentences: which part of the path this shortens>"}

`submodules` is optional and usually absent. Include it only when the
transform genuinely spans two levels -- pipelining a combinational child, for
example, puts the stage registers inside the child and the control that tracks
them in the parent, and neither half is correct on its own. A child listed
there may change its own port list, because parent and child are replaced
together. A child that anything OUTSIDE this proposal instantiates may not be
listed at all; that is checked and will reject your answer.

Rules that are checked mechanically and will reject your answer:
  - `rtl` must define exactly the module named in `module`, with an identical
    port list: same names, same directions, same widths. This applies to the
    target module only; a module listed in `submodules` may change its ports.
  - `latency_delta` must be 0 for a latency-preserving transform, and the
    exact number of cycles added for a latency-changing one. A wrong value is
    a rejection, not a rounding error.
  - You may not edit a module that carries a clock-domain crossing.
  - Preserve the module's existing reset behaviour. In particular, a register
    you ADD to a feed-forward datapath must not be given a reset the original
    module did not have. Such a register holds no state that has to be
    recovered, a reset on it is wasted area, and it makes the module disagree
    with its own unpipelined self for as long as reset is asserted -- which
    the equivalence check reports as a counterexample. Write the new stage as
    a bare `always @(posedge clk) q <= d;` with no reset branch.

If no catalogue transform helps this path, reply {"refused": "<why>"}.
"""


def prompt_for(target, rtl_dir):
    """The user half of the call. The catalogue lives in the cached system half."""
    tgt = target.get("target") or {}
    mod = tgt.get("module")
    _, src = T.module_source(mod, rtl_dir)
    breakdown = "\n".join(
        f"  {v['share_pct']:5.1f}%  {v['delay_ns']:8.3f} ns  {v['module']:<24s}"
        f" {', '.join(v['instances'][:4])}"
        for v in (target.get("module_totals") or [])[:6])

    # The instance paths are in the prompt on purpose. The slicer names the
    # module carrying the most delay, but the edit that fixes it is not always
    # in that module: three sibling instances of one adder chained inside a
    # single parent are shortened by pipelining the parent, not by touching
    # the adder. The model cannot see that from the module source alone.
    parents = sorted({"/".join(i.split("/")[:-1])
                      for i in tgt.get("instances", []) if "/" in i})
    parent_note = ("\nAll of them sit under " + parents[0]
                   if len(parents) == 1 else
                   "\nThey sit under: " + "; ".join(parents) if parents else "")

    inst = tgt.get("instances") or []
    where = (f"{mod} appears on this path {len(inst)} "
             f"{'time' if len(inst) == 1 else 'times'}, as\n"
             f"{', '.join(inst)}.{parent_note}\n" if inst else
             f"{mod} is on this path as the module containing it.\n")

    # A derived target is a module the walk reached by going UP from the one
    # the slicer named, and it is only worth calling because the fix spans
    # levels. So the chain below it ships with the prompt: without the child's
    # source the model is being asked to pipeline something it cannot see, and
    # the `submodules` field it was told about has nothing to be filled from.
    chain = [c for c in (target.get("chain") or []) if c != mod]
    below = ""
    if chain:
        # chain is ordered bottom-up, so each entry's instantiator is the
        # next one along, and `mod` instantiates the last. Naming the wrong
        # one is the same mistake as copying the child's instance paths: a
        # detail the model will try to reconcile instead of ignoring.
        parts = []
        for i, name in enumerate(chain):
            _, csrc = T.module_source(name, rtl_dir)
            if csrc:
                by = chain[i + 1] if i + 1 < len(chain) else mod
                parts.append(f"SOURCE OF {name}, which {by} instantiates:\n"
                             f"{csrc}\n")
        if parts:
            below = ("\nThis target was reached by walking up from "
                     f"{chain[0]}. A transform here may rewrite the modules "
                     "below it as well, using `submodules` -- their sources "
                     "follow.\n\n" + "\n".join(parts))

    return f"""TARGET MODULE: {mod}

Clock {target['clock']}. Slack {target['slack_ns']} ns.
Combinational delay {target['combinational_delay_ns']} ns over {target.get('stages')} stages.
Start {target.get('startpoint')}
End   {target.get('endpoint')}

This path's delay by RTL module:
{breakdown}

{where}
This module is blamed for {target.get('paths_covered', 1)} distinct critical
paths covering {target.get('endpoint_count', 1)} endpoints, so a fix here is
worth more than its own slack suggests.

CURRENT SOURCE OF {mod}:
{src}
{below}"""


def feed_forward(src):
    """
    True when no register in the module depends on a register's own held
    value, directly or through combinational logic.

    This is what licenses the reduced proof depth of DECISIONS D12. In a
    feed-forward datapath every output cycle past the fill is a fresh
    function of that cycle's inputs, so `latency + 2` covers every distinct
    case and the proof is complete. A counter (`c <= c + 1`) or any state
    machine fails this, and those keep the bounded depth-12 check.

    The claim is checked against the candidate RTL rather than taken from the
    catalogue, because the catalogue describes what a transform usually does
    and the depth reduction has to be true of what it actually did.
    """
    seq = {}
    for _clk, text in g2_cdc.blocks(src):
        for lhs, rhs in g2_cdc.assignments(text):
            seq.setdefault(lhs, set()).update(g2_cdc.idents(rhs))
    conts = {}
    for m in re.finditer(
            r"\bassign\s+([A-Za-z_][\w$]*)\s*(?:\[[^\]]*\])*\s*=\s*([^;]*);",
            src):
        conts.setdefault(m.group(1), set()).update(g2_cdc.idents(m.group(2)))

    regs = set(seq)

    def reaches(start, seen):
        """Registers in the combinational cone feeding `start`."""
        out = set()
        stack = list(start)
        while stack:
            s = stack.pop()
            if s in seen:
                continue
            seen.add(s)
            if s in regs:
                out.add(s)
                continue          # stop at a register: its own inputs are next cycle
            stack.extend(conts.get(s, ()))
        return out

    for reg, rhs in seq.items():
        if reaches(rhs, set()) & regs:
            return False
    return True


def stateless(rtl_dir, module):
    """
    True when the elaborated module holds no state at all: no flop, no latch,
    no memory.

    Asked of the elaborated design rather than the source on purpose. Scanning
    for `always @(posedge ...)` misses a latch accidentally inferred by an
    incomplete `always @(*)`, and a latch is state -- a module with one is not
    combinational however it reads. Yosys has already decided the question by
    the time it emits cells, so ask it.
    """
    files = sorted(glob.glob(os.path.join(rtl_dir, "*.v")))
    ys = ("\n".join(f"read_verilog -defer {f}" for f in files) +
          f"\nhierarchy -check -top {module}\nproc\nopt_expr\nopt_clean\nstat\n")
    r = subprocess.run(["yosys", "-p", ys], capture_output=True, text=True)
    if r.returncode != 0:
        return False          # cannot tell -> do not claim completeness
    stat = r.stdout[r.stdout.rfind("Printing statistics"):]
    return not re.search(r"\$(dff|dffe|adff|sdff|dlatch|dffsr|mem|sr)\b", stat)


def gate1(golden, cand, module, latency, clock, feed_forward, timeout,
          transform=None):
    """
    Depth follows DECISIONS D12: latency + 2 is complete for a feed-forward
    register insertion, so paying for depth 12 there buys nothing. Anything
    else stays on the bounded depth-12 check and is reported as bounded.

    D16 adds the other complete case, and it is the cheaper one. A module that
    holds no state is a pure function of its inputs, so a single cycle of the
    miter already covers every distinct case there is: two combinational
    circuits that agree on all inputs for one cycle agree forever. Depth buys
    literally nothing, and the verdict is a complete proof of equivalence, not
    a bounded one. Both sides must be stateless -- if the transform introduced
    a flop the miter is a sequential problem again.
    """
    comb = (latency == 0
            and stateless(golden, module) and stateless(cand, module))
    if comb:
        depth = 1
    elif feed_forward and latency:
        depth = latency + 2
    else:
        depth = 12
    cmd = [sys.executable, os.path.join(HERE, "g1_equiv.py"),
           "--golden", golden, "--candidate", cand, "--module", module,
           "--latency", str(latency), "--depth", str(depth),
           "--timeout", str(timeout), "--json"]
    if clock:
        cmd += ["--clock", clock]
    # Only the bounded branch needs the observability probe. The other two
    # depths are complete proofs: depth 1 on a stateless module is the whole
    # theorem, and latency+2 on a feed-forward insertion is derived from the
    # latency itself, so the window is known to reach the outputs. The bounded
    # depth 12 is a constant that knows nothing about the module, and a module
    # deeper than 11 flops would pass it without the miter ever comparing a
    # value that depends on an input. Measured on fp4_dot_unit, whose output
    # is four flops behind its inputs: a deliberately mis-wired retime passed
    # at depth 4 in 2.6s and was rejected at depth 5 with a cycle-5
    # counterexample.
    if depth == 12:
        cmd += ["--observe"]

    # A re-encoded FSM cannot be proven from an all-zero start state: all-zeros
    # is a different state under a different encoding, so the two halves
    # disagree on cycle 0 for a reason that has nothing to do with the edit.
    # Holding reset for one cycle on both halves is what makes the encodings
    # correspond. The port names come from the module, not from --clock: that
    # flag carries an SDC clock name like clk_s5, which is not a port on
    # anything.
    if transform == "fsm_encode":
        _, gsrc = T.module_source(module, golden)
        pins = T.ports(gsrc or "")
        ck = next((c for c in G1.CLOCK_NAMES if c in pins), None)
        rs = next((r for r in G1.RESET_NAMES if r in pins), None)
        if not (ck and rs):
            return {"verdict": "ERROR", "depth": depth, "complete": False,
                    "proof": "bounded",
                    "detail": f"fsm_encode needs an active-high synchronous "
                              f"reset and a clock on {module}; its ports are "
                              f"{sorted(pins)}"}
        cmd = [c for c in cmd]
        if "--clock" in cmd:
            cmd[cmd.index("--clock") + 1] = ck
        else:
            cmd += ["--clock", ck]
        cmd += ["--reset-align", rs]

    r = subprocess.run(cmd, capture_output=True, text=True)
    d = LLM.extract_json(r.stdout) or {}
    d.setdefault("verdict", "ERROR")
    d["complete"] = bool(comb or (feed_forward and latency))
    d["proof"] = ("combinational" if comb else
                  "feed-forward" if (feed_forward and latency)
                  else "bounded")
    d["depth"] = depth
    return d


def select(targets, rtl_dir, max_slack, with_parents, depth=2):
    """
    Which targets are worth a model call.

    Each exists because a call is the scarce resource here.

    Three filters, described in the order they cut.

    First, slack. Fmax is set by the one clock that fails, so shortening a path
    with +20 ns of slack changes no number anyone reports; on this design 11 of
    the slicer's 12 targets are already met. Default `max_slack` is 0.0, i.e.
    only paths that actually violate.

    Second, parents. The slicer names the module carrying the most delay, and
    that is not always the module the fix belongs in: the worst path here runs
    through three sibling `fp8_adder` instances chained inside one
    `fp4_dot_unit`, and no edit to `fp8_adder` can pipeline a chain that lives
    in its parent. So the common parent of the target's instance paths is
    appended as a second candidate, after the slicer's own pick -- the cheap
    local edit is tried first, and the structural one is there when it is not
    enough.
    """
    keep = [t for t in targets if t.get("slack_ns", 0.0) <= max_slack]

    # Third filter, and the sharpest one: the slicer's lever. A path that
    # violates by less than the gate-level flow can recover is not an RTL
    # problem, and spending a call plus an equivalence proof on it duplicates
    # work the synthesiser does for free. On this design that removes
    # `mem_axi_slave` at -1.303 ns and leaves `fp8_adder` at -23.083 ns, which
    # is the only path here no amount of sizing can close. Targets from an
    # older slicer run carry no lever field; those are kept, so the filter can
    # only ever narrow a set it understands.
    keep = [t for t in keep
            if (t.get("lever") or {}).get("lever", "rtl") == "rtl"]
    if not with_parents:
        return keep

    # Walk UP the instantiation chain, not one step but as far as
    # `depth`, appending each level as its own candidate after the slicer's
    # pick. One step is not enough on this design and the reason is
    # structural: `fp8_adder` owns the delay, its parent `fp4_dot_unit` owns
    # the chain that has to be cut, and the *grand*parent `fp4_dot_stage` owns
    # the FIFO handshake that has to absorb the added latency. Stopping at one
    # level names a module that cannot hold the fix.
    #
    # The walk stops the moment a module has more than one instantiator. Above
    # that point an edit is no longer local to this path, and a candidate the
    # loop cannot reason about is worse than no candidate.
    have = {t["target"]["module"] for t in keep}
    out = []
    for t in keep:
        out.append(t)
        cur = t["target"]["module"]
        for _ in range(depth):
            callers = T.instantiators(cur, rtl_dir)
            if len(callers) != 1:
                break
            parent = callers.pop()
            if parent in T.CDC_MODULES or parent in have:
                break
            have.add(parent)
            p = json.loads(json.dumps(t))
            # The parent's instance paths are the child's with one segment
            # dropped: `fp8_adder` at dot_0/fp4_dot_0/add2 is instantiated by
            # `fp4_dot_unit` at dot_0/fp4_dot_0. Copying the child's paths
            # verbatim -- which is what this used to do -- told the model that
            # fp4_dot_stage appears three times on the path as add2, add5 and
            # add6, which is false and is exactly the kind of wrong detail a
            # model will try to reconcile rather than ignore.
            below = (out[-1]["target"].get("instances") or [])
            up = sorted({"/".join(i.split("/")[:-1])
                         for i in below if "/" in i})
            p["target"] = {"module": parent,
                           "delay_ns": t["target"].get("delay_ns"),
                           "share_pct": t["target"].get("share_pct"),
                           "instances": up}
            p["derived"] = f"instantiates {cur}"
            # Every module between the original slicer pick and this one. The
            # fix for an elastic parent puts stage registers in the child and
            # the control that tracks them in the parent, so the model has to
            # see the child's source to write either half.
            p["chain"] = (t.get("chain") or [t["target"]["module"]])
            if cur not in p["chain"]:
                p["chain"] = p["chain"] + [cur]
            out.append(p)
            cur = parent
    return out


def _parent_module(child, rtl_dir):
    """The module that instantiates `child`, if exactly one does."""
    hits = set()
    for f in sorted(glob.glob(os.path.join(rtl_dir, "*.v"))):
        src = open(f, errors="ignore").read()
        for m in re.finditer(r"^\s*module\s+([A-Za-z_][\w$]*)", src, re.M):
            body = src[m.end():]
            end = body.find("endmodule")
            if end < 0:
                continue
            if re.search(rf"\b{re.escape(child)}\s+[A-Za-z_][\w$]*\s*\(",
                         body[:end]):
                hits.add(m.group(1))
    return hits.pop() if len(hits) == 1 else None


def run(args):
    targets = json.load(open(args.targets))
    if isinstance(targets, dict):
        targets = targets.get("paths") or targets.get("targets") or []
    rtl_for_select = args.rtl
    before = len(targets)
    targets = select(targets, rtl_for_select, args.max_slack,
                     not args.no_parents, args.parent_depth)
    print(f"{before} slicer targets -> {len(targets)} worth a call "
          f"(slack <= {args.max_slack} ns, lever=rtl"
          f"{'' if args.no_parents else ', parents included'})",
          file=sys.stderr)
    for t in targets:
        print(f"   {t['clock']:<10} slack {t['slack_ns']:>8.3f}  "
              f"{t['target']['module']}"
              f"{'   [' + t['derived'] + ']' if t.get('derived') else ''}",
              file=sys.stderr)
    backend = LLM.get(args.backend, args.mock_dir)

    os.makedirs(args.out, exist_ok=True)
    hist_path = os.path.join(args.out, "history.jsonl")
    hist = open(hist_path, "a")

    work = os.path.join(args.out, "rtl")          # accepted edits accumulate here
    if not os.path.exists(work):
        shutil.copytree(args.rtl, work)

    tried = set()                                  # (module, transform) memo
    accepted, rejected = [], []
    unavailable = False

    for n, tgt in enumerate(targets[:args.max_targets]):
        mod = (tgt.get("target") or {}).get("module")
        if not mod:
            continue
        if mod in T.CDC_MODULES:
            rejected.append((mod, "target owns a CDC; slicer should not have picked it"))
            continue

        feedback = ""
        took = None          # the (module, transform) this target settled on
        won = False
        for attempt in range(args.retries + 1):
            rec = {"iteration": n, "attempt": attempt, "module": mod,
                   "clock": tgt.get("clock"), "slack_ns": tgt.get("slack_ns"),
                   "paths_covered": tgt.get("paths_covered", 1),
                   "backend": backend.name, "t": time.time()}

            user = prompt_for(tgt, work) + feedback
            try:
                raw = backend.propose(SYSTEM + "\n\n" + T.prompt_catalog(),
                                      user)
            except LLM.BackendUnavailable as e:
                # The provider is down or rate-limiting. Record it, stop
                # asking, and keep every edit accepted so far -- an outage is
                # not a reason to throw away a proved optimisation.
                rec.update(stage="backend", verdict="UNAVAILABLE",
                           detail=str(e))
                hist.write(json.dumps(rec) + "\n"); hist.flush()
                print(f"backend unavailable, stopping early: {e}",
                      file=sys.stderr)
                unavailable = True
                break
            p = LLM.extract_json(raw)

            if p is None or "refused" in (p or {}):
                rec.update(stage="propose", verdict="REFUSED",
                           detail=(p or {}).get("refused", "unparseable reply"))
                hist.write(json.dumps(rec) + "\n"); hist.flush()
                rejected.append((mod, rec["detail"]))
                break

            proposal_module = p.get("module")
            key = (proposal_module, p.get("transform"))
            rec.update(proposal_module=proposal_module,
                       transform=p.get("transform"),
                       latency_delta=p.get("latency_delta"),
                       reason=p.get("reason"))
            # A derived prompt includes child source so the model can return a
            # coordinated parent+child edit, but the parent still has to be the
            # primary module. Otherwise a model can repeat an earlier child
            # rewrite and earn another acceptance without addressing this
            # target -- exactly what one bake-off arm did.
            if proposal_module != mod:
                detail = (f"proposal rewrites {proposal_module!r}, but this "
                          f"target is {mod!r}")
                rec.update(stage="validate", verdict="REJECTED", detail=detail)
                hist.write(json.dumps(rec) + "\n"); hist.flush()
                feedback = ("\n\nYour previous answer rewrote the wrong primary "
                            f"module. Return `{mod}` in `module`; put any "
                            "coordinated child rewrites in `submodules`.")
                continue
            # The memo stops a later target buying an idea an earlier target
            # already proved bad. It must not fire inside a target's own
            # repair loop: attempt 1 is the same module and the same transform
            # by design -- that is what a repair is -- and consulting the memo
            # there cancels the retry the feedback was written for.
            if attempt == 0 and key in tried:
                rec.update(stage="memo", verdict="SKIPPED",
                           detail="this module/transform pair already failed "
                                  "on an earlier target")
                hist.write(json.dumps(rec) + "\n"); hist.flush()
                break
            took = key

            ok, bad = T.validate(p, work)
            if not ok:
                rec.update(stage="validate", verdict="REJECTED", detail=bad)
                hist.write(json.dumps(rec) + "\n"); hist.flush()
                feedback = ("\n\nYour previous answer was rejected before any "
                            "proof ran:\n" + "\n".join(f"  - {b}" for b in bad))
                continue

            cand = os.path.join(args.out, f"cand_{n}_{attempt}")
            T.apply(p, cand, work)

            # Formal equivalence correctly passes identical inputs, so it
            # cannot distinguish a useful rewrite from a byte-for-byte repeat.
            # Reject the repeat before buying a proof or counting an accept.
            before = {os.path.basename(f): open(f, "rb").read()
                      for f in glob.glob(os.path.join(work, "*.v"))}
            after = {os.path.basename(f): open(f, "rb").read()
                     for f in glob.glob(os.path.join(cand, "*.v"))}
            if before == after:
                rec.update(stage="validate", verdict="REJECTED",
                           detail="proposal changes no RTL bytes")
                hist.write(json.dumps(rec) + "\n"); hist.flush()
                feedback = ("\n\nYour previous answer reproduced the current "
                            "RTL byte-for-byte. Propose a real change or "
                            "refuse this target.")
                continue

            lat = int(p.get("latency_delta") or 0)

            # Which equivalence obligation applies is decided by the child's
            # interface, not by how big the latency change is.
            #
            # A rigid module owes its parent a value on a fixed cycle, so a
            # cycle-exact miter is the right question and G1 asks it, with G1b
            # checking separately that the parent tolerates the shift.
            #
            # An elastic module sits behind FIFOs. The cycle a result lands on
            # is not observable there, and a cycle-exact miter run against a
            # correct elastic pipeline returns NOT_EQUIVALENT -- measured, not
            # assumed; it is what this branch was written for. So the
            # obligation becomes a stream contract instead: every operand pair
            # popped produces exactly one result pushed, right value, right
            # order, nothing lost, nothing invented, nothing stranded. That is
            # a stronger statement than "equal N cycles later", not a weaker
            # one, and G1c proves it against the golden module as reference,
            # so it subsumes G1 here rather than sitting beside it.
            elastic = g1c_stream.applies(cand, p["module"])

            if lat and elastic:
                rec["g1_skipped"] = ("elastic interface: cycle equivalence is "
                                     "not the contract, see g1c")
                g1c = g1c_stream.check(work, cand, p["module"], lat,
                                       depth=args.g1c_depth,
                                       timeout=args.g1_timeout)
                # The counterexample is kept, not just the verdict. A
                # rejection is the half of this record the report is built
                # from -- "the gate fired" is a claim, the trace is evidence.
                rec["g1c"] = {k: g1c.get(k) for k in
                              ("verdict", "seconds", "depth", "properties")}
                if g1c["verdict"] != "STREAM_EQUIVALENT":
                    rec["g1c"]["counterexample"] = (
                        g1c.get("counterexample") or g1c.get("detail") or "")[:4000]
                if g1c["verdict"] != "STREAM_EQUIVALENT":
                    rec.update(stage="g1c", verdict="REJECTED")
                    hist.write(json.dumps(rec) + "\n"); hist.flush()
                    feedback = (
                        "\n\nYour previous answer failed the stream contract "
                        f"its parent relies on ({g1c['verdict']}). This module "
                        "is read from two FIFOs and written to a third, so the "
                        "cycle a result appears on is not what has to be "
                        "preserved. What has to be preserved is that every "
                        "operand pair popped produces exactly one result "
                        "pushed, with the right value, in the right order, "
                        "never overflowing the destination, and never holding "
                        "a finished result while there is room to write it.\n"
                        + (g1c.get("counterexample")
                           or g1c.get("detail") or "")[:1200])
                    continue
            else:
                ff = feed_forward(p["rtl"])
                g1 = gate1(work, cand, p["module"], lat, args.clock, ff,
                           args.g1_timeout, p.get("transform"))
                rec["g1"] = g1
                if g1["verdict"] != "EQUIVALENT":
                    rec.update(stage="g1", verdict="REJECTED")
                    hist.write(json.dumps(rec) + "\n"); hist.flush()
                    feedback = ("\n\nYour previous answer failed formal "
                                f"equivalence ({g1['verdict']}). "
                                + (g1.get("counterexample_summary")
                                   or g1.get("counterexample", ""))[:1500])
                    continue

                # A latency change is only correct at module scope. Whether the
                # parent can absorb it is a different question, and one G1 is
                # structurally unable to ask -- see g1b_contract.py.
                if lat:
                    g1b = g1b_contract.check(work, cand, p["module"],
                                             timeout=args.g1_timeout)
                    rec["g1b"] = {"verdict": g1b["verdict"],
                                  "parents": g1b["parents"],
                                  "checks": [{k: c.get(k) for k in
                                              ("parent", "verdict", "seconds")}
                                             for c in g1b["checks"]]}
                    if g1b["verdict"] not in ("CONTRACT_HELD", "NO_PARENT"):
                        rec.update(stage="g1b", verdict="REJECTED")
                        hist.write(json.dumps(rec) + "\n"); hist.flush()
                        broke = ", ".join(c["parent"] for c in g1b["checks"]
                                          if c["verdict"] != "EQUIVALENT")
                        feedback = (
                            "\n\nYour previous answer was formally equivalent "
                            f"as a module, but it added {lat} cycle(s) of "
                            f"latency and the parent module(s) {broke} do not "
                            "tolerate that: they consume this module's output "
                            "in the same cycle they drive its inputs. Either "
                            "propose a latency-preserving rewrite of this "
                            "module (logic_restructure or retime, "
                            "latency_delta 0), or explain in `refused` why no "
                            "such rewrite exists.")
                        continue

            g2 = g2_cdc.check(work, cand, p["module"])
            rec["g2"] = {"verdict": g2["verdict"], "failures": g2["failures"],
                         "warnings": g2["warnings"]}
            if g2["verdict"] != "PASS":
                rec.update(stage="g2", verdict="REJECTED")
                hist.write(json.dumps(rec) + "\n"); hist.flush()
                feedback = ("\n\nYour previous answer was formally equivalent but "
                            "broke a clock-domain crossing:\n"
                            + "\n".join(f"  - {f}" for f in g2["failures"]))
                continue

            # G2c: clock structure. Neither equivalence nor STA can see a
            # runt pulse -- a combinational clock mux is *equivalent* to a
            # glitch-free one, and OpenSTA believes whatever net it was told
            # is a clock. So it gets its own structural check, and the loop
            # holds the model to the same rule as the baseline: it may inherit
            # a glitchy structure, it may not create one.
            g2c = clockcheck.regression(work, cand)
            rec["g2c"] = g2c
            if g2c["verdict"] != "PASS":
                rec.update(stage="g2c", verdict="REJECTED")
                hist.write(json.dumps(rec) + "\n"); hist.flush()
                feedback = ("\n\nYour previous answer was formally equivalent "
                            "but degraded a clock structure:\n"
                            + "\n".join(f"  - {f}" for f in g2c["failures"])
                            + "\nA clock must be driven by a flop, or by an "
                              "AND of a clock with an enable latched on the "
                              "clock's low phase. Never select or gate a clock "
                              "with plain combinational logic.")
                continue

            # Both cheap gates passed. Fold the edit into the working tree so
            # the next target sees it; G3 judges the accumulated set once.
            T.splice(p, work)
            rec.update(stage="accepted", verdict="ACCEPTED")
            hist.write(json.dumps(rec) + "\n"); hist.flush()
            accepted.append((mod, p["transform"], lat))
            won = True
            break

        if took and not won:
            tried.add(took)
        if unavailable:
            break

    hist.close()
    print(f"backend {backend.name}, {getattr(backend, 'calls', 0)} calls")
    print(f"accepted {len(accepted)}: " +
          ", ".join(f"{m}/{t}/+{l}" for m, t, l in accepted))
    for m, why in rejected:
        print(f"  rejected {m}: {why}")
    print(f"history -> {hist_path}")
    print(f"candidate RTL -> {work}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--targets", required=True, help="slicer --out JSON")
    ap.add_argument("--rtl", default=os.path.join(HERE, "..", "rtl"))
    ap.add_argument("--out", default="artifacts/loop")
    ap.add_argument("--backend", default="mock")
    ap.add_argument("--mock-dir", default="bench/mock_proposals")
    ap.add_argument("--clock", default=None)
    ap.add_argument("--max-targets", type=int, default=12)
    ap.add_argument("--max-slack", type=float, default=0.0,
                    help="only spend a call on paths with slack <= this (ns)")
    ap.add_argument("--parent-depth", type=int, default=2,
                    help="how many levels up the instantiation chain to offer "
                         "as additional targets")
    ap.add_argument("--no-parents", action="store_true",
                    help="do not add the target's parent as a second candidate")
    ap.add_argument("--retries", type=int, default=2,
                    help="repair attempts per target after a gate rejection")
    ap.add_argument("--g1-timeout", type=int, default=1800)
    ap.add_argument("--g1c-depth", type=int, default=16,
                    help="bounded depth for the stream proof. 16 with the "
                         "datapath abstracted costs single-digit seconds and "
                         "is deep enough to fill and then starve a 4-stage "
                         "pipeline, which is what the drain property needs; "
                         "against the real arithmetic the same bound does not "
                         "finish in 40 minutes")
    sys.exit(run(ap.parse_args()))


if __name__ == "__main__":
    main()
