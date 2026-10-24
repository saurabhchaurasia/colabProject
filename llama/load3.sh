#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "${SCRIPT_PATH}")"
PROJECT_DIR="${COLAB_PROJECT_DIR:-/workspace/colabProject}"
PROJECT_REPO="https://github.com/saurabhchaurasia/colabProject"
DEFAULT_LLAMA_HOME="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/colabProject/llama"
if [[ -n "${LLAMA_HOME:-}" ]]; then
  APP_DIR="${LLAMA_HOME}"
else
  APP_DIR="${PROJECT_DIR}/llama"
fi
INSTALL_DIR="${APP_DIR}/llama-prebuilt"
CUDA_VERSION="12.8"
SERVER_BIN="$(find "${INSTALL_DIR}" -type f -name llama-server -executable -print -quit 2>/dev/null || true)"

if [[ ! "${CUDA_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "CUDA_VERSION must use a major.minor format, for example 12.8." >&2
  exit 1
fi

missing=()
command -v curl >/dev/null 2>&1 || missing+=(curl)
command -v python3 >/dev/null 2>&1 || missing+=(python3)
command -v tar >/dev/null 2>&1 || missing+=(tar)
command -v git >/dev/null 2>&1 || missing+=(git)
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

if [[ -d "${PROJECT_DIR}/.git" ]]; then
  project_remote="$(git -C "${PROJECT_DIR}" remote get-url origin)"
  project_remote="${project_remote%.git}"
  project_remote="${project_remote%/}"
  if [[ "${project_remote}" != "${PROJECT_REPO}" ]]; then
    echo "Refusing to pull ${PROJECT_DIR}: origin is ${project_remote}, not ${PROJECT_REPO}." >&2
    exit 1
  fi
  project_branch="$(git -C "${PROJECT_DIR}" branch --show-current)"
  if [[ "${project_branch}" != main ]]; then
    echo "Refusing to pull ${PROJECT_DIR}: checkout branch is '${project_branch}', expected 'main'." >&2
    exit 1
  fi
  if [[ -n "$(git -C "${PROJECT_DIR}" status --porcelain)" ]]; then
    echo "Refusing to pull ${PROJECT_DIR}: the checkout has local changes." >&2
    echo "Commit or stash those changes, then run load3.sh again." >&2
    exit 1
  fi
  echo "Pulling the latest colabProject into ${PROJECT_DIR}..."
  git -C "${PROJECT_DIR}" pull --ff-only origin main
elif [[ -e "${PROJECT_DIR}" && -n "$(find "${PROJECT_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "Cannot clone colabProject: ${PROJECT_DIR} exists and is not an empty Git checkout." >&2
  exit 1
else
  mkdir -p "$(dirname -- "${PROJECT_DIR}")"
  echo "Cloning colabProject into ${PROJECT_DIR}..."
  git clone --branch main --single-branch "${PROJECT_REPO}.git" "${PROJECT_DIR}"
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi was not found; cannot confirm NVIDIA GPU availability." >&2
  exit 1
fi
nvidia-smi
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
else
  echo "llama.cpp is already installed at ${SERVER_BIN}; skipping binary download."
fi

if [[ ! -x "${SERVER_BIN}" ]]; then
  echo "llama.cpp setup completed without an executable llama-server." >&2
  exit 1
fi

echo "colabProject is up to date at ${PROJECT_DIR}."
echo "llama.cpp prerequisites and prebuilt are ready at ${INSTALL_DIR}."
echo "Run ${PROJECT_DIR}/llama/sanity.sh to download the model and start the server."
