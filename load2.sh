#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_SCRIPT="${SCRIPT_DIR}/benchmark_model.py"
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

if [[ ! -f "${BENCHMARK_SCRIPT}" ]]; then
  echo "Benchmark script not found: ${BENCHMARK_SCRIPT}" >&2
  exit 1
fi

missing_packages=()
for command_name in curl python3 zstd; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    missing_packages+=("${command_name}")
  fi
done

if (( ${#missing_packages[@]} > 0 )); then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Missing prerequisites (${missing_packages[*]}) and apt-get is unavailable." >&2
    exit 1
  fi

  if (( EUID == 0 )); then
    apt_command=(apt-get)
  elif command -v sudo >/dev/null 2>&1; then
    apt_command=(sudo apt-get)
  else
    echo "Installing prerequisites requires root privileges or sudo." >&2
    exit 1
  fi

  echo "Installing prerequisites: ${missing_packages[*]}"
  "${apt_command[@]}" update
  "${apt_command[@]}" install -y "${missing_packages[@]}"
fi

if ! command -v ollama >/dev/null 2>&1; then
  echo "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

if ! curl -fsS "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
  echo "Starting Ollama server..."
  nohup ollama serve >/tmp/ollama-serve.log 2>&1 </dev/null &
fi

ollama_ready=false
for _ in {1..60}; do
  if curl -fsS "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    ollama_ready=true
    break
  fi
  sleep 1
done

if [[ "${ollama_ready}" != true ]]; then
  echo "Ollama did not become ready at http://${OLLAMA_HOST}." >&2
  if [[ -f /tmp/ollama-serve.log ]]; then
    tail -n 30 /tmp/ollama-serve.log >&2
  fi
  exit 1
fi

python3 "${BENCHMARK_SCRIPT}"
