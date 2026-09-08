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
    "qwen":     "qwen/qwen-2.5-coder-32b-instruct",
    "deepseek": "deepseek/deepseek-chat",
    "llama":    "meta-llama/llama-3.3-70b-instruct",
    # Free tiers. These are the ones the bake-off actually runs on: the
    # project has no budget, and a model that cannot be re-run by whoever
    # reads the report is not a reproducible result.
    "deepseek-free": "deepseek/deepseek-chat-v3-0324:free",
    "qwen-free":     "qwen/qwen-2.5-coder-32b-instruct:free",
    "r1-free":       "deepseek/deepseek-r1:free",
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

    def propose(self, system, user, retries=5, max_tokens=16000):
        sys_content = (
            [{"type": "text", "text": system,
              "cache_control": {"type": "ephemeral"}}]
            if self.cache else system)
        if self.shape == "anthropic":
            body = json.dumps({
                "model": self.model,
                "temperature": self.temperature,
                "max_tokens": max_tokens,
                "system": sys_content,
                "messages": [{"role": "user", "content": user}],
            }).encode()
            headers = {"x-api-key": self.key,
                       "anthropic-version": "2023-06-01",
                       "Content-Type": "application/json"}
        else:
            body = json.dumps({
                "model": self.model,
                "temperature": self.temperature,
                "messages": [
                    {"role": "system", "content": sys_content},
                    {"role": "user", "content": user},
                ],
            }).encode()
            headers = {"Authorization": f"Bearer {self.key}",
                       "Content-Type": "application/json"}
        last = None
        for attempt in range(retries):
            req = urllib.request.Request(self.url, data=body, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    d = json.loads(r.read())
                self.calls += 1
                u = d.get("usage") or {}
                if self.shape == "anthropic":
                    self.tokens_in += u.get("input_tokens", 0)
                    self.tokens_out += u.get("output_tokens", 0)
                    return "".join(b.get("text", "")
                                   for b in d.get("content", [])
                                   if b.get("type") == "text")
                self.tokens_in += u.get("prompt_tokens", 0)
                self.tokens_out += u.get("completion_tokens", 0)
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
                except json.JSONDecodeError:
                    return None
    return None
