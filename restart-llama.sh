#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_DIR="${SCRIPT_DIR}/llama"
source "${LLAMA_DIR}/env.sh"
load_llama_env "${LLAMA_DIR}/.env"

bash "${LLAMA_DIR}/load3.sh"

SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-8150}"
DEFAULT_LLAMA_HOME="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/colabProject/llama"
if [[ -n "${LLAMA_HOME:-}" ]]; then
  APP_DIR="${LLAMA_HOME}"
elif [[ -x "${LLAMA_DIR}/llama-prebuilt/llama-server" ]] ||
    [[ ! -x "${DEFAULT_LLAMA_HOME}/llama-prebuilt/llama-server" ]]; then
  APP_DIR="${LLAMA_DIR}"
else
  APP_DIR="${DEFAULT_LLAMA_HOME}"
fi
INSTALL_DIR="${APP_DIR}/llama-prebuilt"
PID_FILE="${LLAMA_DIR}/llama-server.pid"
if [[ "${SERVER_PORT}" != 8080 ]]; then
  PID_FILE="${LLAMA_DIR}/llama-server-${SERVER_PORT}.pid"
fi
SERVER_URL="http://${SERVER_HOST}:${SERVER_PORT}"

managed_server_pid=""
if [[ -f "${PID_FILE}" ]]; then
  saved_pid="$(<"${PID_FILE}")"
  if [[ "${saved_pid}" =~ ^[1-9][0-9]*$ ]] &&
      kill -0 "${saved_pid}" >/dev/null 2>&1 &&
      [[ -r "/proc/${saved_pid}/cmdline" ]]; then
    process_args="$(tr '\0' ' ' <"/proc/${saved_pid}/cmdline")"
    if [[ "${process_args}" == *"${INSTALL_DIR}/"*llama-server* &&
          "${process_args}" == *"--port ${SERVER_PORT}"* ]]; then
      managed_server_pid="${saved_pid}"
    fi
  fi
fi

if [[ -n "${managed_server_pid}" ]]; then
  echo "Stopping managed llama.cpp server PID ${managed_server_pid} at ${SERVER_URL}..."
  kill -TERM "${managed_server_pid}"
  for _ in {1..30}; do
    if ! kill -0 "${managed_server_pid}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if kill -0 "${managed_server_pid}" >/dev/null 2>&1; then
    echo "llama.cpp server PID ${managed_server_pid} did not stop within 30 seconds." >&2
    exit 1
  fi
  rm -f "${PID_FILE}"
elif curl --connect-timeout 1 --max-time 2 -fsS \
    "${SERVER_URL}/health" >/dev/null 2>&1; then
  echo "A server not managed by this project is responding at ${SERVER_URL}; refusing to stop it." >&2
  exit 1
elif [[ -f "${PID_FILE}" ]]; then
  rm -f "${PID_FILE}"
fi

echo "Starting llama.cpp with the selected .env profile via sanity.sh..."
exec bash "${LLAMA_DIR}/sanity.sh"
