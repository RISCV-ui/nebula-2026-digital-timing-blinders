#!/usr/bin/env python3
"""
hierarchy.py -- instance path -> RTL module, built from the RTL itself.

The timing report names endpoints by their full instance path
(dot_0/fifo_timer_r/mem[13][5]$_DFFE_PP_/D). Turning that back into a source
file is the whole reason SYNTH_HIERARCHICAL=1 and -nofsm are set: the names
survive synthesis. What is missing is the map from a path prefix to the module
that prefix instantiates, and that only exists in the RTL.

Parsed by scanning for instantiations of names that are known modules, which
avoids mistaking a task call or a function for an instance. Both instantiation
forms in this design are handled:

    l1_d_cache_8kb d_cache_0(
    asynchronous_fifo_gen #(.width(32),.logofdepth(4)) fifo_timer_r (
"""

import json
import os
import re
import sys

RTL_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "rtl"))


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def load_modules(rtl_dir=RTL_DIR):
    """{module: {"file":..., "body":..., "start_line":...}}"""
    mods = {}
    for fn in sorted(os.listdir(rtl_dir)):
        if not fn.endswith(".v"):
            continue
        path = os.path.join(rtl_dir, fn)
        raw = open(path, errors="ignore").read()
        clean = strip_comments(raw)
        for m in re.finditer(r"\bmodule\s+(\w+)\b(.*?)\bendmodule\b", clean, re.S):
            name = m.group(1)
            mods[name] = {
                "file": path,
                "body": m.group(0),
                "start_line": clean[:m.start()].count("\n") + 1,
            }
    return mods


def instantiations(mods):
    """{parent_module: {instance_name: child_module}}"""
    names = set(mods)
    tree = {}
    for parent, info in mods.items():
        found = {}
        for child in names:
            if child == parent:
                continue
            pat = re.compile(r"\b" + re.escape(child) +
                             r"\s*(?:#\s*\((?:[^()]|\([^()]*\))*\)\s*)?(\w+)\s*\(")
            for m in pat.finditer(info["body"]):
                inst = m.group(1)
                # a port connection like ".foo(bar)" cannot start an instance,
                # and neither can a keyword
                if inst in ("if", "else", "begin", "case", "posedge", "negedge"):
                    continue
                found[inst] = child
        tree[parent] = found
    return tree


def resolve(inst_path, top, tree):
    """
    "dot_0/fifo_timer_r/mem[13][5]$_DFFE_PP_" ->
        [("dot_0","axi_lite_dot"), ("fifo_timer_r","asynchronous_fifo_gen")]

    Walks as far down as the path matches real instances and stops. The tail is
    a leaf cell named by Yosys, not a module, so it has no entry.
    """
    chain, cur = [], top
    for seg in inst_path.split("/"):
        seg = seg.split("$")[0]
        child = tree.get(cur, {}).get(seg)
        if child is None:
            break
        chain.append((seg, child))
        cur = child
    return chain


def main():
    mods = load_modules()
    tree = instantiations(mods)
    top = sys.argv[1] if len(sys.argv) > 1 else "soc_top"
    if len(sys.argv) > 2:
        for seg, mod in resolve(sys.argv[2], top, tree):
            print(f"{seg}\t{mod}")
        return
    print(json.dumps({k: v for k, v in tree.items() if v}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
