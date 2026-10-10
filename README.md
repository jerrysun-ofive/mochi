# Mochi

> A little helper for your messy files.

Mochi is a native, local-first macOS file organizer. Deterministic rules run locally; optional AI can suggest destinations but cannot perform filesystem operations directly.

## Current implementation

- macOS 13 SwiftUI menu-bar and dashboard shell
- versioned deterministic rule domain and evaluator
- safe destination and rename validation
- FSEvents folder monitor and incomplete-download readiness probe
- security-scoped folder grants
- one-click Quick Rules for PDFs, images, screenshots, archives, installers, and documents
- durable operation journal, collision handling, crash recovery, and safe undo
- provider-neutral hybrid AI orchestration
- direct TypeSafe Jev decision adapter
- OpenAI-compatible adapters for OpenAI, DeepSeek, and Ollama
- Gemini adapter
- Mochi Pro provider-neutral gateway adapter
- local content minimization/redaction and decision cache
- BYOK settings for TypeSafe Jev plus OpenAI, Gemini, DeepSeek, or local Ollama, with secrets stored in macOS Keychain
- reproducible benchmark runner and tests

The application is under active development and is not ready to organize irreplaceable files.

## Build and test

```bash
swift build
swift test
swift run MochiApp
```

The benchmark command accepts a JSON array of `BenchmarkCase` values and an optional mock-decision map keyed by each case's `candidateSetHash`:

```bash
swift run mochi-benchmark dataset.json report.json decisions.json
```

Reports include a dataset fingerprint, top-1 and abstention metrics, calibration scores, p50/p95/p99 latency, transmitted bytes, attempts, token classes, and actual billed cost reported by an adapter.

## Quick start

Authorize a watched folder and a destination, then open **Quick Rules** to add common organizers in one click. Quick Rules create enabled deterministic rules and use destination subfolders such as `PDFs` or `Images`; matching files still enter Review before anything moves.

BYOK credentials are configured under **Settings → AI & Privacy**. TypeSafe Jev is required for closed-set classification, together with OpenAI, Gemini, DeepSeek, or Ollama for generative fallback. Hosted AI classification remains review-only until the exact model version passes Mochi's benchmark safety gate.

## Architecture

See [the AI architecture](docs/AI_ARCHITECTURE.md), [benchmark plan](docs/AI_BENCHMARK_PLAN.md), [distribution contract](docs/DISTRIBUTION.md), and the architecture decision records under `docs/adr`.

## Safety

Mochi never silently overwrites a file. AI responses are treated as untrusted suggestions and pass through local validation, preview, journaling, and execution boundaries.

## License

Apache License 2.0.
