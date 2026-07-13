#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL="${MODEL:-Qwen/Qwen2.5-7B-Instruct}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"
TUNNEL_BIN="${TUNNEL_BIN:-cloudflared}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but was not found on PATH."
  exit 1
fi

if ! command -v pip3 >/dev/null 2>&1; then
  echo "pip3 is required but was not found on PATH."
  exit 1
fi

if ! python3 -c "import vllm" >/dev/null 2>&1; then
  echo "Installing vLLM..."
  python3 -m pip install --upgrade pip
  python3 -m pip install vllm
fi

if ! command -v "$TUNNEL_BIN" >/dev/null 2>&1; then
  echo "cloudflared is not installed on PATH. The server will still start, but no tunnel will be created."
fi

export VLLM_HOST="$HOST"
export VLLM_PORT="$PORT"

if pgrep -f "vllm.entrypoints.openai.api_server" >/dev/null 2>&1; then
  echo "Stopping existing vLLM server..."
  pkill -f "vllm.entrypoints.openai.api_server" || true
fi

nohup python3 -m vllm.entrypoints.openai.api_server \
  --model "$MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  >/tmp/vllm-server.log 2>&1 &

server_pid=$!
server_url="http://${HOST}:${PORT}"

for _ in {1..60}; do
  if curl -fsS "${server_url}/health" >/dev/null 2>&1 || curl -fsS "${server_url}/v1/models" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$server_pid" >/dev/null 2>&1; then
    echo "vLLM server exited early. Last log lines:"
    tail -n 50 /tmp/vllm-server.log || true
    exit 1
  fi
  sleep 2
done

echo "Testing vLLM server..."
curl -fsS "${server_url}/v1/models" >/dev/null

if command -v "$TUNNEL_BIN" >/dev/null 2>&1; then
  echo "Starting Cloudflare tunnel..."
  pkill -9 -f cloudflared || true
  : > /tmp/vllm-cloudflared.log
  cloudflared tunnel --url "$server_url" >/tmp/vllm-cloudflared.log 2>&1 &
  tunnel_pid=$!

  tunnel_url=""
  for _ in {1..20}; do
    tunnel_url=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' /tmp/vllm-cloudflared.log | head -n 1 || true)
    if [ -n "$tunnel_url" ]; then
      echo "$tunnel_url"
      break
    fi
    if ! kill -0 "$tunnel_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if [ -z "$tunnel_url" ]; then
    echo "Cloudflare tunnel URL was not printed. Last log lines:"
    tail -n 20 /tmp/vllm-cloudflared.log || true
  fi
fi

echo "vLLM server is running at ${server_url}"
