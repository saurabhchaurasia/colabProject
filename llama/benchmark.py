#!/usr/bin/env python3
import json
import math
import os
import re
import shlex
import sys
import time
import urllib.error
import urllib.request


def load_environment():
    env_file = os.path.join(os.path.dirname(__file__), ".env")
    try:
        with open(env_file, encoding="utf-8") as env_stream:
            lines = env_stream.readlines()
    except FileNotFoundError:
        return

    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, raw_value = line.partition("=")
        key = key.strip()
        if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            raise ValueError(f"Invalid .env entry at {env_file}:{line_number}.")
        try:
            values = shlex.split(raw_value, comments=True)
        except ValueError as exc:
            raise ValueError(f"Invalid .env value at {env_file}:{line_number}.") from exc
        if len(values) > 1:
            raise ValueError(
                f"Quote values containing spaces in {env_file}:{line_number}."
            )
        os.environ.setdefault(key, values[0] if values else "")


load_environment()

SERVER_HOST = os.environ.get("SERVER_HOST", "127.0.0.1")
SERVER_PORT = int(os.environ.get("SERVER_PORT", "8150"))
CONTEXT_SIZE = int(os.environ.get("CONTEXT_SIZE", "120000"))
NUM_PREDICT = 4096
CHECKPOINTS = (10, 25, 50, 75, 90)
TEMPERATURE = float(os.environ.get("TEMPERATURE", "0.8"))
TOP_K = int(os.environ.get("TOP_K", "40"))
TOP_P = float(os.environ.get("TOP_P", "0.95"))
MIN_P = float(os.environ.get("MIN_P", "0.05"))
PRESENCE_PENALTY = float(os.environ.get("PRESENCE_PENALTY", "0.0"))
REPEAT_PENALTY = float(os.environ.get("REPEAT_PENALTY", "1.0"))
BASE_URL = f"http://{SERVER_HOST}:{SERVER_PORT}"
REQUEST_TIMEOUT = 3600
CALIBRATION_ATTEMPTS = 6
OUTPUT_SENTENCE = "This is neutral benchmark context used to measure inference."
OUTPUT_GRAMMAR = (
    "root ::= sentence+\n"
    f'sentence ::= "{OUTPUT_SENTENCE}" " "\n'
)


def post_json(path, body):
    request = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"llama.cpp API returned HTTP {exc.code}: {detail}") from exc


def ensure_server_is_running():
    request = urllib.request.Request(f"{BASE_URL}/health")
    try:
        with urllib.request.urlopen(request, timeout=5):
            return
    except (urllib.error.URLError, TimeoutError) as exc:
        raise SystemExit(
            f"Cannot reach llama.cpp server at {BASE_URL}. Run sanity.sh first."
        ) from exc


def tokenize_count(text):
    result = post_json("/tokenize", {"content": text, "add_special": True})
    tokens = result.get("tokens")
    if not isinstance(tokens, list):
        raise RuntimeError("llama.cpp /tokenize response did not include a tokens list.")
    return len(tokens)


def make_prompt(target_prompt_tokens):
    instruction = (
        "Repeat only the exact benchmark sentence below, separated by spaces. "
        "Do not add any other words.\n\n"
    )
    filler_unit = f"{OUTPUT_SENTENCE} "
    chars = max(0, (target_prompt_tokens - len(instruction) // 4) * 4)
    best_prompt = instruction
    best_count = tokenize_count(best_prompt)

    for _ in range(CALIBRATION_ATTEMPTS):
        filler = (filler_unit * (chars // len(filler_unit) + 1))[:chars]
        prompt = instruction + filler
        prompt_tokens = tokenize_count(prompt)
        if abs(prompt_tokens - target_prompt_tokens) < abs(
            best_count - target_prompt_tokens
        ):
            best_prompt, best_count = prompt, prompt_tokens
        error = target_prompt_tokens - prompt_tokens
        if abs(error) <= max(4, math.ceil(CONTEXT_SIZE * 0.005)):
            return prompt
        chars = max(0, chars + error * 4)

    print(
        f"  Warning: calibrated prompt to {best_count:,} tokens; "
        f"target was {target_prompt_tokens:,}.",
        flush=True,
    )
    return best_prompt


def completion(prompt, num_predict):
    request = urllib.request.Request(
        f"{BASE_URL}/completion",
        data=json.dumps(
            {
                "prompt": prompt,
                "n_predict": num_predict,
                "temperature": TEMPERATURE,
                "top_k": TOP_K,
                "top_p": TOP_P,
                "min_p": MIN_P,
                "presence_penalty": PRESENCE_PENALTY,
                "repeat_penalty": REPEAT_PENALTY,
                "grammar": OUTPUT_GRAMMAR,
                "ignore_eos": True,
                "cache_prompt": False,
                "stream": True,
            }
        ).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        },
        method="POST",
    )
    timings = None
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            for line in response:
                line = line.strip()
                if not line or not line.startswith(b"data:"):
                    continue
                payload = line[len(b"data:") :].strip()
                if payload == b"[DONE]":
                    break
                chunk = json.loads(payload.decode("utf-8"))
                text = chunk.get("content", "")
                if text:
                    sys.stdout.write(text)
                    sys.stdout.flush()
                if chunk.get("timings"):
                    timings = chunk["timings"]
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"llama.cpp API returned HTTP {exc.code}: {detail}"
        ) from exc

    if not isinstance(timings, dict):
        raise RuntimeError(
            "llama.cpp stream ended without final timing metrics."
        )
    required = ("prompt_n", "prompt_ms", "predicted_n", "predicted_ms")
    if any(key not in timings for key in required):
        raise RuntimeError(f"llama.cpp timing metrics are incomplete: {timings}")
    return timings


def rate(tokens, milliseconds):
    return tokens * 1000 / milliseconds if tokens and milliseconds else None


def fmt_rate(value):
    return "n/a" if value is None else f"{value:.2f}"


def result_row(target, timings):
    prompt_tokens = int(timings["prompt_n"])
    generated = int(timings["predicted_n"])
    actual_tokens = prompt_tokens + generated
    actual_percent = actual_tokens / CONTEXT_SIZE * 100
    return (
        f"{target:>6}%  {actual_percent:>9.2f}%  "
        f"{actual_tokens:>8,}/{CONTEXT_SIZE:<9,}  "
        f"{prompt_tokens:>14,}  "
        f"{float(timings['prompt_ms']) / 1000:>10.2f}s  "
        f"{fmt_rate(rate(prompt_tokens, float(timings['prompt_ms']))):>14}  "
        f"{generated:>10,}  "
        f"{float(timings['predicted_ms']) / 1000:>9.2f}s  "
        f"{fmt_rate(rate(generated, float(timings['predicted_ms']))):>13}"
    )


def main():
    started_at = time.perf_counter()
    if CONTEXT_SIZE <= 0 or NUM_PREDICT <= 0:
        raise SystemExit("CONTEXT_SIZE and NUM_PREDICT must be positive integers.")
    if not CHECKPOINTS or any(value <= 0 or value >= 100 for value in CHECKPOINTS):
        raise SystemExit("CHECKPOINTS must contain percentages between 1 and 99.")
    ensure_server_is_running()

    print(
        f"Benchmarking llama.cpp at {BASE_URL} with a "
        f"{CONTEXT_SIZE:,}-token context; output cap {NUM_PREDICT:,} tokens."
    )
    print("Running baseline request (prompt: hi):", flush=True)
    baseline = completion("hi", min(64, NUM_PREDICT))
    print(flush=True)
    results = [(0, baseline)]
    for target in CHECKPOINTS:
        target_tokens = round(CONTEXT_SIZE * target / 100)
        target_prompt_tokens = max(1, target_tokens - NUM_PREDICT)
        print(f"Preparing {target}% checkpoint...", flush=True)
        prompt = make_prompt(target_prompt_tokens)
        print(f"Generating at {target}% context:", flush=True)
        timings = completion(prompt, NUM_PREDICT)
        print(flush=True)
        actual_tokens = int(timings["prompt_n"]) + int(timings["predicted_n"])
        if abs(actual_tokens - target_tokens) > max(
            4, math.ceil(CONTEXT_SIZE * 0.005)
        ):
            print(
                f"  Warning: actual context was {actual_tokens:,} tokens; "
                f"target was {target_tokens:,}.",
                flush=True,
            )
        results.append((target, timings))

    print("\nContext benchmark (llama.cpp reported timings)")
    print(
        f"{'Target':>7}  {'Actual fill':>10}  {'Context tokens':>18}  "
        f"{'Prompt tokens':>14}  {'Prefill time':>11}  "
        f"{'Prefill tok/s':>14}  {'Generated':>10}  "
        f"{'Decode time':>10}  {'Decode tok/s':>13}"
    )
    for target, timings in results:
        print(result_row(target, timings))
    print(f"Total benchmark time: {time.perf_counter() - started_at:.2f}s")


if __name__ == "__main__":
    main()
