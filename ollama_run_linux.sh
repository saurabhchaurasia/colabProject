#!/usr/bin/env bash
set -euo pipefail

# unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M
# unsloth/Qwen3.5-27B-MTP-GGUF:Q5_K_M
MODEL="${MODEL:-unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-32000}"
THINK="${THINK:-true}"

export OLLAMA_CONTEXT_LENGTH
export OLLAMA_KEEP_ALIVE="-1"

ollama pull "hf.co/${MODEL}"
echo "Model '${MODEL}' pulled successfully."

think_args=()
if [ "${THINK}" = "false" ]; then
  think_args+=(--think=false)
fi

echo "Testing model..."
ollama run "${think_args[@]}" "hf.co/${MODEL}" "Hi"

echo "================================"
echo "ollama ps"
ollama ps
echo "================================"