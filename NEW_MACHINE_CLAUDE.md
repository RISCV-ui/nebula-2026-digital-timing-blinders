# Nebula 2026 — Fresh Linux Machine: Toolchain Install

You (Claude Code) are opening in an **empty folder** on a fresh **Ubuntu/Debian**
Linux machine. This file's only job right now is: get every EDA tool this
project needs installed and verified. The actual project code (RTL, Python
scripts, the book) is not here yet — it'll be added in a separate step later.

Work through the checklist below top to bottom. Before any `sudo` command or
any installer that downloads+runs a script (`curl | sh` style), **stop and
tell the user what you're about to run and why, then wait for confirmation**
— don't just run it silently. Everything else (git clone, make, pip install
inside a venv) is fine to run without asking.

After each numbered step, verify it worked (a version check or similar)
before moving to the next. If a step fails, don't retry blindly — read the
actual error, diagnose, and report back.

## 0. Sanity check what's already there

Run first, so you don't reinstall things that already exist:
```
which git make python3 curl nix yosys iverilog 2>&1
git --version; make --version; python3 --version
```

## 1. Base build dependencies (apt, needs sudo — ask first)

```
sudo apt update
sudo apt install -y build-essential git curl python3 python3-venv python3-pip \
    pkg-config libreadline-dev tcl-dev tk-dev
```

## 2. OSS CAD Suite (Yosys + OpenSTA + Icarus Verilog + more, prebuilt binaries)

No sudo needed — installs into a local directory.
```
mkdir -p ~/eda
cd ~/eda
curl -L -o oss-cad-suite.tgz \
  https://github.com/YosysHQ/oss-cad-suite-build/releases/latest/download/oss-cad-suite-linux-x64.tgz
tar xzf oss-cad-suite.tgz
```
Add to PATH (append to `~/.bashrc` so it persists across shells, then also
`source` it for the current session):
```
echo 'source ~/eda/oss-cad-suite/environment' >> ~/.bashrc
source ~/eda/oss-cad-suite/environment
```
Verify:
```
yosys -V
opensta -version || sta -version
iverilog -V
```
If `eqy` or `sby` aren't found after sourcing the environment (`which eqy sby`),
they need building from source — see step 4.

## 3. OpenROAD-flow-scripts (ORFS) — full RTL-to-GDS flow, sky130hd PDK

```
cd ~/eda
git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git orfs
cd orfs
sudo ./setup.sh   # installs ORFS's own system deps — ask user before running, it's sudo + apt
./build_openroad.sh --local
```
This build takes a long time (30–90+ min) — run it and let it finish, don't
interrupt. Verify afterward:
```
source ~/eda/orfs/env.sh
yosys -V
openroad -version
```

## 4. EQY + sby (formal equivalence checking) — only if missing after step 2

```
cd ~/eda
git clone https://github.com/YosysHQ/sby.git
git clone https://github.com/YosysHQ/eqy.git
cd ~/eda/sby && sudo make install   # ask user first, sudo
cd ~/eda/eqy && sudo make install   # ask user first, sudo
```
Verify: `eqy --help`, `sby --help`.

## 5. Nix (needed for OpenRAM + sky130 PDK)

Ask the user first — this is a system-level installer requiring sudo/interactive
setup. If they approve, they should run it themselves interactively (same reason
as always: password prompts don't script cleanly), e.g.:
```
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
After it's installed, open a **new shell** (or `source
/nix/var/nix/profiles/default/bin` onto PATH) and verify:
```
nix --version
```

## 6. OpenRAM (SRAM compiler) with sky130 support

```
cd ~/eda
git clone --depth 1 https://github.com/VLSIDA/OpenRAM.git
cd OpenRAM
export OPENRAM_HOME="$PWD/compiler"
export OPENRAM_TECH="$PWD/technology"
export PYTHONPATH="$OPENRAM_HOME"
echo "export OPENRAM_HOME=\"$PWD/compiler\"" >> ~/.bashrc
echo "export OPENRAM_TECH=\"$PWD/technology\"" >> ~/.bashrc
echo "export PYTHONPATH=\"\$OPENRAM_HOME\"" >> ~/.bashrc

make sky130-pdk       # uses ciel via `nix develop` — this machine is x86_64-linux,
                       # so OpenRAM's flake.nix works natively, no platform patching needed
make sky130-install
```
Verify by generating a tiny test SRAM (adjust config name if the repo's
example differs — check `technology/sky130/sram_configs/` or similar first):
```
cd ~/eda/OpenRAM
python3 sram_compiler.py <a small example config from the repo's docs/tests>
```

## 7. Python environment for the LLM loop

```
cd <wherever the Nebula project code ends up>
python3 -m venv .venv_llm
.venv_llm/bin/pip install anthropic
```
`ANTHROPIC_API_KEY` needs to be set in the environment before running
`llm_loop.py` for real (non-`--mock`) runs — ask the user for it, don't
hardcode it into any file.

## 8. Final report

Once done, print a summary table: tool → installed (yes/no) → version →
verified how. Flag anything that failed or needed a workaround, the same way
issues have been tracked in this project's macOS setup (see the Troubleshooting
chapter of `nebula_book.md` once the project folder is copied over — a Linux
machine should hit far fewer platform-specific problems than the arm64 Mac did,
since ORFS/OSS-CAD-Suite/OpenRAM's Nix flake all target x86_64-linux natively).
