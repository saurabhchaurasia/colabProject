# llama.cpp Qwen3.5 benchmark

This directory sets up and runs a separate CUDA-enabled llama.cpp benchmark for
Qwen3.5-0.8B. It does not use or change the root Ollama configuration.

## Setup

Set `PROFILE=base` or `PROFILE=dual` in `.env` to select a configuration;
`env.sh` selects the corresponding `BASE_` or `DUAL_` values from `.env`.
`base` uses the Q5_K_XL GGUF from
`unsloth/Qwen3.5-0.8B-GGUF`, requests all model layers on visible GPUs, and uses
the f16 KV cache. `dual` selects the Qwen3.8-27B Q5_K_XL dual-GPU settings
described below. Edit the prefixed values in `.env` to customize a profile;
environment variables can override the selected values.

Run setup from the repository root or this directory:

```bash
bash llama/load3.sh
```

`load3.sh` only installs missing Debian/Ubuntu build tools and downloads the
official prebuilt llama.cpp CUDA server and matching runtime libraries. It
does not read the model profile, download a model, or start a server. It does
not need `nvcc` or a local compiler. The default CUDA 12.8 build requires
NVIDIA driver 570.26 or newer. Set `CUDA_VERSION` in the environment to choose
another available release variant when running `load3.sh` directly; `sanity.sh`
passes the configured `.env` value through automatically.
When `load3.sh` is run by itself outside this project directory, it installs
the prebuilt under `~/.cache/colabProject/llama` (or `LLAMA_HOME`). `sanity.sh`
uses that same location if the prebuilt is not in the project directory.

Warm up the model with a short chat-formatted greeting before benchmarking:

```bash
bash llama/sanity.sh
```

`sanity.sh` loads the selected profile, invokes `load3.sh` to ensure llama.cpp
is installed, downloads the configured GGUF if needed, validates the GPU
configuration, and starts the server if it is not already healthy. It then
sends a chat-formatted greeting with Qwen thinking disabled and prints its
response and timing. It allows up to 128 generated tokens and does not run the
context benchmark. If a healthy managed server is already running, it reuses
it without downloading the model again. Stop the server before running sanity
to apply changed model or server settings. A different server at the selected
port is rejected rather than silently using its model or settings.

Restart the selected llama.cpp server and apply current profile settings with
the repository-level script:

```bash
bash restart-llama.sh
```

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
| `PROFILE` | `base` | Selects `base` (Qwen3.5-0.8B) or `dual` (Qwen3.8-27B dual-GPU). |
| `MODEL_REPO` | `unsloth/Qwen3.5-0.8B-GGUF` | Hugging Face repository containing the GGUF. |
| `MODEL_FILE` | `Qwen3.5-0.8B-UD-Q5_K_XL.gguf` | GGUF file to download and run. |
| `MODEL_DIR` | `models` | Model download directory, relative to this folder. |
| `SERVER_HOST` | `127.0.0.1` | Local llama.cpp server bind address. |
| `SERVER_PORT` | `8150` | Local llama.cpp server port. |
| `CONTEXT_SIZE` | `120000` | Context size requested for the server. Qwen3.5-0.8B has a native 262,144-token context, but hardware memory may limit usable size. |
| `GPU_LAYERS` | `all` | Model layers to offload; `all` requests full offload. |
| `KV_CACHE_TYPE` | `f16` | KV-cache type for both keys and values (`f16`, `q8_0`, or `q4_0`). |
| `CUDA_VERSION` | `12.8` | CUDA version variant to download from the latest official llama.cpp nightly release. |
| `CUDA_VISIBLE_DEVICES` | unset | Optional GPU IDs visible to llama.cpp, e.g. `0,1`. |

The generation cap (4,096 tokens) and context checkpoints
(10%, 25%, 50%, 75%, and 90%) are fixed in `benchmark.py`; they are
not read from `.env`.

Environment variables override `.env` values. The server must be restarted
after changing model, context, GPU, or KV-cache settings.

## `dual` profile: Qwen3.8-27B dual-GPU

Set `PROFILE=dual` in `.env` to select the Q5_K_XL model and the two-GPU
settings requested for a pair of RTX 5060 Ti cards. The same commands then use
that configuration automatically:

```bash
bash llama/load3.sh
bash llama/sanity.sh
bash llama/test.sh
```

The profile downloads `Qwen3.8-27B-UD-Q5_K_XL.gguf` from
`unsloth/Qwen3.8-27B-GGUF`, uses port 8081, 131,072 context, tensor splitting
at `50,50`, f16 KV cache, the specified sampler values, Jinja and reasoning,
and draft-MTP settings. The sample's Q6 label does not match the requested
`UD-Q5_K_XL` file, so this profile uses the Q5_K_XL quantization.

The profile requires two visible GPUs and exactly one tensor-split weight per
GPU. `sanity.sh` checks this before downloading the large model. Verify
the actual two-card VRAM capacity: 27B Q5_K_XL weights plus a 131K f16 KV cache
may exceed 2 × 16 GB, so full GPU residency is not guaranteed. The server
uses the configured values as requested and exits if the requested context
cannot be allocated (`--fit off`).
