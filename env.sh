#!/usr/bin/env bash

load_project_env() {
  local env_file="${1:?An env file path is required.}"
  local model_was_set="${MODEL+x}" model_value="${MODEL-}"
  local ollama_host_was_set="${OLLAMA_HOST+x}" ollama_host_value="${OLLAMA_HOST-}"
  local context_size_was_set="${CONTEXT_SIZE+x}" context_size_value="${CONTEXT_SIZE-}"

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

  export MODEL OLLAMA_HOST CONTEXT_SIZE
}
