# ollama_run_linux.sh

This script bootstraps a local Ollama server on Linux, pulls a model, runs a quick sanity check, and optionally exposes the server through a Cloudflare tunnel.

## What it does

1. Ensures `zstd` is installed.
2. Installs Ollama if it is not already available.
3. Downloads a local `cloudflared` binary into the same folder as the script.
4. Sets Ollama runtime environment variables.
5. Stops any existing `ollama serve` process.
6. Starts `ollama serve` in the background.
7. Waits for the Ollama API to become available.
8. Pulls the configured model.
9. Runs a short test prompt against the model.
10. Starts a Cloudflare tunnel if `cloudflared` is installed on the system.
11. Prints the current Ollama process list.

## Requirements

- Linux
- `bash`
- `curl`
- `sudo` access for package installation
- Internet access for downloading Ollama, the model, and `cloudflared`

## Usage

Run the script from the project directory:

```bash
bash ollama_run_linux.sh
```

## Configuration

You can override these environment variables when running the script:

- `MODEL`: Ollama model to pull and test. Default: `qwen3.5:9b`
- `CONTEXT_SIZE`: Ollama context length. Default: `32000`
- `OLLAMA_HOST`: Ollama host and port. Default: `127.0.0.1:11434`

Example:

```bash
MODEL=llama3.1:8b CONTEXT_SIZE=8192 bash ollama_run_linux.sh
```

## Side effects

- Installs packages on the machine if they are missing.
- Downloads `cloudflared-linux-amd64` into the script directory.
- Writes Ollama logs to `/tmp/ollama-serve.log`.
- Writes Cloudflare tunnel logs to `/tmp/cloudflared.log`.
- Terminates any existing process matching `ollama serve` before starting a new one.
- Terminates any existing `cloudflared` process before starting a new tunnel.

## Notes

- The Cloudflare tunnel step only runs if `cloudflared` is already available on the system `PATH`.
- The script expects a Linux environment and will not work as-is on Windows without a compatible shell and Linux tooling.
