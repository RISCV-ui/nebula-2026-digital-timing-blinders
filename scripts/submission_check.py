#!/usr/bin/env python3
"""Check that the digital submission bundle still matches its evidence."""

import hashlib
import json
import os
import re
import sys


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def path(rel):
    return os.path.join(ROOT, rel)


def load(rel):
    with open(path(rel)) as fh:
        return json.load(fh)


def sha256(rel):
    h = hashlib.sha256()
    with open(path(rel), "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    required = [
        "artifacts/submission_20260911/lint.json",
        "artifacts/submission_20260911/synth.json",
        "artifacts/submission_20260911/eqy.json",
        "artifacts/submission_20260911/ppa.json",
        "artifacts/submission_20260911/toplevel_equiv.json",
        "artifacts/bakeoff_all_20260911/bakeoff_all.json",
        "artifacts/eqy/retry_summary_20260911.json",
        "artifacts/submission_20260911/raw/final_6_finish.rpt",
        "artifacts/submission_20260911/raw/baseline_6_finish.rpt",
        "output/result_assets/data/all_results.json",
        "output/result_assets/figures/03_model_gate_outcomes.png",
        "output/result_assets/figures/08_physical_ppa.png",
        "output/result_assets/figures/09_formal_verification.png",
        "output/pdf/Nebula_Digital_Final_Report.pdf",
    ]
    missing = [p for p in required if not os.path.isfile(path(p))]
    if missing:
        print("FAIL missing: " + ", ".join(missing))
        return 1

    lint = load("artifacts/submission_20260911/lint.json")
    synth = load("artifacts/submission_20260911/synth.json")
    eqy = load("artifacts/submission_20260911/eqy.json")
    ppa = load("artifacts/submission_20260911/ppa.json")
    top = load("artifacts/submission_20260911/toplevel_equiv.json")
    bake = load("artifacts/bakeoff_all_20260911/bakeoff_all.json")
    retry = load("artifacts/eqy/retry_summary_20260911.json")

    checks = {
        "lint_final_tree": (lint.get("verdict") == "NO_NEW_WARNINGS" and
                            lint.get("candidate", {}).get("tree") ==
                            "artifacts/final_candidate/rtl"),
        "synthesis_report": synth.get("verdict") == "SYNTHESIS_VALID",
        "eqy_no_counterexamples": (eqy.get("counts", {}).get("proved") == 36 and
                                    eqy.get("counts", {}).get("not_equivalent") == 0),
        "top_level_contract": (top.get("verdict") ==
                               "EQUIVALENT_MODULO_DECLARED_STREAM_LATENCY" and
                               top.get("ordinary_top_level_equivalence") ==
                               "NOT_EQUIVALENT"),
        "final_ppa_stage": (ppa.get("stage") == "6_final" and
                            ppa.get("after") == "final_candidate_signoff"),
        "target_fmax": any(c.get("clock") == "clk_s5" and
                           c.get("fmax_before") == 25.65 and
                           c.get("fmax_after") == 89.09
                           for c in ppa.get("clocks", [])),
        "clock_count": (ppa.get("clock_summary", {}).get("met_after") == 9 and
                         ppa.get("clock_summary", {}).get("constrained") == 11 and
                         ppa.get("clock_summary", {}).get("unreported") == 4),
        "eqy_retry_recorded": (retry.get("verdict") == "NO_IMPROVEMENT" and
                               retry.get("new_proofs") == 0 and
                               retry.get("final_proved") == 36),
    }

    arms = {a["arm"]: a for a in bake.get("arms", [])}
    ultra = arms.get("openrouter:nemotron-ultra", {})
    gemma = arms.get("openrouter:gemma-free", {})
    checks["bakeoff_audit"] = (ultra.get("raw_accepted") == 2 and
                               ultra.get("accepted") == 1 and
                               len(ultra.get("invalid_accepts", [])) == 1)
    checks["gemma_rate_limit_recorded"] = (gemma.get("tested") is False and
                                            gemma.get("died_at", {}).get("backend") == 1)

    # Matching the rounded ORFS report prevents an extractor-only number from
    # becoming the headline when the signoff tool itself says something else.
    finish = open(path("artifacts/submission_20260911/raw/final_6_finish.rpt")).read()
    base_finish = open(path("artifacts/submission_20260911/raw/baseline_6_finish.rpt")).read()
    checks["final_matches_orfs"] = ("tns max -1.95" in finish and
                                    "wns max -0.17" in finish)
    checks["baseline_matches_orfs"] = ("tns max -3384.44" in base_finish and
                                       "wns max -25.25" in base_finish)

    for name, ok in checks.items():
        print(f"{'PASS' if ok else 'FAIL'}  {name}")

    print("\nRecorded negative results:")
    print("  PPA regressions: " + ", ".join(ppa["clock_summary"]["regressed"]))
    print("  EQY incomplete: 10 timeout, 7 unproven, 1 tool error")
    print("  EQY deeper retry: 0 new proofs; 36/54 remains")
    print("  Ordinary top-level cycle equivalence: NOT_EQUIVALENT (+4-cycle contract)")
    print("  Gemma free: NOT TESTED (HTTP 429 before a gate)")
    print("  Paid Claude: PENDING")
    print("  Demo video: PENDING")

    print("\nKey SHA-256:")
    for rel in required[:6] + ["output/pdf/Nebula_Digital_Final_Report.pdf"]:
        print(f"  {sha256(rel)}  {rel}")

    failed = [name for name, ok in checks.items() if not ok]
    print("\n" + ("READY_EXCEPT_PAID_MODEL_AND_VIDEO" if not failed else
                   "NOT_READY: " + ", ".join(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
