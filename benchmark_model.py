#!/usr/bin/env python3
import json
import math
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from collections import deque


MODEL = os.environ.get("MODEL", "unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M")
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434").rstrip("/")
CONTEXT_SIZE = int(os.environ.get("CONTEXT_SIZE", "120000"))
NUM_PREDICT = min(4096, max(1, CONTEXT_SIZE // 10))
BASELINE_NUM_PREDICT = min(64, NUM_PREDICT)
CALIBRATION_NUM_PREDICT = 1
CHECKPOINTS = (25, 50, 75, 90)
MAX_CALIBRATION_ATTEMPTS = 4
REQUEST_TIMEOUT = 3600


class LiveTokenWindow:
    max_lines = 5

    def __init__(self):
        terminal_width = shutil.get_terminal_size(fallback=(80, 24)).columns
        self.width = max(1, terminal_width - 1)
        self.is_terminal = sys.stdout.isatty()
        self.lines = deque([""], maxlen=self.max_lines)
        self.started = False

    def write(self, text):
        if not text:
            return
        if not self.started:
            self.started = True
            if self.is_terminal:
                sys.stdout.write("\n" * self.max_lines)

        for character in text:
            if character == "\r":
                continue
            if character == "\n" or len(self.lines[-1]) >= self.width:
                self.lines.append("")
                if character == "\n":
                    continue
            self.lines[-1] += character

        if self.is_terminal:
            sys.stdout.write(f"\033[{self.max_lines}A")
            for line in self.lines:
                sys.stdout.write(f"\r\033[2K{line}\n")
        sys.stdout.flush()

    def finish(self):
        if not self.started:
            return
        if self.is_terminal:
            sys.stdout.write("\n")
        else:
            sys.stdout.write("\n".join(self.lines) + "\n")
        sys.stdout.flush()


def ollama_model_name(model_ref):
    if model_ref.startswith("hf.co/"):
        return model_ref
    return f"hf.co/{model_ref}"


def api_url():
    return f"http://{OLLAMA_HOST}/api/chat"


def ensure_server_is_running():
    request = urllib.request.Request(f"http://{OLLAMA_HOST}/api/tags")
    try:
        with urllib.request.urlopen(request, timeout=5):
            return
    except (urllib.error.URLError, TimeoutError) as exc:
        raise SystemExit(
            f"Cannot reach Ollama at http://{OLLAMA_HOST}. "
            "Start the Ollama server first (for example, run `ollama serve`)."
        ) from exc


def chat(model, messages, num_predict, stream=False):
    body = json.dumps(
        {
            "model": model,
            "messages": messages,
            "stream": stream,
            "think": False,
            "options": {
                "num_ctx": CONTEXT_SIZE,
                "num_predict": num_predict,
                "temperature": 0,
            },
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        api_url(),
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            if not stream:
                return json.loads(response.read().decode("utf-8"))

            chunks = []
            live_window = LiveTokenWindow()
            final_result = None
            saw_thinking = False
            for line in response:
                if not line.strip():
                    continue
                chunk = json.loads(line.decode("utf-8"))
                message = chunk.get("message", {})
                saw_thinking = saw_thinking or bool(message.get("thinking"))
                text = message.get("content", "")
                if text:
                    live_window.write(text)
                    chunks.append(text)
                if chunk.get("done"):
                    final_result = chunk

            if final_result is None:
                raise RuntimeError("Ollama stream ended without a final response.")
            live_window.finish()
            if not chunks:
                detail = (
                    "Ollama streamed no visible answer text. "
                    "The model may not support disabling its separate thinking channel."
                )
                if saw_thinking:
                    detail += " The thinking trace was not displayed."
                raise RuntimeError(detail)
            final_result.setdefault("message", {})["content"] = "".join(chunks)
            return final_result
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Ollama API returned HTTP {exc.code}: {detail}") from exc


def context_tokens(result):
    return int(result["prompt_eval_count"]) + int(result["eval_count"])


def tokens_per_second(token_count, duration_ns):
    if not token_count or not duration_ns:
        return None
    return token_count * 1_000_000_000 / duration_ns


def format_rate(rate):
    return "n/a" if rate is None else f"{rate:.2f}"


def format_duration(duration_ns):
    if not duration_ns:
        return "n/a"
    return f"{duration_ns / 1_000_000_000:.2f}s"


def result_table_header():
    return (
        f"{'Target':>7}  {'Actual fill':>10}  {'Context tokens':>18}  "
        f"{'Prompt tokens':>14}  {'Prefill time':>13}  "
        f"{'Prefill tok/s':>14}  {'Generated':>10}  "
        f"{'Decode time':>12}  {'Decode tok/s':>13}"
    )


def format_result_row(target, result, used_tokens):
    actual_percent = used_tokens / CONTEXT_SIZE * 100
    prompt_tokens = int(result["prompt_eval_count"])
    generated_tokens = int(result["eval_count"])
    prefill = tokens_per_second(
        prompt_tokens, int(result["prompt_eval_duration"])
    )
    decode = tokens_per_second(
        generated_tokens, int(result["eval_duration"])
    )
    return (
        f"{target:>6}%  {actual_percent:>9.2f}%  "
        f"{used_tokens:>8,}/{CONTEXT_SIZE:<9,}  "
        f"{prompt_tokens:>14,}  "
        f"{format_duration(result['prompt_eval_duration']):>13}  "
        f"{format_rate(prefill):>14}  {generated_tokens:>10,}  "
        f"{format_duration(result['eval_duration']):>12}  "
        f"{format_rate(decode):>13}"
    )


def run_checkpoint(model, history, target_percent, current_tokens):
    target_tokens = round(CONTEXT_SIZE * target_percent / 100)
    target_prompt_tokens = max(1, target_tokens - NUM_PREDICT)
    instruction = (
        f"Continue the benchmark. Write a neutral response of about "
        f"{NUM_PREDICT:,} tokens. Do not discuss the benchmark.\n\n"
    )
    padding_unit = "The benchmark context contains neutral filler text. "
    padding_chars = max(
        0, (target_prompt_tokens - current_tokens) * 5 - len(instruction)
    )
    best = None
    previous = None
    tolerance = max(4, math.ceil(CONTEXT_SIZE * 0.005))

    for attempt in range(1, MAX_CALIBRATION_ATTEMPTS + 1):
        print(
            f"  Measuring {target_percent}% checkpoint "
            f"(attempt {attempt}/{MAX_CALIBRATION_ATTEMPTS})...",
            flush=True,
        )
        padding = (padding_unit * (padding_chars // len(padding_unit) + 1))[
            :padding_chars
        ]
        user_message = instruction + padding
        candidate_history = history + [{"role": "user", "content": user_message}]
        result = chat(
            model,
            candidate_history,
            num_predict=CALIBRATION_NUM_PREDICT,
        )
        prompt_tokens = int(result["prompt_eval_count"])
        candidate = {
            "messages": candidate_history,
            "prompt_tokens": prompt_tokens,
        }
        if best is None or abs(prompt_tokens - target_prompt_tokens) < abs(
            best["prompt_tokens"] - target_prompt_tokens
        ):
            best = candidate

        error = target_prompt_tokens - prompt_tokens
        if abs(error) <= tolerance:
            return candidate

        if previous is None:
            chars_per_token = 5
        else:
            previous_chars, previous_tokens = previous
            token_delta = prompt_tokens - previous_tokens
            chars_per_token = (
                (padding_chars - previous_chars) / token_delta
                if token_delta
                else 5
            )
            chars_per_token = min(8, max(1, chars_per_token))
        previous = (padding_chars, prompt_tokens)
        padding_chars = max(0, padding_chars + round(error * chars_per_token))

    if abs(best["prompt_tokens"] - target_prompt_tokens) > tolerance:
        print(
            f"  Warning: calibrated prompt to {best['prompt_tokens']:,} tokens "
            f"instead of {target_prompt_tokens:,} for the {target_percent}% target.",
            flush=True,
        )
    return best


def main():
    if CONTEXT_SIZE <= 0:
        raise SystemExit("CONTEXT_SIZE must be a positive integer.")
    if not MODEL:
        raise SystemExit("MODEL must not be empty.")
    if not shutil.which("ollama"):
        raise SystemExit("The `ollama` command was not found on PATH.")

    ensure_server_is_running()
    model = ollama_model_name(MODEL)
    print(
        f"Benchmarking {MODEL} with a {CONTEXT_SIZE:,}-token context. "
        "Ensure the model and available memory support this size."
    )
    print(f"Pulling {model}...")
    subprocess.run(["ollama", "pull", model], check=True)

    print(
        f"\nRunning 0% baseline with prompt: hi "
        f"(up to {BASELINE_NUM_PREDICT} generated tokens)"
    )
    baseline_history = [{"role": "user", "content": "hi"}]
    baseline = chat(
        model,
        baseline_history,
        num_predict=BASELINE_NUM_PREDICT,
        stream=True,
    )
    history = baseline_history + [
        {"role": "assistant", "content": baseline["message"]["content"]}
    ]
    results = [(0, baseline, context_tokens(baseline))]
    print("\nBaseline result:")
    print(result_table_header())
    print(format_result_row(*results[0]))

    for checkpoint in CHECKPOINTS:
        print(f"Benchmarking {checkpoint}% context...")
        calibrated = run_checkpoint(
            model, history, checkpoint, results[-1][2]
        )
        print(
            f"Generated response at {checkpoint}% "
            f"(up to {NUM_PREDICT:,} tokens; visible output):"
        )
        result = chat(
            model,
            calibrated["messages"],
            num_predict=NUM_PREDICT,
            stream=True,
        )
        used_tokens = context_tokens(result)
        target_tokens = round(CONTEXT_SIZE * checkpoint / 100)
        tolerance = max(4, math.ceil(CONTEXT_SIZE * 0.005))
        if abs(used_tokens - target_tokens) > tolerance:
            print(
                f"  Warning: final context used {used_tokens:,} tokens "
                f"({used_tokens / CONTEXT_SIZE:.2%}); target was "
                f"{target_tokens:,} ({checkpoint}%).",
                flush=True,
            )
        history = calibrated["messages"] + [
            {"role": "assistant", "content": result["message"]["content"]}
        ]
        checkpoint_result = (checkpoint, result, used_tokens)
        results.append(checkpoint_result)
        print(f"\n{checkpoint}% checkpoint result:")
        print(result_table_header())
        print(format_result_row(*checkpoint_result))

    print("\nContext benchmark (Ollama-reported timings)")
    print(f"Model load time on baseline: {format_duration(baseline.get('load_duration'))}")
    print(result_table_header())
    for result_row in results:
        print(format_result_row(*result_row))


if __name__ == "__main__":
    main()
