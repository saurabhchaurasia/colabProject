#!/usr/bin/env bash

load_llama_env() {
  local env_file="${1:?An env file path is required.}"
  local -a names=(
    MODEL_REPO MODEL_FILE MODEL_DIR SERVER_HOST SERVER_PORT CONTEXT_SIZE
    GPU_LAYERS KV_CACHE_TYPE CUDA_VERSION CUDA_VISIBLE_DEVICES
  )
  local name

  for name in "${names[@]}"; do
    if [[ -v "${name}" ]]; then
      printf -v "llama_env_override_${name}" '%s' "${!name}"
      printf -v "llama_env_override_set_${name}" '%s' true
    fi
  done

  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi

  for name in "${names[@]}"; do
    local set_var="llama_env_override_set_${name}"
    local value_var="llama_env_override_${name}"
    if [[ "${!set_var:-}" == true ]]; then
      printf -v "${name}" '%s' "${!value_var}"
    fi
    export "${name}"
  done
}
