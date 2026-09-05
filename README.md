<p align="center">
  <img src="Resources/Brand/logo.svg" alt="HAL" width="120" height="120">
</p>

<h1 align="center">HAL</h1>

<p align="center">
  Simplified Chinese Pinyin input method for macOS.<br>
  Built with InputMethodKit, librime, and rime-ice.
</p>

## Features

- **Candidate window at the caret**, fully customisable input window.
- **Caps Lock switches Chinese and English** inside HAL, without handing the
  keyboard back to another input source.
- **`EN+`** (Shift + Caps Lock) completes English words from the system
  dictionary as you type; **`EN`** is a plain passthrough.
- **Fuzzy Pinyin rules you write yourself** — custom map fuzzy Pinyin or any input to any syllable,

## Requirements

macOS 26+, Apple Silicon.

## Install

Download the DMG from [Releases](https://github.com/YaphetSf/HAL/releases). Open `HAL.app`,
then add HAL in System Settings → Keyboard → Text Input → Edit.

Control centre: `~/Applications/HAL.app`. Rime overrides: `~/Library/Application Support/HAL/Rime`.

## AI Editing

HAL can proofread or rephrase selected text through either Apple Intelligence or a model server you control.
A server on the same Mac and a remote server use the same OpenAI-compatible Chat Completions
provider. HAL does not bundle, download, or manage third-party models.
The complete Rephrase prompt is editable in HAL → AI Editing and is shared by both providers.

### Recommended starting point

If you want a known baseline, start with
[`mlx-community/Qwen3.5-9B-MLX-4bit`](https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit).
It scored **42/54 (77.8%)** in HAL's v7 suite across English, Chinese, and mixed-language
Proofread and Rephrase. The checkpoint is about 6 GB and uses approximately 5.8 GB of memory
while running.

Run the downloaded model with MLX-LM outside HAL:

```bash
mlx_lm.server \
  --model /path/to/Qwen3.5-9B-MLX-4bit \
  --host 127.0.0.1 \
  --port 8901 \
  --chat-template-args '{"enable_thinking":false}'
```

Then open HAL → AI Editing, choose **OpenAI-compatible server**, and enter:

```text
Chat completions URL: http://server-address:port/v1/chat/completions
```

Use `127.0.0.1` when the server runs on the same Mac. For a server on another machine, use its
reachable LAN or Tailscale address and make sure the server listens on that network interface.

Qwen is a measured recommendation, not a requirement. Any server and model implementing the same
Chat Completions interface can be used.

## Build from source

```bash
brew install xcodegen
scripts/build-install.sh
scripts/package-release.sh
xcodebuild test
```

## Evaluate AI Editing

Run the same Proofread and Rephrase capability suite against either Apple Intelligence
or an OpenAI-compatible endpoint:

```bash
# macOS Foundation Models
scripts/eval-local-rewrite.sh

# Model server
Evals/src/endpoint_eval.py \
  --endpoint http://127.0.0.1:8901/v1/chat/completions \
  --label my-model \
  --cases Evals/src/cases.json \
  --prompts Evals/src/prompts.json \
  --report Evals/results/my-model.json
```

The capability eval is intentionally separate from unit tests because model output and
performance depend on the installed runtime and checkpoint. See
[`Evals/README.md`](Evals/README.md) for repeated runs, individual
cases, and strict gating.

## Licence

HAL: [MIT](LICENSE). librime: BSD-3-Clause. rime-ice: GPL-3.0. Versions:
[Rime/VERSIONS.md](Rime/VERSIONS.md).
