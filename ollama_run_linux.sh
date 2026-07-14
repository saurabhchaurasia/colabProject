#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${MODEL:-hf.co/unsloth/Qwen3.5-2B-MTP-GGUF:Q4_K_M}"
CONTEXT_SIZE="${CONTEXT_SIZE:-32000}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

# if ! command -v zstd >/dev/null 2>&1; then
#   echo "Installing zstd..."
#   sudo apt-get update
#   sudo apt-get install -y zstd
# fi

# if ! command -v ollama >/dev/null 2>&1; then
#   echo "Installing Ollama..."
#   curl -fsSL https://ollama.com/install.sh | sh
# fi

# echo "Downloading cloudflared..."
# curl -fsSL -o "${SCRIPT_DIR}/cloudflared-linux-amd64" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
# chmod +x "${SCRIPT_DIR}/cloudflared-linux-amd64"

export OLLAMA_CONTEXT_LENGTH="$CONTEXT_SIZE"
export OLLAMA_KEEP_ALIVE="-1"

# if pgrep -f "ollama serve" >/dev/null 2>&1; then
#   echo "Stopping existing Ollama server..."
#   pkill -f "ollama serve" || true
# fi

# nohup ollama serve >/tmp/ollama-serve.log 2>&1 &

# for _ in {1..30}; do
#   if curl -fsS "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
#     break
#   fi
#   sleep 1
# done

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

echo "ollama ps"
ollama ps