# llama.cpp Qwen3.5 benchmark

This directory builds and runs a separate CUDA-enabled llama.cpp benchmark for
Qwen3.5-0.8B. It does not use or change the root Ollama configuration.

## Setup

Edit `.env` to configure the model, context length, checkpoints, GPU layers,
and KV-cache type. Defaults use the Q4_K_M GGUF from
`unsloth/Qwen3.5-0.8B-GGUF`, request all model layers on visible GPUs, and use
the q8_0 KV cache.

Run setup from the repository root or this directory:

```bash
bash llama/load3.sh
```

`load3.sh` installs missing Debian/Ubuntu build tools, requires an NVIDIA CUDA
GPU and downloads the official prebuilt llama.cpp CUDA server and its matching
runtime libraries. It does not need `nvcc` or a local compiler. The default
CUDA 12.8 build requires NVIDIA driver 570.26 or newer; set `CUDA_VERSION` in
`.env` only when you need another available release variant.
The script also downloads the configured GGUF and starts the local server. It
leaves the server running and prints the benchmark command when ready. It
restarts a server previously started by this script to apply current settings;
if a different server already occupies the configured port, it stops with an
error rather than silently using that server's model or settings.

Warm up the model with a short chat-formatted greeting before benchmarking:

```bash
bash llama/sanity.sh
```

`sanity.sh` invokes `load3.sh` to make sure the server and model are present,
then sends a chat-formatted greeting with Qwen thinking disabled and prints its
response and timing. It allows up to 64 generated tokens and does not run the
context benchmark. This avoids treating a one-token raw completion as a full
answer.

Run or repeat the benchmark:

```bash
bash llama/test.sh
```

The benchmark reports baseline, context fill, prefill throughput, generated
tokens, decode throughput, and total time. It uses llama.cpp's tokenizer API to
size synthetic filler prompts, then streams generated text to the terminal as
it arrives, up to `NUM_PREDICT` tokens at each configured context checkpoint.

`--n-gpu-layers all` requests all model layers on GPU, and `--split-mode layer`
allows llama.cpp to distribute them across visible GPUs. This does not guarantee
that the model and KV cache fit in GPU memory. Check `nvidia-smi` while a
request is running and see `llama-server.log` for the actual backend/offload
report. `--fit off` prevents llama.cpp from silently reducing the configured
context size to fit available memory; if the requested setup does not fit, the
server should fail rather than benchmark a smaller context. CPU use for the
server, sampling, and operating system is still expected.

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `MODEL_REPO` | `unsloth/Qwen3.5-0.8B-GGUF` | Hugging Face repository containing the GGUF. |
| `MODEL_FILE` | `Qwen3.5-0.8B-Q4_K_M.gguf` | GGUF file to download and run. |
| `MODEL_DIR` | `models` | Model download directory, relative to this folder. |
| `SERVER_HOST` | `127.0.0.1` | Local llama.cpp server bind address. |
| `SERVER_PORT` | `8080` | Local llama.cpp server port. |
| `CONTEXT_SIZE` | `120000` | Context size requested for the server. Qwen3.5-0.8B has a native 262,144-token context, but hardware memory may limit usable size. |
| `GPU_LAYERS` | `all` | Model layers to offload; `all` requests full offload. |
| `KV_CACHE_TYPE` | `q8_0` | KV-cache type for both keys and values (`f16`, `q8_0`, or `q4_0`). |
| `CUDA_VERSION` | `12.8` | CUDA version variant to download from the latest official llama.cpp nightly release. |
| `CUDA_VISIBLE_DEVICES` | unset | Optional GPU IDs visible to llama.cpp, e.g. `0,1`. |

The generation cap (4,096 tokens) and context checkpoints
(20%, 40%, 50%, 60%, 70%, 80%, and 90%) are fixed in `benchmark.py`; they are
not read from `.env`.

Environment variables override `.env` values. The server must be restarted
after changing model, context, GPU, or KV-cache settings.
