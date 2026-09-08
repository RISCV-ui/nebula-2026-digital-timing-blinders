# Installing Claude Code (CLI + VS Code) on the New Linux Laptop

Run this before anything else in `LAPTOP_HANDOFF.md` — you need Claude Code
itself running here before it can read the rest of this project.

## 1. Node.js (Claude Code CLI needs v18+)

```
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node --version    # verify: v20.x or later
```

## 2. Claude Code CLI

```
npm install -g @anthropic-ai/claude-code
claude --version
```

## 3. VS Code extension (optional, CLI works standalone too)

Open VS Code → Extensions (`Ctrl+Shift+X`) → search "Claude Code" → install
the official Anthropic extension. It detects the CLI installed in step 2
automatically. You can also just run `claude` in VS Code's integrated
terminal without the extension — same engine, extension just adds a
diff/sidebar UI on top.

## 4. Log in

```
claude
```
Follow the browser OAuth prompt (Claude subscription login). If instead
using API-key billing, set the key first:
```
export ANTHROPIC_API_KEY=sk-ant-...
echo 'export ANTHROPIC_API_KEY=sk-ant-...' >> ~/.bashrc
```

## 5. Open the project

```
cd ~/path/to/unzipped/Nebula
claude
```
It reads `CLAUDE.md` automatically, which points to `LAPTOP_HANDOFF.md` for
toolchain reinstall steps — follow that next.

## Notes

- This laptop has sudo (unlike the `luffy@10.107.2.130` box we tried first
  and abandoned — see `LAPTOP_HANDOFF.md`), so step 1's `sudo apt install`
  should just work, no workaround needed.
- If `npm install -g` fails with an EACCES permission error, don't `sudo
  npm install -g` (breaks npm's global permissions long-term) — instead fix
  npm's global prefix to a user-owned directory first:
  ```
  mkdir -p ~/.npm-global
  npm config set prefix '~/.npm-global'
  echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
  source ~/.bashrc
  ```
  then retry `npm install -g @anthropic-ai/claude-code`.
