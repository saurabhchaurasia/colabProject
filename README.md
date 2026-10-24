# Ollama model loader

These scripts install/start Ollama and pull/check a model. The optional
`cloudflare.sh` script exposes the Ollama API through a Cloudflare quick tunnel.

## Environment variables

The shell scripts and benchmark load the repository's `.env` file
automatically. Edit it to set shared defaults; variables already set in the
environment take precedence. The file uses `KEY=value` lines:

```dotenv
MODEL=unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M
OLLAMA_HOST=127.0.0.1:11434
CONTEXT_SIZE=120000
NUM_GPU_LAYERS=999
OLLAMA_KV_CACHE_TYPE=q8_0
```

| Variable | Used by | Default | Description |
| --- | --- | --- | --- |
| `MODEL` | `ollama_run_linux.sh`, `benchmark_model.py`, `sanity.sh`, `test.sh` | `unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M` | Hugging Face model repository and GGUF variant to pull. The scripts add the `hf.co/` prefix when calling Ollama. |
| `OLLAMA_HOST` | `load.sh`, `cloudflare.sh`, `benchmark_model.py`, `load2.sh`, `sanity.sh`, `test.sh` | `127.0.0.1:11434` | Ollama server host and port. Use the `host:port` form without `http://`; it is used to check the API and, when started, to configure the Cloudflare tunnel. |
| `CONTEXT_SIZE` | `benchmark_model.py`, `sanity.sh`, `test.sh` | `120000` | Context window size, in tokens, passed to Ollama for the benchmark and initial model request. The 20%, 40%, 50%, 60%, 70%, 80%, and 90% checkpoints are calculated against this value. Confirm the selected model and available memory support this context size. |
| `NUM_GPU_LAYERS` | `benchmark_model.py`, `sanity.sh`, `test.sh` | `999` | Maximum number of model layers requested for GPU offload. Ollama can distribute layers across visible GPUs; confirm `ollama ps` reports `100% GPU` after loading. A high request cannot make an oversized model or context fit in VRAM. |
| `OLLAMA_KV_CACHE_TYPE` | Ollama server (`load.sh`, `load2.sh`) | `q8_0` | KV-cache precision used by Ollama. `q8_0` is 8-bit integer quantization, not FP8; it can reduce KV-cache memory use. The Ollama server must be started with this variable, so restart an already-running server after changing it. |

Set a variable for one command:

```bash
MODEL="unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M" bash ollama_run_linux.sh
OLLAMA_HOST="127.0.0.1:11434" bash cloudflare.sh
```

## Load the model before benchmarking

To pull the selected model and send a short initial request before starting the
benchmark, run:

```bash
bash sanity.sh
bash test.sh
```

`sanity.sh` uses the same `MODEL`, `OLLAMA_HOST`, and `CONTEXT_SIZE`
settings as the benchmark, limits its initial response to one token, and prints
`ollama ps` after the request completes. This separates the first model load
from benchmark measurements.

The `OLLAMA_KV_CACHE_TYPE` setting is read by the Ollama server, not by an
individual chat request. `load2.sh` passes it when starting Ollama if no server
is already running. If Ollama was already running when you changed `.env`,
restart that server with the setting applied before benchmarking. Ollama
supports `f16`, `q8_0`, and `q4_0` KV-cache types; `q8_0` is not FP8.

Restart the local Ollama server with the configured KV-cache type by running:

```bash
./restart-ollama.sh
```

The script reads `OLLAMA_KV_CACHE_TYPE` from `.env` (or the current environment),
stops a standalone `ollama serve` process if one is running, then calls
`load.sh` to start Ollama with the setting. `load.sh` applies a runtime override
and restarts Ollama when it is managed by systemd. It requires `sudo` when
restarting a systemd-managed service.

## Context benchmark

With Ollama running, execute the benchmark script to pull the selected model,
send a short `hi` baseline, and continue the chat through the 20%, 40%, 50%,
60%, 70%, 80%, and 90% context checkpoints. With the default 120,000-token
context, those checkpoints are 24,000, 48,000, 60,000, 72,000, 84,000, 96,000,
and 108,000 tokens. The final table reports actual context fill, prompt tokens,
prefill time and tokens per second,
generated tokens, and decode time and tokens per second. Checkpoint replies are
streamed to the terminal as they arrive and capped at 4,096 tokens by default;
the model may generate fewer. The script requests visible answer text rather
than a separate reasoning trace. It prints the baseline and each checkpoint's
metrics immediately, then prints a final table with all results. Calibration
requests use a one-token output cap to avoid repeatedly generating long
responses while adjusting context size. The final summary also prints total
elapsed benchmark time, including the model pull.

```bash
python3 benchmark_model.py
```

Set `CONTEXT_SIZE` to benchmark a different context window, for example:

```bash
CONTEXT_SIZE=120000 MODEL="unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M" \
  python3 benchmark_model.py
```

## Setup and run the benchmark

On Debian/Ubuntu Linux, `load2.sh` installs missing `curl`, `python3`, and
`zstd` packages, installs `git` if a clone is needed, installs Ollama if needed,
starts or reuses its server, and prepares the project without running the
benchmark. If the benchmark script is not beside `load2.sh`, it clones this
repository into `/workspace/colabProject`. Package installation requires root
or `sudo`.

```bash
bash load2.sh
```

When setup finishes, run the benchmark yourself:

```bash
bash /workspace/colabProject/test.sh
```

Pass benchmark settings to `test.sh`:

```bash
MODEL="unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M" CONTEXT_SIZE=120000 bash test.sh
```

To use a custom endpoint for scripts launched from `load.sh`, export it first:

```bash
export OLLAMA_HOST="127.0.0.1:11434"
bash load.sh
```

The Cloudflare tunnel launch in `load.sh` is currently commented out. To start
the tunnel separately, run `bash cloudflare.sh`.

## llama.cpp Qwen3.5 benchmark

For a separate llama.cpp-based Qwen3.5-0.8B benchmark, configure
[`llama/.env`](./llama/.env), then run:

```bash
bash llama/load3.sh
bash llama/sanity.sh
bash llama/test.sh
```

This path sets up llama.cpp with CUDA; `sanity.sh` loads the base Q5_K_XL GGUF
by default. See
[`llama/README.md`](./llama/README.md) for prerequisites, GPU offload behavior,
and configuration options. Its `llama/.env` file selects the `base` or `dual`
configuration and does not change the Ollama benchmark settings.

To select the Qwen3.8-27B dual-RTX-5060-Ti configuration, change
`PROFILE=base` to `PROFILE=dual` in `llama/.env`, then run:

```bash
bash llama/load3.sh
bash llama/test.sh
```

See [`llama/README.md`](./llama/README.md) for its model quantization and
hardware requirements.
