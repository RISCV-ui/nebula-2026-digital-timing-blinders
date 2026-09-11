#!/usr/bin/env python3
"""
lint.py -- lint the frozen RTL, lint the optimised RTL, and diff the two.

A lint report on one tree answers "is this code clean". That is not the
question this project has to answer. The RTL was already clean before the model
touched it, so the only claim worth making is that it is *still* clean
afterwards -- and specifically that no warning exists in the optimised tree
that did not exist in the frozen one. So this runs Verilator twice and diffs.

Diffing on line numbers would be useless: a pipeline transform inserts lines,
so every warning below the edit shifts and the diff reports the whole file as
new. The key is therefore (warning code, file basename, message text) with the
line number stripped out. Two warnings that say the same thing about the same
file are the same warning even if the edit moved one of them.

Verilator exits non-zero when it emits any warning at all, so the return code
says nothing about whether the tree regressed. This exits non-zero only when
the candidate introduces a warning the golden did not have, which is the
condition that should actually stop a flow.

    lint.py --golden bench/rtl
    lint.py --golden bench/rtl --candidate artifacts/wns/rtl \\
            --out artifacts/lint/report.json
"""

import argparse, glob, json, os, re, subprocess, sys
from collections import Counter

# Verilator prefixes every diagnostic with %Warning-CODE: or %Error-CODE:, then
# file:line:col, then the message. The continuation lines that follow (source
# excerpt, caret, "In instance ..." note) are context for a human and carry no
# identity of their own, so only the header line is parsed.
LINE_RE = re.compile(
    r"^%(?P<sev>Warning|Error)-(?P<code>[A-Z0-9_]+):\s+"
    r"(?P<file>[^:]+):(?P<line>\d+):(?P<col>\d+):\s+(?P<msg>.*)$")

# Syntax and elaboration failures use `%Error:` without a diagnostic code, so
# LINE_RE cannot see them. Treating an empty parsed warning list as clean made
# a syntactically invalid candidate pass the gate. The final "Exiting due to
# N warning(s)" line is excluded because warnings are compared separately.
ERROR_RE = re.compile(r"^%Error(?:-[A-Z0-9_]+)?:\s+(?P<msg>.*)$")


def run(tree, top, extra_args):
    files = sorted(glob.glob(os.path.join(tree, "*.v")))
    if not files:
        sys.exit(f"no .v files in {tree}")
    cmd = (["verilator", "--lint-only", "-Wall", "--top-module", top,
            "-I" + tree] + extra_args + files)
    p = subprocess.run(cmd, capture_output=True, text=True)
    out = p.stdout + p.stderr

    found = []
    errors = []
    for ln in out.splitlines():
        m = LINE_RE.match(ln)
        if m:
            d = m.groupdict()
            found.append({
                "severity": d["sev"],
                "code": d["code"],
                "file": os.path.basename(d["file"]),
                "line": int(d["line"]),
                "message": d["msg"].strip(),
                # identity without the line number, so an inserted pipeline stage
                # does not make every warning below it look new
                "key": f"{d['code']}|{os.path.basename(d['file'])}|{d['msg'].strip()}",
            })
            continue
        e = ERROR_RE.match(ln)
        if e and not e.group("msg").startswith("Exiting due to"):
            errors.append(e.group("msg").strip())
    return {"tree": tree, "files": len(files), "findings": found,
            "errors": errors, "returncode": p.returncode,
            "command": " ".join(cmd[:6] + ["..."]), "raw": out}


def summarise(r):
    c = Counter(f["code"] for f in r["findings"])
    return {"total": len(r["findings"]), "by_code": dict(c.most_common()),
            "by_file": dict(Counter(f["file"] for f in r["findings"]).most_common())}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--golden", required=True, help="frozen input RTL")
    ap.add_argument("--candidate", help="optimised RTL; omit to lint one tree")
    ap.add_argument("--top", default="soc_top")
    ap.add_argument("--out", default="artifacts/lint/report.json")
    ap.add_argument("--verilator-arg", action="append", default=[],
                    help="extra flag passed through to verilator")
    a = ap.parse_args()

    g = run(a.golden, a.top, a.verilator_arg)
    report = {"top": a.top, "golden": {**summarise(g), "tree": a.golden}}
    print(f"golden    {a.golden}: {len(g['findings'])} findings "
          f"over {g['files']} files")
    for k, v in summarise(g)["by_code"].items():
        print(f"    {v:3d}  {k}")

    verdict = "CLEAN" if not g["findings"] else "WARNINGS_ONLY_IN_BASELINE"
    rc = 0
    if g["errors"]:
        verdict, rc = "GOLDEN_ERROR", 1
        print(f"golden errors: {len(g['errors'])}")
        for err in g["errors"]:
            print(f"    {err}")

    if a.candidate:
        c = run(a.candidate, a.top, a.verilator_arg)
        gk = {f["key"] for f in g["findings"]}
        ck = {f["key"] for f in c["findings"]}
        new = [f for f in c["findings"] if f["key"] not in gk]
        fixed = [f for f in g["findings"] if f["key"] not in ck]

        report["candidate"] = {**summarise(c), "tree": a.candidate}
        report["introduced"] = new
        report["resolved"] = fixed

        print(f"candidate {a.candidate}: {len(c['findings'])} findings "
              f"over {c['files']} files")
        for k, v in summarise(c)["by_code"].items():
            print(f"    {v:3d}  {k}")
        print(f"introduced by optimisation: {len(new)}")
        for f in new:
            print(f"    {f['code']}  {f['file']}:{f['line']}  {f['message']}")
        print(f"resolved by optimisation:   {len(fixed)}")
        if c["errors"]:
            print(f"candidate errors: {len(c['errors'])}")
            for err in c["errors"]:
                print(f"    {err}")

        # The gate. A pre-existing warning is the design's, not the model's;
        # only a new one is evidence the optimisation hurt the code.
        if c["errors"]:
            verdict, rc = "REGRESSED", 1
        elif new:
            verdict, rc = "REGRESSED", 1
        elif fixed:
            verdict = "IMPROVED"
        else:
            verdict = "NO_NEW_WARNINGS"

    report["verdict"] = verdict
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as fh:
        json.dump(report, fh, indent=2)

    # The full verilator text is kept beside the JSON: the JSON is what the
    # report tables are built from, the text is the evidence behind them.
    for tag, r in (("golden", g), ("candidate", c if a.candidate else None)):
        if r:
            with open(os.path.splitext(a.out)[0] + f".{tag}.txt", "w") as fh:
                fh.write(r["raw"])

    print(f"\nverdict: {verdict}")
    print(f"wrote {a.out}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
