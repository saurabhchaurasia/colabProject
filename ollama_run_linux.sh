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

if command -v cloudflared >/dev/null 2>&1; then
  echo "Starting Cloudflare tunnel..."
  pkill -9 -f cloudflared || true
  : > /tmp/cloudflared.log
  "${SCRIPT_DIR}/../cloudflared-linux-amd64" tunnel --url "http://${OLLAMA_HOST}" --http-host-header "${OLLAMA_HOST}" >/tmp/cloudflared.log 2>&1 &
  cloudflared_pid=$!

  tunnel_url=""
  for _ in {1..20}; do
    tunnel_url=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log | head -n 1 || true)
    if [ -n "${tunnel_url}" ]; then
      echo "================================"
      echo "${tunnel_url}"
      break
    fi
    if ! kill -0 "${cloudflared_pid}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if [ -z "${tunnel_url}" ]; then
    echo "Cloudflare tunnel URL was not printed. Last log lines:"
    tail -n 20 /tmp/cloudflared.log || true
  fi
fi

echo "================================"
echo "ollama ps"
ollama ps
echo "================================"