# vllm_run_linux.sh

This README describes how to do the same kind of local model serving workflow with vLLM instead of Ollama.

## What the vLLM version should do

A vLLM-based setup usually follows the same high-level flow as the Ollama script:

1. Install the required system and Python dependencies.
2. Start a vLLM OpenAI-compatible server.
3. Load the model you want to serve.
4. Wait for the server to become healthy.
5. Send a quick test request to confirm the model responds.
6. Expose the server through a tunnel if you need remote access.

## Requirements

- Linux
- Python 3.10 or newer
- `pip` or another Python package manager
- A CUDA-capable GPU for practical performance
- Enough VRAM for the model you want to serve
- Internet access for downloading packages and model weights

## Typical setup

Install vLLM in a Python environment:

```bash
pip install vllm
```

Start the server with an OpenAI-compatible API:

```bash
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-7B-Instruct \
  --host 127.0.0.1 \
  --port 8000
```

## Example test request

Once the server is running, you can test it with a chat-completions request:

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-7B-Instruct",
    "messages": [
      {"role": "user", "content": "Say hi"}
    ]
  }'
```

## Optional tunnel

If you want to expose the server externally, you can use a tunnel tool such as `cloudflared`:

```bash
cloudflared tunnel --url http://127.0.0.1:8000
```

## Notes

- vLLM is not a drop-in replacement for the Ollama CLI; it is typically run as a Python server.
- Model names are usually Hugging Face model IDs rather than Ollama tags.
- The exact command line can vary depending on your vLLM version and the model you choose.
- If you want, I can also create a matching `run_vllm_linux.sh` script for this workspace.