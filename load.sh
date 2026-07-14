#!/bin/bash

#
cd /workspace/
# Cause the script to exit on failure.
set -eo pipefail

# download ollama
if ! command -v zstd >/dev/null 2>&1; then
  echo "Installing zstd..."
  sudo apt-get update
  sudo apt-get install -y zstd
fi

if ! command -v ollama >/dev/null 2>&1; then
  echo "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

# ollama serve
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

if pgrep -f "ollama serve" >/dev/null 2>&1; then
  echo "Stopping existing Ollama server..."
  pkill -f "ollama serve" || true
fi

nohup ollama serve >/tmp/ollama-serve.log 2>&1 &

for _ in {1..30}; do
  if curl -fsS "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# download cloudflared
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Downloading cloudflared..."
curl -fsSL -o "cloudflared-linux-amd64" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x "cloudflared-linux-amd64"

# download repo
if [ ! -d "ColabProject" ]; then
  git clone https://github.com/saurabhchaurasia/ColabProject.git
fi
cd ColabProject
chmod +x ollama_run_linux.sh

# auto run ollama_run_linux.sh
# bash ollama_run_linux.sh