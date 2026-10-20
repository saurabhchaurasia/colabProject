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
```

| Variable | Used by | Default | Description |
| --- | --- | --- | --- |
| `MODEL` | `ollama_run_linux.sh`, `benchmark_model.py`, `sanity.sh`, `test.sh` | `unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M` | Hugging Face model repository and GGUF variant to pull. The scripts add the `hf.co/` prefix when calling Ollama. |
| `OLLAMA_HOST` | `load.sh`, `cloudflare.sh`, `benchmark_model.py`, `load2.sh`, `sanity.sh`, `test.sh` | `127.0.0.1:11434` | Ollama server host and port. Use the `host:port` form without `http://`; it is used to check the API and, when started, to configure the Cloudflare tunnel. |
| `CONTEXT_SIZE` | `benchmark_model.py`, `sanity.sh`, `test.sh` | `120000` | Context window size, in tokens, passed to Ollama for the benchmark and initial model request. The 20%, 40%, 50%, 60%, 70%, 80%, and 90% checkpoints are calculated against this value. Confirm the selected model and available memory support this context size. |
| `NUM_GPU_LAYERS` | `benchmark_model.py`, `sanity.sh`, `test.sh` | `999` | Maximum number of model layers requested for GPU offload. Ollama can distribute layers across visible GPUs; confirm `ollama ps` reports `100% GPU` after loading. A high request cannot make an oversized model or context fit in VRAM. |

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
