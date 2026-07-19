#!/usr/bin/env bash
set -euo pipefail

# unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M
# unsloth/Qwen3.5-27B-MTP-GGUF:Q5_K_M
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${MODEL:-hf.co/unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M}"
CONTEXT_SIZE="${CONTEXT_SIZE:-32000}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

export OLLAMA_CONTEXT_LENGTH="$CONTEXT_SIZE"
export OLLAMA_KEEP_ALIVE="-1"

ollama pull "$MODEL"
echo "Model '${MODEL}' pulled successfully."

echo "Testing model..."
ollama run "$MODEL" "Just respond Hi for sanity check."

echo "================================"
echo "ollama ps"
ollama ps
echo "================================"

bash cloudflare.sh