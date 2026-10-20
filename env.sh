#!/usr/bin/env bash

load_project_env() {
  local env_file="${1:?An env file path is required.}"
  local model_was_set="${MODEL+x}" model_value="${MODEL-}"
  local ollama_host_was_set="${OLLAMA_HOST+x}" ollama_host_value="${OLLAMA_HOST-}"
  local context_size_was_set="${CONTEXT_SIZE+x}" context_size_value="${CONTEXT_SIZE-}"
  local num_gpu_layers_was_set="${NUM_GPU_LAYERS+x}" num_gpu_layers_value="${NUM_GPU_LAYERS-}"
  local kv_cache_type_was_set="${OLLAMA_KV_CACHE_TYPE+x}" kv_cache_type_value="${OLLAMA_KV_CACHE_TYPE-}"

  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi

  if [[ -n "${model_was_set}" ]]; then
    MODEL="${model_value}"
  fi
  if [[ -n "${ollama_host_was_set}" ]]; then
    OLLAMA_HOST="${ollama_host_value}"
  fi
  if [[ -n "${context_size_was_set}" ]]; then
    CONTEXT_SIZE="${context_size_value}"
  fi
  if [[ -n "${num_gpu_layers_was_set}" ]]; then
    NUM_GPU_LAYERS="${num_gpu_layers_value}"
  fi
  if [[ -n "${kv_cache_type_was_set}" ]]; then
    OLLAMA_KV_CACHE_TYPE="${kv_cache_type_value}"
  fi

  export MODEL OLLAMA_HOST CONTEXT_SIZE NUM_GPU_LAYERS OLLAMA_KV_CACHE_TYPE
}

stop_standalone_ollama_server() {
  local cmdline pid server_pid
  local -a args server_pids=()

  for cmdline in /proc/[0-9]*/cmdline; do
    [[ -r "${cmdline}" ]] || continue
    pid="${cmdline#/proc/}"
    pid="${pid%/cmdline}"
    args=()
    mapfile -d '' -t args <"${cmdline}" 2>/dev/null || continue
    if (( ${#args[@]} == 2 )) &&
      [[ "${args[0]##*/}" == "ollama" && "${args[1]}" == "serve" ]]; then
      server_pids+=("${pid}")
    fi
  done

  if (( ${#server_pids[@]} > 1 )); then
    echo "Found multiple standalone Ollama servers; refusing to stop an ambiguous process set." >&2
    printf 'PID: %s\n' "${server_pids[@]}" >&2
    return 1
  fi
  if (( ${#server_pids[@]} == 0 )); then
    return 0
  fi

  server_pid="${server_pids[0]}"
  echo "Stopping standalone Ollama server (PID ${server_pid})..."
  kill -TERM "${server_pid}"
  for _ in {1..30}; do
    if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Ollama server PID ${server_pid} did not stop within 30 seconds." >&2
  return 1
}
