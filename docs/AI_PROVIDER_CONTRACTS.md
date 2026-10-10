# AI Provider Contracts

## Decision provider

`DestinationDecisionProvider` accepts a minimal file envelope and eligible destination candidates. It returns a selected opaque ID, full probability distribution, confidence, exact provider/model metadata, latency, and usage.

The candidate list logically includes `none_of_these`. Provider adapters represent this value in their wire format and reject unsupported candidate counts rather than truncating.

## Generative provider

`GenerativeAIProvider` resolves an ambiguous destination and compiles a natural-language instruction into a disabled rule draft.

Destination results are limited to an existing candidate UUID, a proposed single folder name beneath an authorized parent UUID, a clarification question, or no recommendation.

## Error behavior

Adapters normalize credential, endpoint, capacity, response, availability, and capability failures into `AIProviderError`. Raw provider payloads and credentials must never enter logs.

## Capability discovery

Adapters declare candidate limits, batching, model pinning, structured output, cached input, and usage reporting. Orchestration branches on declared capabilities rather than provider names.

## Current adapters

- TypeSafe Jev uses `https://api.typesafe.ai/v1/systemone` directly.
- OpenAI and DeepSeek use their OpenAI-compatible chat endpoints.
- Ollama defaults to the loopback OpenAI-compatible endpoint.
- Gemini uses `generateContent` with JSON response MIME type.

Provider adapters are transport boundaries. Domain types do not expose provider SDK types.
