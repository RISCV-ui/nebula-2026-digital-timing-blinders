#!/usr/bin/env python3
"""
Stage 8: the actual agentic loop. Wires run_sta.py / run_synth.py / run_eqy.py
into the run_sta -> propose_and_apply_edit -> resynth_and_check cycle from
CLAUDE.md's architecture section.

    run_sta(netlist, sdc)            -> ranked critical-path JSON
    propose_and_apply_edit(...)      -> Claude tool-use call, RTL-only edit,
                                         one of: pipelining / logic_restructuring
                                         / retiming / fsm_recode
    resynth_and_check(orig, edited)  -> run_synth (re-synth) + run_sta
                                         (re-check slack) + run_eqy (formal
                                         equivalence gate). REJECTS the edit
                                         if EQY fails -- non-negotiable, per
                                         CLAUDE.md: never let an edit through
                                         without the equivalence gate.

Every edit is checked against the RTL it was derived from (not just the
original source) -- each accepted edit becomes the new gold reference for
the next iteration. A final whole-design EQY check (original vs last
accepted RTL) is left as a separate explicit step (see --final-check),
matching the two-EQY-checkpoint design in the book.

Usage (mock, no API key / no tokens spent, exercises the full loop machinery):
    python3 llm_loop.py --verilog designs/src/gcd/gcd.v --top gcd \
        --liberty platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
        --sdc designs/sky130hd/gcd/constraint.sdc \
        --run-id demo1 --max-edits 2 --mock

Usage (real):
    export ANTHROPIC_API_KEY=...
    python3 llm_loop.py --verilog designs/src/gcd/gcd.v --top gcd \
        --liberty platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
        --sdc designs/sky130hd/gcd/constraint.sdc \
        --run-id demo1 --max-edits 5
"""
import argparse
import json
import re
import subprocess
import sys
import textwrap
from pathlib import Path

FLOW_DIR = Path(__file__).resolve().parent
PY = sys.executable

sys.path.insert(0, str(FLOW_DIR))
import rtl_hierarchy

TECHNIQUES = ["pipelining", "logic_restructuring", "retiming", "fsm_recode"]

SYSTEM_PROMPT = textwrap.dedent("""\
    You are the RTL-optimization engine in an automated timing-closure loop
    for a chip design flow (sky130hd standard-cell library).

    You will be given: the current Verilog source of one module, the
    single worst timing-violating path in that module (as reported by
    OpenSTA), including its startpoint, endpoint, slack in nanoseconds, and
    the ordered chain of standard cells the signal passes through, and the
    module's current post-synthesis area/cell-count (and, from later edits
    onward, how much area has already grown relative to the original
    unedited design).

    Propose exactly ONE edit using exactly ONE of these four techniques:
      - pipelining: insert a register mid-path to split one slow cycle into two
      - logic_restructuring: rewrite logic to be functionally identical but
        with a shorter critical path
      - retiming: move an existing register earlier/later without adding new ones
      - fsm_recode: re-encode FSM states (e.g. one-hot vs binary)

    Rules:
      - Edit RTL ONLY. Never propose changing the SDC/constraints file.
      - The edit must be functionally equivalent to the original module
        (it will be formally checked with EQY -- if it's not equivalent,
        the edit is discarded and you'll be asked to try again).
      - Return the COMPLETE modified Verilog source for the module, not a
        diff or partial snippet.
      - If pipelining, you may add a pipeline register on the module's
        internal signals, but you must not change the module's port list
        or timing-visible latency contract in a way that breaks the
        surrounding design -- assume this module's ports are fixed.
      - Weigh area cost: prefer retiming or logic_restructuring over
        pipelining when either would close the path, since pipelining adds
        registers (and area) while retiming/restructuring do not.

    Call the propose_rtl_edit tool with your answer. Always call the tool;
    never answer in plain text.
""")

TOOL_SCHEMA = {
    "name": "propose_rtl_edit",
    "description": "Propose one timing-closure RTL edit for the given critical path.",
    "input_schema": {
        "type": "object",
        "properties": {
            "technique": {"type": "string", "enum": TECHNIQUES},
            "rationale": {"type": "string", "description": "One or two sentences: why this technique, why this edit fixes the path."},
            "modified_verilog": {"type": "string", "description": "Complete replacement source for the module."},
        },
        "required": ["technique", "rationale", "modified_verilog"],
    },
}


def run_subprocess_json(cmd, out_path):
    result = subprocess.run(cmd, cwd=FLOW_DIR, capture_output=True, text=True)
    if not Path(out_path).exists():
        raise RuntimeError(
            f"command produced no output ({' '.join(cmd)})\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    data = json.loads(Path(out_path).read_text())
    return data, result


SYNTH_RETRY_STRATEGIES = ["retime", "timing_driven"]


def synth(verilog_path, top, liberty, run_id, artifacts_dir, strategy=None, abc_period_ps=None,
          blackboxes=None):
    out = artifacts_dir / f"synth_{run_id}.json"
    cmd = [PY, "run_synth.py", "--verilog", str(verilog_path), "--top", top,
           "--liberty", str(liberty), "--run-id", run_id, "--out", str(out)]
    # Hard macros stay black boxes across every retry, so the netlist the loop
    # measures is the same netlist ORFS places -- macro instance, not inferred
    # flops.
    for b in (blackboxes or []):
        cmd += ["--blackbox", str(b)]
    if strategy:
        cmd += ["--strategy", strategy]
    if abc_period_ps:
        cmd += ["--abc-period-ps", str(abc_period_ps)]
    data, _ = run_subprocess_json(cmd, out)
    return data


def sta(netlist_path, top, sdc, liberty, run_id, artifacts_dir, group_count=10):
    out = artifacts_dir / f"sta_{run_id}.json"
    cmd = [PY, "run_sta.py", "--netlist", str(netlist_path), "--top", top,
           "--sdc", str(sdc), "--liberty", str(liberty),
           "--group-count", str(group_count), "--out", str(out)]
    data, _ = run_subprocess_json(cmd, out)
    return data


def eqy(gold_path, gate_path, top, run_id, artifacts_dir, blackboxes=None):
    out = artifacts_dir / f"eqy_{run_id}.json"
    cmd = [PY, "run_eqy.py", "--gold", str(gold_path), "--gate", str(gate_path),
           "--top", top, "--run-id", run_id, "--out", str(out)]
    for b in (blackboxes or []):
        cmd += ["--macro-stub", str(b)]
    result = subprocess.run(cmd, cwd=FLOW_DIR, capture_output=True, text=True)
    data = json.loads(out.read_text()) if out.exists() else {"equivalent": False, "status": f"NO_OUTPUT: {result.stderr[-500:]}"}
    return data


def worst_path_summary(sta_data):
    if not sta_data["paths"]:
        return None
    p = sta_data["paths"][0]
    lines = [
        f"Startpoint: {p['startpoint']} ({p['startpoint_desc']})",
        f"Endpoint: {p['endpoint']} ({p['endpoint_desc']})",
        f"Path group: {p['path_group']}  Type: {p['path_type']}",
        f"Slack: {p['slack']} ns ({p['status']})",
        f"Cell chain ({p['num_cells']} cells):",
    ]
    for c in p["cells"]:
        lines.append(f"  {c['pin']}  ({c['cell']})  delay={c['delay']}  t={c['time']}")
    return "\n".join(lines)


def ppa_summary(synth_data, baseline_synth_data=None):
    """Area/cell-count context for the LLM -- so edits aren't proposed blind
    to area cost. baseline_synth_data (edit 0's pre-edit synth) lets the
    model see cumulative area drift across the whole loop, not just this
    module's current snapshot."""
    lines = [
        f"Current area: {synth_data['area']}  Cell count: {synth_data['num_cells']}",
    ]
    if baseline_synth_data is not None:
        base_area = baseline_synth_data["area"]
        base_cells = baseline_synth_data["num_cells"]
        area_delta = synth_data["area"] - base_area
        pct = (area_delta / base_area * 100) if base_area else 0.0
        lines.append(
            f"Baseline (before any accepted edits): area={base_area}  "
            f"cells={base_cells}  (delta so far: {area_delta:+.2f}, {pct:+.1f}%)"
        )
    lines.append(
        "Prefer techniques that don't grow area unnecessarily (e.g. retiming "
        "over pipelining) when either would close the path, since pipelining "
        "adds registers/area and retiming does not."
    )
    return "\n".join(lines)


MODULE_RE_TEMPLATE = r"\bmodule\s+{}\b.*?\bendmodule\b"


def extract_module(src_text, module_name):
    m = re.search(MODULE_RE_TEMPLATE.format(re.escape(module_name)), src_text, re.DOTALL)
    if not m:
        raise ValueError(f"module {module_name} not found in source")
    return m.group(0)


def splice_module(full_src_text, module_name, new_module_text):
    """Replace only the named module's block in a (possibly multi-module)
    source file, leaving every other module in the file untouched. Needed
    because a design like gcd.v has submodules alongside the top module --
    swapping the whole file for just the edited top module would silently
    drop them."""
    pattern = re.compile(MODULE_RE_TEMPLATE.format(re.escape(module_name)), re.DOTALL)
    new_text, count = pattern.subn(lambda _: new_module_text, full_src_text, count=1)
    if count != 1:
        raise ValueError(f"expected exactly one occurrence of module {module_name} to replace, found {count}")
    return new_text


def propose_and_apply_edit_mock(module_src, worst_path_text, ppa_text, technique_cycle_idx):
    """No-op-ish edit for exercising the loop without spending tokens: adds
    a harmless comment, proving the mechanics (synth/sta/eqy/accept-reject)
    work. A real edit is what the live Claude call above produces instead."""
    technique = TECHNIQUES[technique_cycle_idx % len(TECHNIQUES)]
    edited = module_src.replace(
        "module ", f"// [mock {technique} edit -- no-op, for loop testing]\nmodule ", 1
    )
    return {
        "technique": technique,
        "rationale": "(mock) no-op passthrough edit to exercise the loop.",
        "modified_verilog": edited,
    }


def propose_and_apply_edit_live(client, module_src, worst_path_text, ppa_text):
    user_content = (
        f"Current module source:\n```verilog\n{module_src}\n```\n\n"
        f"Worst timing-violating path:\n```\n{worst_path_text}\n```\n\n"
        f"Area/PPA context:\n```\n{ppa_text}\n```\n\n"
        "Propose one edit via the propose_rtl_edit tool."
    )
    resp = client.messages.create(
        model="claude-sonnet-4-5",
        max_tokens=4096,
        system=SYSTEM_PROMPT,
        tools=[TOOL_SCHEMA],
        tool_choice={"type": "tool", "name": "propose_rtl_edit"},
        messages=[{"role": "user", "content": user_content}],
    )
    if resp.stop_reason != "tool_use":
        raise RuntimeError(f"expected tool_use, got stop_reason={resp.stop_reason}")
    for block in resp.content:
        if block.type == "tool_use" and block.name == "propose_rtl_edit":
            return block.input
    raise RuntimeError("no propose_rtl_edit tool_use block in response")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verilog", required=True, help="module source file (single module)")
    ap.add_argument("--top", required=True)
    ap.add_argument("--liberty", required=True)
    ap.add_argument("--sdc", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--max-edits", type=int, default=3, help="max accepted edits before stopping")
    ap.add_argument("--max-retries-per-path", type=int, default=2)
    ap.add_argument("--no-synth-retry", action="store_true",
                     help="skip the cheap synthesis-only retry tier, go straight to LLM RTL edits")
    ap.add_argument("--slack-threshold", type=float, default=0.0, help="stop once worst slack >= this")
    ap.add_argument("--blackbox", action="append", default=[],
                    help="stub file whose modules stay black boxes in every re-synth "
                         "(repeatable; the OpenRAM macro stubs go here)")
    ap.add_argument("--mock", action="store_true", help="skip the real API call, exercise loop mechanics only")
    args = ap.parse_args()

    artifacts_dir = FLOW_DIR / "artifacts" / "llm_loop" / args.run_id
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    client = None
    if not args.mock:
        import os
        if not os.environ.get("ANTHROPIC_API_KEY"):
            print("ERROR: ANTHROPIC_API_KEY not set (or pass --mock to test loop mechanics)", file=sys.stderr)
            sys.exit(1)
        sys.path.insert(0, str(FLOW_DIR / ".venv_llm/lib/python3.14/site-packages"))
        import anthropic
        client = anthropic.Anthropic()

    current_src_path = Path(args.verilog)
    gold_src_path = current_src_path  # original, unmodified reference for the final check
    module_name = args.top
    baseline_synth_data = None  # edit 0's pre-edit synth; area drift is measured against this

    print(f"=== Stage 8 loop start: run_id={args.run_id} mock={args.mock} ===", file=sys.stderr)

    for edit_num in range(args.max_edits):
        tag = f"{args.run_id}_e{edit_num}"

        # 1. run_sta (via synth -> netlist -> sta, since we start from RTL)
        synth_data = synth(current_src_path, module_name, args.liberty, f"{tag}_pre", artifacts_dir,
                           blackboxes=args.blackbox)
        if not synth_data["ok"]:
            print(f"[edit {edit_num}] synth FAILED, aborting: {synth_data.get('error')}", file=sys.stderr)
            sys.exit(1)
        sta_data = sta(synth_data["netlist"], module_name, args.sdc, args.liberty, f"{tag}_pre", artifacts_dir)
        wns = sta_data["wns"].get("max")
        print(f"[edit {edit_num}] pre-edit: cells={synth_data['num_cells']} area={synth_data['area']} wns={wns} violated={sta_data['num_violated']}/{sta_data['num_paths']}", file=sys.stderr)
        if baseline_synth_data is None:
            baseline_synth_data = synth_data

        if wns is None or wns >= args.slack_threshold:
            print(f"[edit {edit_num}] slack threshold met (wns={wns}) -- stopping, timing closed", file=sys.stderr)
            break

        # Synthesis-only retry tier: try cheap re-mapping strategies on the
        # SAME (unedited) RTL before ever calling the LLM. No RTL change
        # means no EQY needed -- source is byte-identical, equivalence is
        # trivial. Only escalate to an LLM RTL edit if none of these close
        # the gap; this is the answer to "how many times retry synthesis
        # before an RTL fix" -- capped at len(SYNTH_RETRY_STRATEGIES) tries.
        worst_path_for_period = sta_data["paths"][0]
        approx_period_ps = worst_path_for_period["data_required_time"] * 1000
        synth_retry_closed = False
        for strategy in ([] if args.no_synth_retry else SYNTH_RETRY_STRATEGIES):
            rtag = f"{tag}_synthretry_{strategy}"
            retry_kwargs = {"abc_period_ps": approx_period_ps} if strategy == "timing_driven" else {}
            synth_retry = synth(current_src_path, module_name, args.liberty, rtag, artifacts_dir,
                                 strategy=strategy, blackboxes=args.blackbox, **retry_kwargs)
            if not synth_retry["ok"]:
                print(f"[edit {edit_num}] synth-retry strategy={strategy}: synth FAILED -- skipping", file=sys.stderr)
                continue
            sta_retry = sta(synth_retry["netlist"], module_name, args.sdc, args.liberty, rtag, artifacts_dir)
            wns_retry = sta_retry["wns"].get("max")
            print(f"[edit {edit_num}] synth-retry strategy={strategy}: wns {wns} -> {wns_retry} "
                  f"violated {sta_data['num_violated']} -> {sta_retry['num_violated']}", file=sys.stderr)
            if wns_retry is not None and wns_retry >= args.slack_threshold and sta_retry["num_violated"] == 0:
                print(f"[edit {edit_num}] synth-retry strategy={strategy} CLOSED TIMING -- no RTL edit needed, stopping", file=sys.stderr)
                synth_retry_closed = True
                break
        if synth_retry_closed:
            break

        worst_text = worst_path_summary(sta_data)
        worst_path = sta_data["paths"][0]
        full_src_text = current_src_path.read_text()
        target_module = rtl_hierarchy.localize_edit_target(
            full_src_text, module_name, worst_path["startpoint"], worst_path["endpoint"]
        )
        print(f"[edit {edit_num}] localized worst path to module: {target_module}"
              + (" (top -- no deeper common submodule)" if target_module == module_name else ""),
              file=sys.stderr)
        module_src = extract_module(full_src_text, target_module)
        ppa_text = ppa_summary(synth_data, baseline_synth_data)

        accepted = False
        for retry in range(args.max_retries_per_path):
            if args.mock:
                proposal = propose_and_apply_edit_mock(module_src, worst_text, ppa_text, edit_num + retry)
            else:
                proposal = propose_and_apply_edit_live(client, module_src, worst_text, ppa_text)

            technique = proposal["technique"]
            edited_module_src = proposal["modified_verilog"]
            print(f"[edit {edit_num}] retry {retry}: LLM proposed technique={technique} rationale={proposal['rationale'][:120]!r}", file=sys.stderr)

            full_candidate_src = splice_module(current_src_path.read_text(), target_module, edited_module_src)
            candidate_path = artifacts_dir / f"{tag}_r{retry}_candidate.v"
            candidate_path.write_text(full_candidate_src)

            eqy_result = eqy(current_src_path, candidate_path, module_name, f"{tag}_r{retry}",
                             artifacts_dir, blackboxes=args.blackbox)
            if not eqy_result.get("equivalent"):
                print(f"[edit {edit_num}] retry {retry}: EQY REJECTED ({eqy_result.get('status')}) -- discarding edit", file=sys.stderr)
                continue

            synth_after = synth(candidate_path, module_name, args.liberty, f"{tag}_r{retry}_post",
                                artifacts_dir, blackboxes=args.blackbox)
            if not synth_after["ok"]:
                print(f"[edit {edit_num}] retry {retry}: post-edit synth FAILED -- discarding edit", file=sys.stderr)
                continue
            sta_after = sta(synth_after["netlist"], module_name, args.sdc, args.liberty, f"{tag}_r{retry}_post", artifacts_dir)
            wns_after = sta_after["wns"].get("max")

            # WNS alone isn't enough: an edit can improve the one targeted
            # path while regressing others (e.g. pipelining shifts latency
            # and breaks a previously-MET downstream path). Require the
            # violated-path count to not get worse too, else a "win" on
            # paper could be a net loss the loop would otherwise never see.
            wns_improved = wns_after is not None and wns is not None and wns_after > wns
            no_new_violations = sta_after["num_violated"] <= sta_data["num_violated"]
            improved = wns_improved and no_new_violations
            print(f"[edit {edit_num}] retry {retry}: EQY OK, wns {wns} -> {wns_after}, "
                  f"violated {sta_data['num_violated']} -> {sta_after['num_violated']}, improved={improved}", file=sys.stderr)

            if improved:
                current_src_path = candidate_path
                accepted = True
                break
            else:
                print(f"[edit {edit_num}] retry {retry}: no improvement -- discarding edit, retrying", file=sys.stderr)

        if not accepted:
            print(f"[edit {edit_num}] exhausted retries with no accepted edit -- stopping", file=sys.stderr)
            break

    print(f"=== Stage 8 loop end: final RTL = {current_src_path} ===", file=sys.stderr)
    summary = {
        "run_id": args.run_id,
        "original_verilog": str(gold_src_path),
        "final_verilog": str(current_src_path),
        "edits_accepted": current_src_path != gold_src_path,
    }
    (artifacts_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
