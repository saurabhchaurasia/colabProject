#!/usr/bin/env bash

load_llama_env() {
  local env_file="${1:?An env file path is required.}"
  local name
  local profile_prefix
  local profile_value
  local profile_name
  local -a profile_names=(
    MODEL_REPO MODEL_FILE MODEL_DIR SERVER_PORT CONTEXT_SIZE GPU_LAYERS
    KV_CACHE_TYPE SPLIT_MODE TENSOR_SPLIT TEMPERATURE TOP_K TOP_P MIN_P
    PRESENCE_PENALTY REPEAT_PENALTY BATCH_SIZE UBATCH_SIZE JINJA SPEC_TYPE
    SPEC_DRAFT_P_MIN SPEC_DRAFT_N_MAX REASONING
  )
  local -a names=(
    PROFILE MODEL_REPO MODEL_FILE MODEL_DIR SERVER_HOST SERVER_PORT CONTEXT_SIZE
    GPU_LAYERS KV_CACHE_TYPE CUDA_VERSION CUDA_VISIBLE_DEVICES SPLIT_MODE
    TENSOR_SPLIT TEMPERATURE TOP_K TOP_P MIN_P PRESENCE_PENALTY REPEAT_PENALTY
    BATCH_SIZE UBATCH_SIZE JINJA SPEC_TYPE SPEC_DRAFT_P_MIN SPEC_DRAFT_N_MAX
    REASONING
  )
  local -A overrides=()
  local -A override_set=()

  for name in "${names[@]}"; do
    if [[ -v "${name}" ]]; then
      overrides["${name}"]="${!name}"
      override_set["${name}"]=true
    fi
  done

  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    if ! source "${env_file}"; then
      set +a
      return 1
    fi
    set +a
  fi

  if [[ "${override_set[PROFILE]:-}" == true ]]; then
    PROFILE="${overrides[PROFILE]}"
  fi

  case "${PROFILE:-base}" in
    base) profile_prefix=BASE ;;
    dual) profile_prefix=DUAL ;;
    *)
      echo "PROFILE must be 'base' or 'dual'; received '${PROFILE}'." >&2
      return 1
      ;;
  esac

  for name in "${profile_names[@]}"; do
    profile_name="${profile_prefix}_${name}"
    if [[ ! -v "${profile_name}" ]]; then
      echo "Missing ${profile_name} in ${env_file}." >&2
      return 1
    fi
    profile_value="${!profile_name}"
    printf -v "${name}" '%s' "${profile_value}"
  done

  for name in "${names[@]}"; do
    if [[ "${override_set[${name}]:-}" == true ]]; then
      printf -v "${name}" '%s' "${overrides[${name}]}"
    fi
    if [[ -v "${name}" ]]; then
      export "${name}"
    fi
  done
}
