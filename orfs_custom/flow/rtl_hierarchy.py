"""
Stage 8 support: maps a hierarchical netlist instance path (as reported by
OpenSTA, e.g. "dpath/b_reg/_00_" or "dpath.b_reg.out[4]$_DFFE_PP_") back to
the RTL submodule that actually contains it, by parsing module instantiations
directly out of the (multi-module, single-file) Verilog source.

Needed because run_synth.tcl deliberately keeps the netlist hierarchical
(does not flatten) specifically so this mapping stays possible -- a flattened
netlist collapses every path to an opaque "_243_"-style ID with no submodule
information left to recover.

Without this, every proposed edit would target the top-level wrapper module
(e.g. "gcd") even when the actual violated logic lives entirely inside a
submodule (e.g. "GcdUnitDpathRTL") -- wasting the LLM's edit on a module that
usually has nothing but instantiations and glue logic in it.
"""
import re

MODULE_DEF_RE = re.compile(r"\bmodule\s+([A-Za-z_]\w*)\b")

VERILOG_KEYWORDS = {
    "input", "output", "inout", "wire", "reg", "logic", "parameter",
    "localparam", "generate", "endgenerate", "initial", "always", "always_ff",
    "always_comb", "always_latch", "assign", "function", "endfunction",
    "task", "endtask", "case", "casex", "casez", "endcase", "if", "else",
    "for", "while", "begin", "end", "genvar", "integer", "real", "signed",
    "unsigned", "module", "endmodule", "posedge", "negedge",
}


def parse_modules(src_text):
    """-> {module_name: module_body_text}"""
    modules = {}
    for m in MODULE_DEF_RE.finditer(src_text):
        name = m.group(1)
        end = src_text.find("endmodule", m.end())
        if end == -1:
            continue
        modules[name] = src_text[m.start(): end + len("endmodule")]
    return modules


def parse_instances(module_body, known_module_names):
    """-> {instance_name: module_type} for instantiations of modules we have
    source for (leaves -- e.g. std cells or PyMTL primitives with no source
    in this file -- are intentionally not resolved further)."""
    instances = {}
    inst_re = re.compile(r"^\s*([A-Za-z_]\w*)\s+(?:#\s*\([^;]*?\)\s*)?([A-Za-z_]\w*)\s*\(", re.MULTILINE)
    for m in inst_re.finditer(module_body):
        mod_type, inst_name = m.group(1), m.group(2)
        if mod_type in VERILOG_KEYWORDS:
            continue
        if mod_type not in known_module_names:
            continue
        instances[inst_name] = mod_type
    return instances


def build_hierarchy_index(full_src_text):
    """-> {module_name: {instance_name: module_type}} for every module in the file."""
    modules = parse_modules(full_src_text)
    return modules, {name: parse_instances(body, modules.keys()) for name, body in modules.items()}


def split_path(instance_path):
    return re.split(r"[./]", instance_path)


def resolve_deepest_module(top_module, instance_map, path_components):
    """Walk path_components through the instance hierarchy starting at
    top_module. Returns the deepest module name we could resolve into
    (falls back to top_module if the very first component doesn't resolve,
    e.g. the path points straight at a top-level port or primitive)."""
    current_module = top_module
    for comp in path_components:
        instances = instance_map.get(current_module, {})
        if comp in instances:
            current_module = instances[comp]
        else:
            break
    return current_module


def localize_edit_target(full_src_text, top_module, startpoint, endpoint):
    """Given the worst path's startpoint/endpoint instance paths, return the
    RTL module name that should receive the edit: the deepest module common
    to both paths (their lowest common ancestor in the instance hierarchy) --
    that module's source is guaranteed to contain (or directly instantiate)
    all the logic between the two points. Falls back to top_module when the
    paths share no common prefix (the connecting logic is glue at the top)."""
    modules, instance_map = build_hierarchy_index(full_src_text)

    start_comps = split_path(startpoint)
    end_comps = split_path(endpoint)

    common = []
    for a, b in zip(start_comps, end_comps):
        if a != b:
            break
        common.append(a)

    target = resolve_deepest_module(top_module, instance_map, common)
    return target if target in modules else top_module
