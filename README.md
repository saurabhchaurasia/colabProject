# Ollama model loader

These scripts install/start Ollama and pull/check a model. The optional
`cloudflare.sh` script exposes the Ollama API through a Cloudflare quick tunnel.

## Environment variables

| Variable | Used by | Default | Description |
| --- | --- | --- | --- |
| `MODEL` | `ollama_run_linux.sh`, `benchmark_model.py`, `load2.sh` | `unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M` | Hugging Face model repository and GGUF variant to pull. The scripts add the `hf.co/` prefix when calling Ollama. |
| `OLLAMA_HOST` | `load.sh`, `cloudflare.sh`, `benchmark_model.py`, `load2.sh` | `127.0.0.1:11434` | Ollama server host and port. Use the `host:port` form without `http://`; it is used to check the API and, when started, to configure the Cloudflare tunnel. |
| `CONTEXT_SIZE` | `benchmark_model.py`, `load2.sh` | `120000` | Context window size, in tokens, passed to Ollama for the benchmark. The 25%, 50%, 75%, and 90% checkpoints are calculated against this value. Confirm the selected model and available memory support this context size. |

Set a variable for one command:

```bash
MODEL="unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M" bash ollama_run_linux.sh
OLLAMA_HOST="127.0.0.1:11434" bash cloudflare.sh
```

## Context benchmark

With Ollama running, execute the benchmark script to pull the selected model,
send a short `hi` baseline, and continue the chat through the 25%, 50%, 75%,
and 90% context checkpoints. With the default 120,000-token context, those
checkpoints are 30,000, 60,000, 90,000, and 108,000 tokens. The final table
reports actual context fill, prompt tokens, prefill time and tokens per second,
generated tokens, and decode time and tokens per second. Checkpoint replies are
streamed to an interactive terminal in a rolling five-line window and capped at
4,096 tokens by default; the model may generate fewer. When output is redirected
or non-interactive, only the final five lines are printed after generation. The
script requests visible answer text rather than a separate reasoning trace. It
prints the baseline and each checkpoint's metrics immediately, then prints a
final table with all results. Calibration requests use a one-token output cap
to avoid repeatedly generating long responses while adjusting context size.

```bash
python3 benchmark_model.py
```

Set `CONTEXT_SIZE` to benchmark a different context window, for example:

```bash
CONTEXT_SIZE=120000 MODEL="unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M" \
  python3 benchmark_model.py
```

## Automatic setup and benchmark

On Debian/Ubuntu Linux, `load2.sh` installs missing `curl`, `python3`, and
`zstd` packages, installs Ollama if needed, starts or reuses its server, and
then runs the context benchmark. Package installation requires root or `sudo`.

```bash
bash load2.sh
```

You can set benchmark variables when starting it:

```bash
MODEL="unsloth/Qwen3.5-0.8B-MTP-GGUF:Q4_K_M" CONTEXT_SIZE=120000 bash load2.sh
```

To use a custom endpoint for scripts launched from `load.sh`, export it first:

```bash
export OLLAMA_HOST="127.0.0.1:11434"
bash load.sh
```

The Cloudflare tunnel launch in `load.sh` is currently commented out. To start
the tunnel separately, run `bash cloudflare.sh`.
