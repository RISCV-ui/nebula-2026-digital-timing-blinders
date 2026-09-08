#!/usr/bin/env bash
# Wrapper: run OpenSTA via docker, mounting the current directory
# so relative paths in .tcl scripts (netlist, sdc, liberty) just work.
set -euo pipefail
docker run --rm -i --platform linux/amd64 \
    -v "$(pwd)":/data \
    openroad/opensta:latest "$@"
