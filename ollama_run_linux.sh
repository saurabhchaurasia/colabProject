#!/usr/bin/env bash
set -euo pipefail

MODEL="${MODEL:-unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M}"

ollama pull "hf.co/${MODEL}"
echo "Model '${MODEL}' pulled successfully."

echo "Testing model..."
ollama run "hf.co/${MODEL}" "Say hey for sanity check."

echo "================================"
echo "ollama ps"
ollama ps
echo "================================"