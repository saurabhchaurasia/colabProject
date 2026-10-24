#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
load_llama_env "${SCRIPT_DIR}/.env"

bash "${SCRIPT_DIR}/load3.sh"

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
            "max_tokens": 64,
            "temperature": 0,
            "stream": False,
            "chat_template_kwargs": {"enable_thinking": False},
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
