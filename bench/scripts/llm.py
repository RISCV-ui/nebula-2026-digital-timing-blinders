#!/usr/bin/env python3
"""
The one place that talks to a model.

Everything above this file sees `Backend.propose(system, user) -> str` and
nothing else, so swapping models for the bake-off is a flag, not an edit, and
the loop can be exercised end to end with no network and no key at all.

Keys are read from the environment. They are never written to a config file,
never passed on a command line where they would land in shell history, and
never logged -- the history store records the model name and the token counts,
not the credential.
"""
import json, os, re, sys, time, urllib.error, urllib.request

MODELS = {
    # Aliases, so the bake-off record says "which model" rather than pasting a
    # provider string into every command.
    "sonnet":   "anthropic/claude-sonnet-5",
    "opus":     "anthropic/claude-opus-5",
    # Native Anthropic takes a bare model id, not the "anthropic/" route
    # prefix OpenRouter uses. Same models, different address.
    "opus-direct":   "claude-opus-5",
    "sonnet-direct": "claude-sonnet-5",
    "sonnet-45": "anthropic/claude-sonnet-4.5",
    "opus-41":   "anthropic/claude-opus-4.1",
    # Open-weight arms for the bake-off. "Open source" in the deliverable has
    # to mean weights someone else can download and re-run, not merely a free
    # API -- Gemini is free and closed, and putting it in the open column would
    # be the kind of claim a judge is right to poke at. These are all
    # open-weight: gpt-oss is Apache-2.0, the rest ship weights on HuggingFace.
    #
    # All verified against OpenRouter's live model list by
    # `bakeoff.py --probe` on 2026-09-09. Slugs drift -- half of a first,
    # plausible-looking guess at these was already dead -- so re-probe before a
    # run rather than trusting this block.
    #
    # Free first: the project has no budget, and a result the reader cannot
    # re-run is not a result. NVIDIA and Google are the only vendors currently
    # serving frontier-size open weights free here.
    "nemotron":       "nvidia/nemotron-3-super-120b-a12b:free",
    "nemotron-ultra": "nvidia/nemotron-3-ultra-550b-a55b:free",
    "nemotron-nano":  "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
    "gemma-free":     "google/gemma-4-31b-it:free",
    # Paid but cheap, and chosen for spread rather than for a leaderboard:
    # two reasoning models, two code-specialised models, and three general
    # ones from different labs, so a failure common to all of them is a
    # statement about the task and not about one vendor's post-training.
    "deepseek":       "deepseek/deepseek-chat-v3.1",
    "deepseek-v32":   "deepseek/deepseek-v3.2",
    "r1":             "deepseek/deepseek-r1-0528",
    "qwen3-coder":    "qwen/qwen3-coder",
    "qwen3-coder-plus": "qwen/qwen3-coder-plus",
    "qwen3-235b":     "qwen/qwen3-235b-a22b-thinking-2507",
    "qwen-25-coder":  "qwen/qwen-2.5-coder-32b-instruct",
    "gptoss":         "openai/gpt-oss-120b",
    "gptoss-20b":     "openai/gpt-oss-20b",
    "glm":            "z-ai/glm-4.6",
    "kimi":           "moonshotai/kimi-k2",
    "llama":          "meta-llama/llama-3.3-70b-instruct",
    "llama4":         "meta-llama/llama-4-maverick",
    "devstral":       "mistralai/devstral-2512",
    "codestral":      "mistralai/codestral-2508",
    "phi4":           "microsoft/phi-4",
    # Gemini's OpenAI-compatibility endpoint wants the full resource name,
    # "models/<id>", not the bare id -- a bare id is a 404, not a helpful
    # error, which is why these aliases carry the prefix.
    "gemini-pro":    "models/gemini-3.1-pro-preview",
    "gemini-flash":  "models/gemini-3.5-flash",
    "gemini-25-pro": "models/gemini-2.5-pro",
}

# Every provider here speaks the OpenAI chat-completions shape, so one client
# covers all of them and the bake-off is a flag rather than a new code path.
# `cache` says whether the provider understands a system message sent as a
# list of blocks carrying cache_control -- OpenRouter does, Gemini's
# compatibility endpoint rejects it and wants a plain string.
PROVIDERS = {
    "openrouter": {
        "url":   "https://openrouter.ai/api/v1/chat/completions",
        "key":   "OPENROUTER_API_KEY",
        "cache": True,
    },
    "gemini": {
        "url":   "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        "key":   "GEMINI_API_KEY",
        "cache": False,
    },
    # The one provider that does not speak the OpenAI shape. Anthropic's
    # Messages API takes the system prompt as a top-level field rather than a
    # message, requires max_tokens, authenticates with x-api-key instead of a
    # bearer token, and returns content as a list of blocks. `shape` is what
    # keeps that from becoming a second client: three small branches in
    # ChatBackend rather than a parallel code path that drifts.
    "anthropic": {
        "url":   "https://api.anthropic.com/v1/messages",
        "key":   "ANTHROPIC_API_KEY",
        "cache": True,
        "shape": "anthropic",
    },
}


# USD per million tokens, list price, input then output.
#
# The bake-off's whole point is a paid-model-versus-open-model comparison, and
# that comparison is not "which model wrote the nicer diff" -- it is cost per
# formally verified fix. A run that accepts two edits for $0.40 and a run that
# accepts three for $9 are different engineering answers, and neither number
# can be stated without recording what the calls actually consumed.
#
# Prefix match, longest first, so a dated id (claude-opus-5-20260115) picks up
# its family's price without a new row. An unpriced model costs 0.0 and is
# reported as unpriced rather than as free.
PRICES = {
    "claude-opus-5":    (15.00, 75.00),
    "claude-sonnet-5":  (3.00, 15.00),
    "claude-haiku-4-5": (1.00, 5.00),
    "gemini-3.5-flash": (0.30, 2.50),
    # OpenRouter's :free tier. Zero is the real price, not a missing row.
    "nvidia/nemotron":  (0.0, 0.0),
}


def price_of(model):
    """List price for a model id, or None when it is not in the table."""
    hits = [k for k in PRICES if model.startswith(k) or k in model]
    if not hits:
        return None
    return PRICES[max(hits, key=len)]


class BackendUnavailable(RuntimeError):
    """
    The provider could not be reached -- rate limit, outage, network.

    Distinct from a refusal on purpose. A refusal is an answer, and the loop
    records it and moves to the next target; this is the absence of an answer,
    and it must not be allowed to discard the edits already accepted in the
    same run.
    """


class Backend:
    name = "base"

    def propose(self, system, user):
        raise NotImplementedError


class MockBackend(Backend):
    """
    Replays canned proposals from a directory, one JSON file per target module.

    This exists so the loop, the gates and the history store can be developed
    and regression-tested without spending a call or needing a key, and so the
    demo has a path that behaves identically offline. A missing file is
    reported as a refusal rather than an error: "the model declined to propose
    anything for this module" is a real outcome the loop has to handle.
    """
    name = "mock"

    def __init__(self, path):
        self.path = path
        self.calls = 0
        self.seen = {}
        self.last_usage = {}

    def usage_summary(self):
        # The offline path spends nothing, and says so with a real zero rather
        # than by being absent -- a run summary missing its cost row reads as
        # a bug in the accounting, not as a free run.
        return {"backend": self.name, "model": "mock", "calls": self.calls,
                "tokens_in": 0, "tokens_out": 0, "tokens_in_fresh": 0,
                "tokens_cache_read": 0, "tokens_cache_write": 0,
                "cost_usd": 0.0, "priced": True}

    def propose(self, system, user):
        self.calls += 1
        m = re.search(r"TARGET MODULE:\s*(\w+)", user)
        if not m:
            return json.dumps({"refused": "no target module in prompt"})
        mod = m.group(1)
        f = os.path.join(self.path, mod + ".json")
        if not os.path.exists(f):
            return json.dumps({"refused": f"no canned proposal for {mod}"})
        d = json.loads(open(f).read())
        # A file holding a list is a scripted sequence of answers for that
        # module: first the reply the gates reject, then the repair. That is
        # what makes the retry path testable without a model, and the retry
        # path is where most of the loop's logic lives.
        if isinstance(d, list):
            n = self.seen.get(mod, 0)
            self.seen[mod] = n + 1
            d = d[min(n, len(d) - 1)]
        return json.dumps(d)


class ChatBackend(Backend):
    """
    One OpenAI-shaped client for every hosted provider in the bake-off.

    The system prompt carries the transform catalogue, which is byte-identical
    on every call and is the bulk of the tokens, so where the provider supports
    prompt caching it is sent as its own cacheable block.
    """

    def __init__(self, provider, model, temperature=0.2):
        if provider not in PROVIDERS:
            raise SystemExit(f"unknown provider {provider!r}; "
                             f"have {sorted(PROVIDERS)}")
        cfg = PROVIDERS[provider]
        self.provider = provider
        self.url = cfg["url"]
        self.cache = cfg["cache"]
        self.shape = cfg.get("shape", "openai")
        self.model = MODELS.get(model, model)
        # The Claude 5 family rejects `temperature` outright
        # ("`temperature` is deprecated for this model", HTTP 400),
        # so the field is dropped for those ids rather than sent and
        # retried. Every other model still gets the fixed low
        # temperature the bake-off runs at.
        self.send_temperature = not re.search(r"claude-(opus|sonnet|haiku|fable)-5",
                                              self.model)
        self.name = f"{provider}:{self.model}"
        self.temperature = temperature
        key_env = cfg["key"]
        self.key = os.environ.get(key_env)
        if not self.key:
            raise SystemExit(
                f"{key_env} is not set. Export it in this shell; do not put it "
                f"in a config file and do not pass it as an argument.")
        self.calls = 0
        self.tokens_in = 0
        self.tokens_out = 0
        # Set per call. None until the first one returns.
        self.last_stop_reason = None
        # What the most recent call cost, so the loop can attribute spend to
        # the iteration that spent it rather than only to the run as a whole.
        self.last_usage = {}

    def _record(self, tin, tout, cache_read, cache_write):
        """
        Book one call's tokens, split by how they are billed.

        The two request shapes report the same thing differently and the
        difference is not cosmetic: Anthropic's `input_tokens` excludes both
        cache reads and cache writes, while OpenAI's `prompt_tokens` includes
        its cached tokens. Adding them the same way would double-count the
        catalogue on every Anthropic call.
        """
        if self.shape != "anthropic":
            tin = max(0, tin - cache_read)
        self.tokens_in += tin + cache_read + cache_write
        self.tokens_out += tout
        self._fresh_in = getattr(self, "_fresh_in", 0) + tin
        self._cache_read = getattr(self, "_cache_read", 0) + cache_read
        self._cache_write = getattr(self, "_cache_write", 0) + cache_write
        self.last_usage = {"tokens_in": tin, "tokens_out": tout,
                           "cache_read": cache_read,
                           "cache_write": cache_write,
                           "cost_usd": self._cost(tin, tout, cache_read,
                                                  cache_write)}

    def _cost(self, tin, tout, cache_read, cache_write):
        """
        List-price cost of one call, or None when the model is not priced.

        Cache reads bill at a tenth of the input rate and cache writes at
        1.25x; both multipliers are the same across the providers here.
        """
        pr = price_of(self.model)
        if pr is None:
            return None
        pin, pout = pr
        return round((tin * pin + cache_read * pin * 0.10
                      + cache_write * pin * 1.25 + tout * pout) / 1e6, 6)

    def usage_summary(self):
        """Everything the report needs to state cost per accepted fix."""
        fresh = getattr(self, "_fresh_in", 0)
        cr = getattr(self, "_cache_read", 0)
        cw = getattr(self, "_cache_write", 0)
        cost = self._cost(fresh, self.tokens_out, cr, cw)
        return {"backend": self.name, "model": self.model,
                "calls": self.calls,
                "tokens_in": self.tokens_in, "tokens_out": self.tokens_out,
                "tokens_in_fresh": fresh, "tokens_cache_read": cr,
                "tokens_cache_write": cw,
                "cost_usd": cost,
                "priced": price_of(self.model) is not None}

    # 16000 was chosen when a reply was only the rewritten module. These
    # models spend thinking tokens out of the same budget before emitting any
    # text, and on the v2 bake-off that budget ran out first on 15 of 26
    # anthropic-arm calls: the response came back with a thinking block, no
    # text block, stop_reason "max_tokens", and output_tokens pinned at exactly
    # the cap. An empty reply is indistinguishable from an unparseable one
    # downstream, so those targets were recorded as refusals and abandoned --
    # $13.51 of Opus calls that accepted nothing. The successful replies on
    # this design used 4.4k-14.6k tokens, so the reply itself was never close
    # to the cap; the thinking was.
    def propose(self, system, user, retries=5, max_tokens=32000):
        sys_content = (
            [{"type": "text", "text": system,
              "cache_control": {"type": "ephemeral"}}]
            if self.cache else system)
        if self.shape == "anthropic":
            payload = {
                "model": self.model,
                "max_tokens": max_tokens,
                "system": sys_content,
                "messages": [{"role": "user", "content": user}],
            }
            if self.send_temperature:
                payload["temperature"] = self.temperature
            body = json.dumps(payload).encode()
            headers = {"x-api-key": self.key,
                       "anthropic-version": "2023-06-01",
                       "Content-Type": "application/json"}
        else:
            payload = {
                "model": self.model,
                "messages": [
                    {"role": "system", "content": sys_content},
                    {"role": "user", "content": user},
                ],
            }
            if self.send_temperature:
                payload["temperature"] = self.temperature
            body = json.dumps(payload).encode()
            headers = {"Authorization": f"Bearer {self.key}",
                       "Content-Type": "application/json"}
        last = None
        for attempt in range(retries):
            req = urllib.request.Request(self.url, data=body, headers=headers)
            try:
                # 180 s was enough for every hosted arm until Opus 5,
                # which spends thinking tokens before the first byte of
                # the reply and blew the read timeout five times in a
                # row -- 962 s of wall clock spent to record "backend
                # unavailable" for a model that was answering fine.
                # Anthropic rejects non-streaming requests past ten
                # minutes, so 600 s is the whole usable window.
                with urllib.request.urlopen(req, timeout=600) as r:
                    d = json.loads(r.read())
                self.calls += 1
                u = d.get("usage") or {}
                if self.shape == "anthropic":
                    # Cached input is billed at a tenth of the base rate and
                    # the catalogue -- the bulk of every prompt -- is sent as a
                    # cacheable block, so counting it at the base rate would
                    # overstate the paid arms by most of their token volume.
                    self._record(u.get("input_tokens", 0),
                                 u.get("output_tokens", 0),
                                 u.get("cache_read_input_tokens", 0),
                                 u.get("cache_creation_input_tokens", 0))
                    # Why the reply was empty decides whether retrying it
                    # is worth anything, so the reason is kept rather than
                    # collapsed into the empty string the caller sees.
                    self.last_stop_reason = d.get("stop_reason")
                    return "".join(b.get("text", "")
                                   for b in d.get("content", [])
                                   if b.get("type") == "text")
                cached = ((u.get("prompt_tokens_details") or {})
                          .get("cached_tokens", 0))
                self._record(u.get("prompt_tokens", 0),
                             u.get("completion_tokens", 0), cached, 0)
                self.last_stop_reason = (
                    (d["choices"][0] or {}).get("finish_reason"))
                return d["choices"][0]["message"]["content"]
            except (urllib.error.URLError, KeyError, TimeoutError) as e:
                last = e
                code = getattr(e, "code", None)
                # A 4xx other than 429 is the provider saying "no", not
                # "later", and retrying it is worse than useless: it turns a
                # bad key or a mistyped model id into a 62-second wait whose
                # error message reads "failed after 5 tries", which sends
                # whoever is debugging it towards the network. Fail on the
                # first one and say what it was.
                if code is not None and 400 <= code < 500 and code != 429:
                    raise BackendUnavailable(
                        f"{self.name}: HTTP {code} on the first attempt, not "
                        f"retried -- this is a request the provider rejected "
                        f"outright ({'check ' + PROVIDERS[self.provider]['key'] if code in (401, 403) else 'check the model id and request body'}): {e}")
                # 429, 503 and Anthropic's 529 are the provider saying
                # "later". A free tier hits them routinely, and 1+2+4s of
                # backoff is far too short to ride one out -- the first run to
                # meet a 503 exhausted its retries in seven seconds and took
                # the whole loop down with it.
                time.sleep(min(60, (8 if code in (429, 503, 529) else 2)
                               * 2 ** attempt))
        raise BackendUnavailable(
            f"{self.name} failed after {retries} tries: {last}")


def get(spec, mock_dir=None):
    """`mock`, or `<provider>:<model alias>` -- e.g. gemini:gemini-pro,
    openrouter:deepseek-free."""
    if spec == "mock":
        return MockBackend(mock_dir or "bench/mock_proposals")
    if ":" not in spec:
        raise SystemExit(f"unknown backend {spec!r}; "
                         f"want mock or <provider>:<model>")
    provider, model = spec.split(":", 1)
    return ChatBackend(provider, model)


def extract_json(text):
    """
    Models fence their JSON, prefix it with prose, or both. Take the outermost
    balanced object and parse that; a proposal that cannot be parsed is a
    refusal, not a crash.
    """
    # Cleared on entry, so a caller reading it after a None always sees why
    # *this* reply failed. Left set, a stale message from an earlier call
    # would be fed back to the model as though it described the reply in
    # hand -- and the one case that reaches here with nothing to report is a
    # reply carrying no object at all.
    extract_json.last_error = None
    s = text.find("{")
    if s < 0:
        return None
    depth, instr, esc = 0, False, False
    for i in range(s, len(text)):
        c = text[i]
        if instr:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                instr = False
            continue
        if c == '"':
            instr = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[s:i + 1])
                except json.JSONDecodeError as e:
                    # Keep why it failed and where. A 12 kB reply carrying one
                    # stray character -- a `.` between a closing quote and the
                    # comma after it, in the run that prompted this -- is not a
                    # refusal and not a model that cannot follow the format; it
                    # is a typo, and the model can fix its own typo for the
                    # price of one more call. Quoting the parser's own message
                    # back is how every other gate here gives feedback, and it
                    # beats guessing at a repair: a tolerant re-parse that
                    # silently changes what the proposal said is the one kind
                    # of fix this project cannot ship.
                    lo, hi = max(0, e.pos - 60), min(len(text), e.pos + 60)
                    extract_json.last_error = (
                        f"{e.msg} at line {e.lineno} column {e.colno}; "
                        f"the text around it is: ...{text[s:][lo:hi]!r}...")
                    return None
    return None


extract_json.last_error = None
