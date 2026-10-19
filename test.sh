#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_SCRIPT="${SCRIPT_DIR}/benchmark_model.py"

source "${SCRIPT_DIR}/env.sh"
load_project_env "${SCRIPT_DIR}/.env"
MODEL="${MODEL:-unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
CONTEXT_SIZE="${CONTEXT_SIZE:-120000}"
export MODEL OLLAMA_HOST CONTEXT_SIZE

if [[ ! -f "${BENCHMARK_SCRIPT}" ]]; then
  echo "Benchmark script not found: ${BENCHMARK_SCRIPT}" >&2
  echo "Run load2.sh first to clone the project and install prerequisites." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. Run load2.sh first." >&2
  exit 1
fi

if ! command -v ollama >/dev/null 2>&1; then
  echo "Ollama is required. Run load2.sh first." >&2
  exit 1
fi

python3 "${BENCHMARK_SCRIPT}"
