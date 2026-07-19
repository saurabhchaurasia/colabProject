#!/usr/bin/env bash
set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
CLOUDFLARED_BIN="./cloudflared-linux-amd64"

if [ ! -x "${CLOUDFLARED_BIN}" ]; then
  echo "Downloading cloudflared..."
  curl -fsSL -o "${CLOUDFLARED_BIN}" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x "${CLOUDFLARED_BIN}"
fi

echo "Starting Cloudflare tunnel..."
pkill -9 -f cloudflared || true
: > /tmp/cloudflared.log
"${CLOUDFLARED_BIN}" tunnel --url "http://${OLLAMA_HOST}" --http-host-header "${OLLAMA_HOST}" >/tmp/cloudflared.log 2>&1 &
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
