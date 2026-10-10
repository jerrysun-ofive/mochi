# Contributing

Build with the current stable Xcode and run `swift test` before opening a pull request. New filesystem behavior requires temporary-directory tests. New AI providers must implement the provider-neutral contracts, document their data handling, and pass the benchmark harness before becoming production defaults.

Never add real user documents, API keys, bookmarks, signing material, or provider responses to fixtures or logs.
