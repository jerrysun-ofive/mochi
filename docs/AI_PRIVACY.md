# AI Privacy and Data Minimization

AI classification is off until configured. Metadata and content stay on the Mac when it is off. Deterministic organization never requires network access.

## Extraction ladder

1. Metadata: normalized filename, extension/type, size, dates, Finder tags, and candidate descriptions.
2. Bounded text: PDF title and first-page text or bounded image metadata, capped at 2,000 characters.
3. Local OCR: reserved for a later release.

The bounded extractor redacts common email, phone, and long numeric patterns locally. No complete file or security-scoped bookmark is transmitted. The UI must disclose the extraction level used.

## Provider exposure

BYOK sends data directly to TypeSafe and the configured fallback service. A file may reach both only after Jev abstains or is ambiguous. Provider failover is separately opt-in.

Mochi Pro is the disclosed processor. Its backend may call approved subprocessors, but must not retain filenames, excerpts, candidate descriptions, or model bodies in application logs.

## Caching and telemetry

BYOK decisions are cached locally using file, candidate-set, extraction, schema, provider, and exact-model-version material. Mochi Pro caches only within one account using an opaque client fingerprint. Cross-user content caching is prohibited.

Permitted aggregate telemetry includes provider/model version, route, latency, token usage, cache status, and accepted/edited/rejected state. Filenames, paths, document text, folder descriptions, and bookmarks are prohibited.
