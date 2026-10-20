#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
load_project_env "${SCRIPT_DIR}/.env"

MODEL="${MODEL:-unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
CONTEXT_SIZE="${CONTEXT_SIZE:-120000}"
NUM_GPU_LAYERS="${NUM_GPU_LAYERS:-999}"

if ! command -v ollama >/dev/null 2>&1; then
  echo "Ollama is required. Run load2.sh first." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. Run load2.sh first." >&2
  exit 1
fi

if [[ ! "${CONTEXT_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
  echo "CONTEXT_SIZE must be a positive integer." >&2
  exit 1
fi
if [[ ! "${NUM_GPU_LAYERS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "NUM_GPU_LAYERS must be a positive integer." >&2
  exit 1
fi

export MODEL OLLAMA_HOST CONTEXT_SIZE NUM_GPU_LAYERS
model="hf.co/${MODEL#hf.co/}"

echo "Pulling ${model}..."
ollama pull "${model}"

echo "Sending initial request with a ${CONTEXT_SIZE}-token context and up to ${NUM_GPU_LAYERS} GPU layers."
echo "This may take a while while Ollama loads the model and prepares the context."
python3 - <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

model = os.environ["MODEL"]
if not model.startswith("hf.co/"):
    model = f"hf.co/{model}"

request = urllib.request.Request(
    f"http://{os.environ['OLLAMA_HOST']}/api/chat",
    data=json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": "hi"}],
            "stream": False,
            "think": False,
            "options": {
                "num_ctx": int(os.environ["CONTEXT_SIZE"]),
                "num_gpu": int(os.environ["NUM_GPU_LAYERS"]),
                "num_predict": 1,
                "temperature": 0,
            },
        }
    ).encode("utf-8"),
    headers={"Content-Type": "application/json"},
    method="POST",
)

try:
    with urllib.request.urlopen(request, timeout=3600) as response:
        result = json.loads(response.read().decode("utf-8"))
except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", errors="replace")
    print(f"Ollama API returned HTTP {exc.code}: {detail}", file=sys.stderr)
    raise SystemExit(1) from exc
except urllib.error.URLError as exc:
    print(f"Could not reach Ollama: {exc}", file=sys.stderr)
    raise SystemExit(1) from exc

print("Initial request completed.")
print(f"Response: {result.get('message', {}).get('content', '')}")
print(f"Prompt tokens: {result.get('prompt_eval_count', 'n/a')}")
print(f"Generated tokens: {result.get('eval_count', 'n/a')}")
PY

echo "================================"
echo "ollama ps"
ollama ps
echo "================================"
