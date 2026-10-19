#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="/workspace/colabProject"
NEED_CLONE=false
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"

if [[ ! -f "${SCRIPT_DIR}/benchmark_model.py" && -f "${REPO_DIR}/benchmark_model.py" ]]; then
  SCRIPT_DIR="${REPO_DIR}"
elif [[ ! -f "${SCRIPT_DIR}/benchmark_model.py" ]]; then
  NEED_CLONE=true
fi

if [[ "${NEED_CLONE}" == true && -e "${REPO_DIR}" ]]; then
  echo "Cannot clone repository: ${REPO_DIR} already exists without benchmark_model.py." >&2
  exit 1
fi

missing_packages=(curl python3 zstd)
if [[ "${NEED_CLONE}" == true ]] && ! command -v git >/dev/null 2>&1; then
  missing_packages+=(git)
fi

packages_to_install=()
for package in "${missing_packages[@]}"; do
  if ! command -v "${package}" >/dev/null 2>&1; then
    packages_to_install+=("${package}")
  fi
done

if (( ${#packages_to_install[@]} > 0 )); then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Missing prerequisites (${packages_to_install[*]}) and apt-get is unavailable." >&2
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

  echo "Installing prerequisites: ${packages_to_install[*]}"
  "${apt_command[@]}" update
  "${apt_command[@]}" install -y "${packages_to_install[@]}"
fi

if [[ "${NEED_CLONE}" == true ]]; then
  mkdir -p "$(dirname -- "${REPO_DIR}")"
  echo "Cloning benchmark repository..."
  git clone https://github.com/saurabhchaurasia/colabProject.git "${REPO_DIR}"
  SCRIPT_DIR="${REPO_DIR}"
fi

if [[ ! -f "${SCRIPT_DIR}/test.sh" ]]; then
  echo "Test script not found: ${SCRIPT_DIR}/test.sh" >&2
  exit 1
fi
chmod +x "${SCRIPT_DIR}/test.sh"

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

echo "Setup complete. Run the benchmark with: bash ${SCRIPT_DIR}/test.sh"
