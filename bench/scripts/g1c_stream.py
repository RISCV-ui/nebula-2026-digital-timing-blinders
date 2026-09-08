#!/usr/bin/env python3
"""
g1c_stream.py -- gate 1c: does the pipelined unit still emit the same stream?

G1 proves a module equals its predecessor. G1b proves the parent survives the
new latency. On this design the second one has no answer to give, and that is
not a tool limitation -- it is the wrong question.

`fp4_dot_unit` was combinational, so `axi_lite_dot` popped a pair of operands
and pushed the result on the same cycle. Four pipeline stages separate those
two events, so the parent is no longer cycle-identical, and no fixed delay
wrapper repairs that: the parent's outputs are AXI handshake signals whose
timing depends on `s1_dr_ready`, an input, not on any constant N. A miter
against a delayed golden fails for a reason that says nothing about whether
the edit is correct.

What is actually true, and what a master can actually observe, is a statement
about one stream:

    every value written into the result FIFO is the correct dot product of a
    pair of operands that was popped, the values appear in pop order, none is
    lost, none is invented, and none is written while the FIFO is full.

That is stronger than cycle equivalence would have been, not weaker. Cycle
equivalence would only have said the timing matched; this says the data and
the order are right, and behind a FIFO the timing was never observable
anyway.

The check is a bounded assertion proof over `fp4_dot_stage`, which is where
the transform lives and is deliberately a single-clock module with the FIFO
interfaces as free inputs. Cutting here is what keeps the proof honest:
`axi_lite_dot` holds three asynchronous FIFOs and two clock domains, and a
solver stepping both clocks together would be checking one phase relationship
out of infinitely many. Whether the FIFOs themselves are safe is G2's
question.

Five properties, checked together on the same trace:

    P1  no overflow      w_en never asserts while full
    P2a no invention     w_en never asserts with an empty shadow queue
    P2b no loss          pending results never exceed the pipeline depth
    P3  data and order   the pushed value is the head of the shadow queue
    P4  drain            a pending result with room available is never held
                         for more than DOT_LAT cycles

P4 is the one worth having. The obvious elastic control -- advance only when
new operands are available -- passes P1, P2 and P3 and is still wrong: at the
end of a burst the last four results sit in the stages until operands happen
to arrive again, so a master that writes five operand pairs reads back one.
That is a functional change wearing a latency change's clothes, and P4 is
what separates them.

The reference model is the pre-transform `fp4_dot_unit`, read from the golden
tree and renamed, so the property is stated against the original function and
not against a restatement of it.

Usage:
    g1c_stream.py --golden bench/rtl --candidate artifacts/wns/rtl
    g1c_stream.py --golden bench/rtl --candidate artifacts/wns/rtl --depth 20
"""
import argparse, glob, json, os, re, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import transforms as T                                     # noqa: E402

REF = "__ref_fp4_dot_unit"


def reference_model(golden_dir, module):
    """The golden module, renamed, so it can sit beside its own successor."""
    _, src = T.module_source(module, golden_dir)
    if src is None:
        raise SystemExit(f"{module} not found in {golden_dir}")
    return re.sub(rf"\bmodule\s+{re.escape(module)}\b", f"module {REF}", src, 1)


def checker(lat, qw, module="fp4_dot_stage"):
    """
    The property harness: shadow queue, reference model, five assertions.

    The queue is 2**qw deep and the pipeline is `lat` deep, so with qw such
    that 2**qw > lat the write index and the read index can never collide --
    P2b bounds the occupancy below the queue size, and P2a keeps the read
    index behind the write index whenever a read happens.
    """
    depth = 1 << qw
    return f"""
module __stream_check(clk, rst, empty_1, empty_2, full, data_1, data_2);

parameter DOT_LAT = {lat};

input        clk, rst;
input        empty_1, empty_2, full;
input [31:0] data_1, data_2;

wire        r_en_1, r_en_2, w_en;
wire [31:0] data_w;

{module} #(.DOT_LAT(DOT_LAT)) dut(
    .clk(clk), .rst(rst),
    .empty_1(empty_1), .empty_2(empty_2), .full(full),
    .data_1(data_1), .data_2(data_2),
    .r_en_1(r_en_1), .r_en_2(r_en_2), .w_en(w_en), .data_w(data_w));

// The pre-transform function, evaluated on the operands at the cycle they are
// popped. This is the specification; everything below compares against it.
wire [31:0] ref_dot;
{REF} ref_u(.clk(clk), .rst(rst),
            .va(data_1), .vb(data_2), .dot_out(ref_dot));

reg [31:0] q [0:{depth - 1}];
reg [{qw}:0] head, tail;
reg [3:0]  stall_cnt;
wire [{qw}:0] occ = tail - head;

// Read the queue head through a wire, not inside the assertion block. Read
// directly from an `always` and yosys infers a *synchronous* read port, which
// registers the value and compares the push against last cycle's head.
wire [31:0] q_head = q[head[{qw} - 1:0]];

integer k;
always @(posedge clk) begin
    if (rst) begin
        head <= 0;
        tail <= 0;
        stall_cnt <= 0;
        for (k = 0; k < {depth}; k = k + 1) q[k] <= 32'd0;
    end
    else begin
        if (r_en_1) begin
            q[tail[{qw - 1}:0]] <= ref_dot;
            tail <= tail + 1;
        end
        if (w_en) head <= head + 1;

        if (w_en)                       stall_cnt <= 0;
        else if (occ != 0 && !full)     stall_cnt <= stall_cnt + 1;
        else                            stall_cnt <= 0;
    end
end

always @(posedge clk) if (!rst) begin
    // P1  no overflow
    assert (!(w_en && full));
    // P2a no invention
    assert (!(w_en && occ == 0));
    // P2b no loss: pending results never exceed the pipeline depth
    assert (occ <= DOT_LAT);
    // P3  data and order
    assert (!w_en || data_w == q_head);
    // P4  drain: a pending result with room available is never held
    assert (stall_cnt <= DOT_LAT);
    // both operand FIFOs are popped as one
    assert (r_en_1 == r_en_2);
end

endmodule
"""


def script(candidate, ref_file, chk_file, depth):
    files = sorted(glob.glob(os.path.join(candidate, "*.v")))
    reads = "\n".join(f"read_verilog -sv -formal -defer {f}" for f in files)
    return f"""
{reads}
read_verilog -sv -formal -defer {ref_file}
read_verilog -sv -formal -defer {chk_file}
hierarchy -check -top __stream_check
proc; opt_expr; opt_clean
memory -nomap; memory_map
flatten
opt_expr
# Both the device and the reference evaluate the same multiplier array on the
# same operands, so every fp4_mul appears twice, structurally identical and
# identically driven. opt_merge collapses those pairs before the solver sees
# them; without it the eight multipliers and the first adder level are solved
# twice over for nothing.
opt_merge -share_all
# Recent yosys emits `assert` as a $check cell, which `sat` has no model for
# and stops on with the same message a real blackbox produces. The assertions
# are edge-triggered, so async2sync has to resolve them to plain synchronous
# logic before chformal can lower them to the $assert cells the solver knows.
async2sync
chformal -lower
opt -fast
sat -seq {depth} -prove-asserts -set-init-zero -verify -show-inputs -show-outputs __stream_check
"""


def run(golden, candidate, lat, qw, depth, timeout, module="fp4_dot_stage"):
    tmp = tempfile.mkdtemp(prefix="g1c_")
    ref_file = os.path.join(tmp, "__ref.v")
    chk_file = os.path.join(tmp, "__chk.v")
    open(ref_file, "w").write(reference_model(golden, "fp4_dot_unit"))
    open(chk_file, "w").write(checker(lat, qw, module))
    ys = os.path.join(tmp, "chk.ys")
    open(ys, "w").write(script(candidate, ref_file, chk_file, depth))

    t0 = time.time()
    try:
        r = subprocess.run(["yosys", "-s", ys], capture_output=True,
                           text=True, timeout=timeout)
        out = r.stdout + r.stderr
        rc = r.returncode
    except subprocess.TimeoutExpired:
        return {"verdict": "TIMEOUT", "seconds": round(time.time() - t0, 1),
                "depth": depth}

    res = {"seconds": round(time.time() - t0, 1), "depth": depth,
           "latency": lat, "module": module,
           "properties": ["P1 no overflow", "P2a no invention",
                          "P2b no loss", "P3 data and order",
                          "P4 drain", "r_en_1 == r_en_2"]}
    if "SAT proof finished - no model found: SUCCESS" in out:
        res["verdict"] = "STREAM_EQUIVALENT"
    elif "SAT proof finished - model found: FAIL" in out:
        res["verdict"] = "PROPERTY_VIOLATED"
        m = re.search(r"Signal Name.*?(?=\n\n)", out, re.S)
        res["counterexample"] = (m.group(0) if m else out[-8000:])[:8000]
    elif rc != 0:
        res["verdict"] = "ERROR"
        res["detail"] = out[-2500:]
    else:
        res["verdict"] = "ERROR"
        res["detail"] = "no SAT verdict\n" + out[-1500:]
    return res


# The port shape this gate's harness is written for. G1c drives the FIFO-side
# signals as free inputs and watches the popped/pushed pair, so it can only
# speak about a module that presents exactly these ports. Anything else gets
# no verdict at all -- the same stance clockcheck.py takes on a clock
# structure it has not been taught: failing to recognise a shape is a prompt
# to look, never a pass and never a fail.
ELASTIC_IN = ("clk", "rst", "empty_1", "empty_2", "full", "data_1", "data_2")
ELASTIC_OUT = ("r_en_1", "r_en_2", "w_en", "data_w")


def applies(rtl_dir, module):
    """
    True when `module` presents the elastic interface this harness models.

    This predicate is what picks G1c over G1b, and the split is not a
    convenience -- the two gates ask different questions because the two
    interfaces carry different contracts. A rigid module owes its parent a
    value on a fixed cycle, and G1b checks exactly that. An elastic module
    owes its parent a *stream*: the right values, in the right order,
    eventually, with nothing stranded. Behind a FIFO the cycle a value arrives
    on is not observable, so a fixed-N miter would reject correct designs and
    would have proved nothing about the ones it passed.
    """
    _, src = T.module_source(module, rtl_dir)
    if not src:
        return False
    p = T.ports(src)
    return (all(n in p and p[n].startswith("input") for n in ELASTIC_IN)
            and all(n in p and p[n].startswith("output") for n in ELASTIC_OUT))


def check(golden, candidate, module, lat, qw=3, depth=16, timeout=3600):
    """Loop-facing entry point, shaped like g1b_contract.check."""
    if not applies(candidate, module):
        return {"verdict": "NOT_APPLICABLE", "module": module,
                "detail": "module does not present the elastic interface this "
                          "harness models; there is no stream contract here "
                          "for it to speak about"}
    res = run(golden, candidate, lat, qw, depth, timeout, module)
    res["module"] = module
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--golden", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--latency", type=int, default=4)
    ap.add_argument("--qw", type=int, default=3, help="log2 of shadow queue depth")
    ap.add_argument("--depth", type=int, default=16)
    ap.add_argument("--timeout", type=int, default=3600)
    ap.add_argument("--out", default=None)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    res = run(a.golden, a.candidate, a.latency, a.qw, a.depth, a.timeout)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(json.dumps(res, indent=2) + "\n")
    if a.json:
        print(json.dumps(res, indent=2))
    else:
        print(f'{res["verdict"]:<20} fp4_dot_stage  depth {res["depth"]}  '
              f'{res.get("seconds")}s')
        for line in (res.get("counterexample") or
                     res.get("detail") or "").splitlines()[:15]:
            print("   ", line)
    sys.exit(0 if res["verdict"] == "STREAM_EQUIVALENT" else 1)


if __name__ == "__main__":
    main()
