#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
load_project_env "${SCRIPT_DIR}/.env"

OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-q8_0}"
case "${OLLAMA_KV_CACHE_TYPE}" in
  f16|q8_0|q4_0) ;;
  *)
    echo "OLLAMA_KV_CACHE_TYPE must be one of: f16, q8_0, q4_0." >&2
    exit 1
    ;;
esac
export OLLAMA_KV_CACHE_TYPE

if ! command -v ollama >/dev/null 2>&1; then
  echo "Ollama is required. Run load2.sh first." >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1 ||
  ! systemctl is-active --quiet ollama.service; then
  stop_standalone_ollama_server
fi

echo "Starting Ollama with OLLAMA_KV_CACHE_TYPE=${OLLAMA_KV_CACHE_TYPE} via load.sh..."
exec bash "${SCRIPT_DIR}/load.sh"
