#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
load_llama_env "${SCRIPT_DIR}/.env"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. Install it and run load3.sh first." >&2
  exit 1
fi

python3 "${SCRIPT_DIR}/benchmark.py"
