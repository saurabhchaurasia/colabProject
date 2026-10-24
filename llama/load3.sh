#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
load_llama_env "${SCRIPT_DIR}/.env"

CONTEXT_SIZE="${CONTEXT_SIZE:-120000}"
SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-8080}"
GPU_LAYERS="${GPU_LAYERS:-all}"
KV_CACHE_TYPE="${KV_CACHE_TYPE:-q8_0}"
CUDA_VERSION="${CUDA_VERSION:-12.8}"
MODEL_REPO="${MODEL_REPO:-unsloth/Qwen3.5-0.8B-GGUF}"
MODEL_FILE="${MODEL_FILE:-Qwen3.5-0.8B-Q4_K_M.gguf}"
MODEL_DIR="${MODEL_DIR:-models}"
SPLIT_MODE="${SPLIT_MODE:-layer}"
TEMPERATURE="${TEMPERATURE:-0.8}"
TOP_K="${TOP_K:-40}"
TOP_P="${TOP_P:-0.95}"
MIN_P="${MIN_P:-0.05}"
PRESENCE_PENALTY="${PRESENCE_PENALTY:-0.0}"
REPEAT_PENALTY="${REPEAT_PENALTY:-1.0}"
BATCH_SIZE="${BATCH_SIZE:-2048}"
UBATCH_SIZE="${UBATCH_SIZE:-512}"
JINJA="${JINJA:-on}"
SPEC_TYPE="${SPEC_TYPE:-none}"
SPEC_DRAFT_P_MIN="${SPEC_DRAFT_P_MIN:-0.0}"
SPEC_DRAFT_N_MAX="${SPEC_DRAFT_N_MAX:-3}"
REASONING="${REASONING:-auto}"
MODEL_PATH="${SCRIPT_DIR}/${MODEL_DIR}/${MODEL_FILE}"
INSTALL_DIR="${SCRIPT_DIR}/llama-prebuilt"
SERVER_BIN="$(find "${INSTALL_DIR}" -type f -name llama-server -print -quit 2>/dev/null || true)"
SERVER_URL="http://${SERVER_HOST}:${SERVER_PORT}"
LOG_FILE="${SCRIPT_DIR}/llama-server.log"
PID_FILE="${SCRIPT_DIR}/llama-server.pid"
if [[ "${SERVER_PORT}" != 8080 ]]; then
  LOG_FILE="${SCRIPT_DIR}/llama-server-${SERVER_PORT}.log"
  PID_FILE="${SCRIPT_DIR}/llama-server-${SERVER_PORT}.pid"
fi

if [[ ! "${CONTEXT_SIZE}" =~ ^[1-9][0-9]*$ ||
      ! "${SERVER_PORT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "CONTEXT_SIZE and SERVER_PORT must be positive integers." >&2
  exit 1
fi
if [[ ! "${GPU_LAYERS}" =~ ^(all|[0-9]+)$ ]]; then
  echo "GPU_LAYERS must be 'all' or a non-negative integer." >&2
  exit 1
fi
if [[ ! "${SPLIT_MODE}" =~ ^(none|layer|row|tensor)$ ]]; then
  echo "SPLIT_MODE must be one of: none, layer, row, tensor." >&2
  exit 1
fi
if [[ "${SPLIT_MODE}" == tensor && -z "${TENSOR_SPLIT:-}" ]]; then
  echo "TENSOR_SPLIT is required when SPLIT_MODE=tensor." >&2
  exit 1
fi
if [[ ! "${TENSOR_SPLIT:-}" =~ ^[0-9]+([.][0-9]+)?(,[0-9]+([.][0-9]+)?)*$ &&
      -n "${TENSOR_SPLIT:-}" ]]; then
  echo "TENSOR_SPLIT must be a comma-separated list of numeric GPU weights." >&2
  exit 1
fi
if [[ ! "${CUDA_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "CUDA_VERSION must use a major.minor format, for example 12.8." >&2
  exit 1
fi
if [[ ! "${KV_CACHE_TYPE}" =~ ^(f16|q8_0|q4_0)$ ]]; then
  echo "KV_CACHE_TYPE must be one of: f16, q8_0, q4_0." >&2
  exit 1
fi
if [[ ! "${JINJA}" =~ ^(on|off)$ || ! "${REASONING}" =~ ^(on|off|auto)$ ]]; then
  echo "JINJA must be on/off and REASONING must be on/off/auto." >&2
  exit 1
fi
if [[ ! "${SPEC_TYPE}" =~ ^(none|draft-mtp|draft-simple|draft-eagle3|draft-dflash|draft-dspark)$ ]]; then
  echo "Unsupported SPEC_TYPE: ${SPEC_TYPE}." >&2
  exit 1
fi
for parameter in TOP_K BATCH_SIZE UBATCH_SIZE SPEC_DRAFT_N_MAX; do
  if [[ ! "${!parameter}" =~ ^[1-9][0-9]*$ ]]; then
    echo "${parameter} must be a positive integer." >&2
    exit 1
  fi
done
if [[ ! "${SPEC_DRAFT_P_MIN}" =~ ^(0([.][0-9]+)?|1([.]0+)?)$ ]]; then
  echo "SPEC_DRAFT_P_MIN must be between 0 and 1." >&2
  exit 1
fi

missing=()
command -v curl >/dev/null 2>&1 || missing+=(curl)
command -v python3 >/dev/null 2>&1 || missing+=(python3)
command -v tar >/dev/null 2>&1 || missing+=(tar)
if (( ${#missing[@]} > 0 )); then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Missing prerequisites (${missing[*]}) and apt-get is unavailable." >&2
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
  "${apt_command[@]}" update
  "${apt_command[@]}" install -y "${missing[@]}"
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi was not found; cannot confirm NVIDIA GPU availability." >&2
  exit 1
fi
nvidia-smi
if [[ "${SPLIT_MODE}" == tensor ]]; then
  gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)"
  if [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]]; then
    IFS=',' read -r -a visible_gpu_ids <<<"${CUDA_VISIBLE_DEVICES}"
    gpu_count="${#visible_gpu_ids[@]}"
  fi
  split_count="$(awk -F, '{print NF}' <<<"${TENSOR_SPLIT}")"
  if (( gpu_count < 2 || split_count != gpu_count )); then
    echo "SPLIT_MODE=tensor requires at least two visible GPUs and one TENSOR_SPLIT weight per visible GPU." >&2
    echo "Detected ${gpu_count} visible GPU(s) and ${split_count} tensor-split weight(s)." >&2
    exit 1
  fi
fi
driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)"
if ! python3 - "${driver_version}" <<'PY'
import sys

version = tuple(int(part) for part in sys.argv[1].split(".")[:2])
raise SystemExit(0 if version >= (570, 26) else 1)
PY
then
  echo "The CUDA 12.8 prebuilt requires NVIDIA driver 570.26 or newer; found ${driver_version}." >&2
  exit 1
fi

if [[ ! -x "${SERVER_BIN:-}" ]]; then
  mkdir -p "${INSTALL_DIR}"
  latest_release="$(curl -fsSL https://api.github.com/repos/ggml-org/llama.cpp/releases/latest)"
  nightly_tag_url="$(
    python3 -c '
import json, sys
release = json.load(sys.stdin)
asset = next((asset for asset in release.get("assets", []) if asset["name"] == "nightly-tag.txt"), None)
if asset is None:
    raise SystemExit("Latest llama.cpp release has no nightly-tag.txt asset.")
print(asset["browser_download_url"])
' <<<"${latest_release}"
  )"
  nightly_tag="$(curl -fsSL "${nightly_tag_url}" | tr -d '\r\n')"
  if [[ ! "${nightly_tag}" =~ ^b[0-9]+$ ]]; then
    echo "Unexpected llama.cpp nightly release tag: ${nightly_tag}" >&2
    exit 1
  fi

  nightly_release="$(
    curl -fsSL "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/${nightly_tag}"
  )"
  mapfile -t binary_urls < <(
    python3 - "${nightly_release}" "${nightly_tag}" "${CUDA_VERSION}" <<'PY'
import json
import sys

release = json.loads(sys.argv[1])
tag = sys.argv[2]
cuda_version = sys.argv[3]
expected = (
    f"llama-{tag}-bin-ubuntu-cuda-{cuda_version}-x64.tar.gz",
    f"cudart-llama-{tag}-bin-ubuntu-cuda-{cuda_version}-x64.tar.gz",
)
assets = {asset["name"]: asset["browser_download_url"] for asset in release.get("assets", [])}
for name in expected:
    if name not in assets:
        raise SystemExit(
            f"Missing official release asset {name}; choose a CUDA_VERSION "
            "available in the llama.cpp nightly release."
        )
    print(assets[name])
PY
  )
  if (( ${#binary_urls[@]} != 2 )); then
    echo "Could not resolve the llama.cpp binary and CUDA runtime downloads." >&2
    exit 1
  fi

  echo "Downloading official llama.cpp ${nightly_tag} CUDA ${CUDA_VERSION} prebuilt binaries..."
  curl -fL --retry 3 -C - "${binary_urls[0]}" -o "${INSTALL_DIR}/llama-server.tar.gz.part"
  curl -fL --retry 3 -C - "${binary_urls[1]}" -o "${INSTALL_DIR}/cudart.tar.gz.part"
  tar -xzf "${INSTALL_DIR}/llama-server.tar.gz.part" -C "${INSTALL_DIR}"
  tar -xzf "${INSTALL_DIR}/cudart.tar.gz.part" -C "${INSTALL_DIR}"
  rm "${INSTALL_DIR}/llama-server.tar.gz.part" "${INSTALL_DIR}/cudart.tar.gz.part"

  server_path="$(find "${INSTALL_DIR}" -type f -name llama-server -print -quit)"
  if [[ -z "${server_path}" ]]; then
    echo "The downloaded archive did not contain llama-server." >&2
    exit 1
  fi
  chmod +x "${server_path}"
  SERVER_BIN="${server_path}"
fi

library_paths=("${INSTALL_DIR}")
while IFS= read -r -d '' library_path; do
  library_paths+=("${library_path}")
done < <(find "${INSTALL_DIR}" -type d -print0)
library_path_list=""
for library_path in "${library_paths[@]}"; do
  if [[ -n "${library_path_list}" ]]; then
    library_path_list+=":"
  fi
  library_path_list+="${library_path}"
done
export LD_LIBRARY_PATH="${library_path_list}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

if [[ ! -f "${MODEL_PATH}" ]]; then
  mkdir -p "$(dirname -- "${MODEL_PATH}")"
  echo "Downloading ${MODEL_REPO}/${MODEL_FILE}..."
  curl -fL --retry 3 -C - \
    "https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}?download=true" \
    -o "${MODEL_PATH}.part"
  mv "${MODEL_PATH}.part" "${MODEL_PATH}"
fi

managed_server_pid=""
if [[ -f "${PID_FILE}" ]]; then
  saved_pid="$(<"${PID_FILE}")"
  if [[ "${saved_pid}" =~ ^[1-9][0-9]*$ ]] &&
      kill -0 "${saved_pid}" >/dev/null 2>&1 &&
      [[ -r "/proc/${saved_pid}/cmdline" ]]; then
    process_args="$(tr '\0' ' ' <"/proc/${saved_pid}/cmdline")"
    if [[ "${process_args}" == *"${INSTALL_DIR}/"*llama-server* ]]; then
      managed_server_pid="${saved_pid}"
    fi
  fi
fi

if curl -fsS "${SERVER_URL}/health" >/dev/null 2>&1 &&
    [[ -z "${managed_server_pid}" ]]; then
  echo "A server not started by llama/load3.sh is already responding at ${SERVER_URL}." >&2
  echo "Stop it or choose another SERVER_PORT; refusing to use an unknown model/configuration." >&2
  exit 1
fi

if [[ -n "${managed_server_pid}" ]]; then
  echo "Restarting llama.cpp server PID ${managed_server_pid} with the current .env settings..."
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
elif [[ -f "${PID_FILE}" ]]; then
  rm -f "${PID_FILE}"
fi

server_args=(
  --model "${MODEL_PATH}"
  --host "${SERVER_HOST}"
  --port "${SERVER_PORT}"
  --ctx-size "${CONTEXT_SIZE}"
  --parallel 1
  --n-gpu-layers "${GPU_LAYERS}"
  --split-mode "${SPLIT_MODE}"
  --fit off
  --cache-type-k "${KV_CACHE_TYPE}"
  --cache-type-v "${KV_CACHE_TYPE}"
  --temp "${TEMPERATURE}"
  --top-k "${TOP_K}"
  --top-p "${TOP_P}"
  --min-p "${MIN_P}"
  --presence-penalty "${PRESENCE_PENALTY}"
  --repeat-penalty "${REPEAT_PENALTY}"
  --batch-size "${BATCH_SIZE}"
  --ubatch-size "${UBATCH_SIZE}"
  --spec-type "${SPEC_TYPE}"
  --spec-draft-p-min "${SPEC_DRAFT_P_MIN}"
  --spec-draft-n-max "${SPEC_DRAFT_N_MAX}"
  --reasoning "${REASONING}"
)
if [[ -n "${TENSOR_SPLIT:-}" ]]; then
  server_args+=(--tensor-split "${TENSOR_SPLIT}")
fi
if [[ "${JINJA}" == on ]]; then
  server_args+=(--jinja)
else
  server_args+=(--no-jinja)
fi
server_env=()
if [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]]; then
  server_env+=("CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}")
fi
echo "Starting llama.cpp server at ${SERVER_URL} with ${GPU_LAYERS} GPU layers requested..."
nohup env "${server_env[@]}" "${SERVER_BIN}" "${server_args[@]}" \
  >"${LOG_FILE}" 2>&1 </dev/null &
server_pid=$!
printf '%s\n' "${server_pid}" >"${PID_FILE}"

server_ready=false
for _ in {1..120}; do
  if curl -fsS "${SERVER_URL}/health" >/dev/null 2>&1; then
    server_ready=true
    break
  fi
  if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if [[ "${server_ready}" != true ]]; then
  echo "llama.cpp server did not become ready at ${SERVER_URL}." >&2
  if [[ -f "${LOG_FILE}" ]]; then
    tail -n 50 "${LOG_FILE}" >&2
  fi
  exit 1
fi

echo "Setup complete. Run the benchmark with: bash ${SCRIPT_DIR}/test.sh"
