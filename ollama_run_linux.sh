#!/usr/bin/env bash
set -euo pipefail

# unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M
# unsloth/Qwen3.5-27B-MTP-GGUF:Q5_K_M
MODEL="${MODEL:-unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M}"
CONTEXT_SIZE="${CONTEXT_SIZE:-32000}"

export OLLAMA_CONTEXT_LENGTH="$CONTEXT_SIZE"
export OLLAMA_KEEP_ALIVE="-1"

ollama pull "hf.co/${MODEL}"
echo "Model '${MODEL}' pulled successfully."

echo "Testing model..."
ollama run "hf.co/${MODEL}" "Hi"

echo "================================"
echo "ollama ps"
ollama ps
echo "================================"