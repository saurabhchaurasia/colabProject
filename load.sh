#!/bin/bash

# Cause the script to exit on failure.
set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
load_project_env "${SCRIPT_DIR}/.env"

cd /workspace/

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

OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE:-q8_0}"
case "${OLLAMA_KV_CACHE_TYPE}" in
  f16|q8_0|q4_0) ;;
  *)
    echo "OLLAMA_KV_CACHE_TYPE must be one of: f16, q8_0, q4_0." >&2
    exit 1
    ;;
esac

if command -v systemctl >/dev/null 2>&1 &&
  systemctl cat ollama.service >/dev/null 2>&1 &&
  systemctl is-active --quiet ollama.service; then
  if (( EUID == 0 )); then
    systemctl_cmd=(systemctl)
  elif command -v sudo >/dev/null 2>&1; then
    systemctl_cmd=(sudo systemctl)
  else
    echo "Restarting the Ollama systemd service requires root privileges or sudo." >&2
    exit 1
  fi

  dropin_dir="/run/systemd/system/ollama.service.d"
  dropin_file="${dropin_dir}/kv-cache-type.conf"
  if (( EUID == 0 )); then
    mkdir -p "${dropin_dir}"
    printf '[Service]\nEnvironment=OLLAMA_KV_CACHE_TYPE=%s\n' \
      "${OLLAMA_KV_CACHE_TYPE}" >"${dropin_file}"
  else
    sudo mkdir -p "${dropin_dir}"
    printf '[Service]\nEnvironment=OLLAMA_KV_CACHE_TYPE=%s\n' \
      "${OLLAMA_KV_CACHE_TYPE}" | sudo tee "${dropin_file}" >/dev/null
  fi
  "${systemctl_cmd[@]}" daemon-reload
  "${systemctl_cmd[@]}" restart ollama.service
else
  stop_standalone_ollama_server
  nohup env \
    OLLAMA_HOST="${OLLAMA_HOST}" \
    OLLAMA_KV_CACHE_TYPE="${OLLAMA_KV_CACHE_TYPE}" \
    ollama serve >/tmp/ollama-serve.log 2>&1 </dev/null &
fi

for _ in {1..30}; do
  if curl -fsS "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# download repo
if [ ! -d "colabProject" ]; then
  git clone https://github.com/saurabhchaurasia/colabProject.git
fi
cd colabProject
chmod +x ollama_run_linux.sh cloudflare.sh

# auto run ollama_run_linux.sh and cloudflare.sh in parallel
# bash cloudflare.sh & 
# cloudflare_pid=$!

bash ollama_run_linux.sh & 
ollama_pid=$!

# wait "${cloudflare_pid}"
wait "${ollama_pid}"