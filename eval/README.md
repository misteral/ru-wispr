# Local LLM evaluation

This directory contains lightweight assets for comparing MLX local LLMs as the final text cleanup layer for dictation.

## Structure

- `models/local-llm-candidates.json` — candidate MLX models found via internet search (Hugging Face API / model pages)
- `datasets/text-postprocessing-v1.jsonl` — small hand-written evaluation dataset for RU/EN dictation cleanup
- `results/` — generated evaluation reports
- `tool/main.swift` — `dikto-eval` executable target entry point

## Run

```bash
swift build -c release
.build/release/dikto-eval
```

Single model:

```bash
.build/release/dikto-eval --filter Qwen2.5-1.5B
```

List assets:

```bash
.build/release/dikto-eval --list-models
.build/release/dikto-eval --list-dataset
```
