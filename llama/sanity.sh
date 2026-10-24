#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
load_llama_env "${SCRIPT_DIR}/.env"

bash "${SCRIPT_DIR}/load3.sh"

CONTEXT_SIZE="${CONTEXT_SIZE:-120000}"
SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-8080}"
GPU_LAYERS="${GPU_LAYERS:-all}"
KV_CACHE_TYPE="${KV_CACHE_TYPE:-f16}"
CUDA_VERSION="${CUDA_VERSION:-12.8}"
MODEL_REPO="${MODEL_REPO:-unsloth/Qwen3.5-0.8B-GGUF}"
MODEL_FILE="${MODEL_FILE:-Qwen3.5-0.8B-UD-Q5_K_XL.gguf}"
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
DEFAULT_LLAMA_HOME="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/colabProject/llama"
if [[ -n "${LLAMA_HOME:-}" ]]; then
  APP_DIR="${LLAMA_HOME}"
elif [[ -x "${SCRIPT_DIR}/llama-prebuilt/llama-server" ]] ||
    [[ ! -x "${DEFAULT_LLAMA_HOME}/llama-prebuilt/llama-server" ]]; then
  APP_DIR="${SCRIPT_DIR}"
else
  APP_DIR="${DEFAULT_LLAMA_HOME}"
fi
INSTALL_DIR="${APP_DIR}/llama-prebuilt"
SERVER_BIN="$(find "${INSTALL_DIR}" -type f -name llama-server -executable -print -quit 2>/dev/null || true)"
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
if [[ ! -x "${SERVER_BIN:-}" ]]; then
  echo "llama-server was not found; run load3.sh to install it." >&2
  exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi was not found; cannot confirm NVIDIA GPU availability." >&2
  exit 1
fi
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

server_already_running=false
if [[ -n "${managed_server_pid}" ]]; then
  for _ in {1..120}; do
    if curl -fsS "${SERVER_URL}/health" >/dev/null 2>&1; then
      server_already_running=true
      echo "llama.cpp server PID ${managed_server_pid} is already running at ${SERVER_URL}."
      break
    fi
    if ! kill -0 "${managed_server_pid}" >/dev/null 2>&1; then
      managed_server_pid=""
      break
    fi
    sleep 1
  done
  if [[ "${server_already_running}" != true && -n "${managed_server_pid}" ]]; then
    echo "llama.cpp server PID ${managed_server_pid} is running but not healthy at ${SERVER_URL}." >&2
    echo "Check ${LOG_FILE}; refusing to download or replace a running server." >&2
    if [[ -f "${LOG_FILE}" ]]; then
      tail -n 50 "${LOG_FILE}" >&2
    fi
    exit 1
  fi
fi

if [[ "${server_already_running}" != true ]] &&
    curl -fsS "${SERVER_URL}/health" >/dev/null 2>&1; then
  echo "A server not started by llama/load3.sh is already responding at ${SERVER_URL}." >&2
  echo "Stop it or choose another SERVER_PORT; refusing to use an unknown model/configuration." >&2
  exit 1
fi

if [[ "${server_already_running}" != true ]]; then
  if [[ -f "${PID_FILE}" ]]; then
    rm -f "${PID_FILE}"
  fi

  if [[ ! -f "${MODEL_PATH}" ]]; then
    mkdir -p "$(dirname -- "${MODEL_PATH}")"
    echo "Downloading ${MODEL_REPO}/${MODEL_FILE}..."
    curl -fL --retry 3 -C - \
      "https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}?download=true" \
      -o "${MODEL_PATH}.part"
    mv "${MODEL_PATH}.part" "${MODEL_PATH}"
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
fi

python3 - <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

url = f"http://{os.environ['SERVER_HOST']}:{os.environ['SERVER_PORT']}/v1/chat/completions"
request = urllib.request.Request(
    url,
    data=json.dumps(
        {
            "model": os.environ["MODEL_FILE"],
            "messages": [
                {"role": "user", "content": "Hi! Please reply with one short greeting."}
            ],
            "max_tokens": 128,
            "chat_template_kwargs": {"enable_thinking": False},
            "temperature": float(os.environ.get("TEMPERATURE", "0.8")),
            "top_k": int(os.environ.get("TOP_K", "40")),
            "top_p": float(os.environ.get("TOP_P", "0.95")),
            "min_p": float(os.environ.get("MIN_P", "0.05")),
            "presence_penalty": float(os.environ.get("PRESENCE_PENALTY", "0.0")),
            "repeat_penalty": float(os.environ.get("REPEAT_PENALTY", "1.0")),
            "stream": False,
        }
    ).encode("utf-8"),
    headers={"Content-Type": "application/json"},
    method="POST",
)

print("Sending initial chat sanity prompt with thinking disabled...", flush=True)
try:
    with urllib.request.urlopen(request, timeout=3600) as response:
        result = json.loads(response.read().decode("utf-8"))
except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", errors="replace")
    print(f"llama.cpp API returned HTTP {exc.code}: {detail}", file=sys.stderr)
    raise SystemExit(1) from exc
except urllib.error.URLError as exc:
    print(f"Could not reach llama.cpp server: {exc}", file=sys.stderr)
    raise SystemExit(1) from exc

choices = result.get("choices", [])
if not choices:
    raise SystemExit("llama.cpp chat response did not include any choices.")
message = choices[0].get("message", {})
content = message.get("content", "")
if not content:
    print(
        "The model returned no visible answer text. "
        f"Finish reason: {choices[0].get('finish_reason', 'unknown')}.",
        file=sys.stderr,
    )
    raise SystemExit(1)
print(f"Response: {content}")
timings = result.get("timings", {})
if timings:
    print(
        f"Prompt tokens: {timings.get('prompt_n', 'n/a')}; "
        f"generated tokens: {timings.get('predicted_n', 'n/a')}; "
        f"generation time: {float(timings.get('predicted_ms', 0)) / 1000:.3f}s"
    )
PY
