# AI Benchmark Plan

## Decision to make

Determine whether Jev-first cascading is safer or more efficient than direct small-model classification for Mochi. Vendor claims are inputs, not conclusions.

## Systems

1. Deterministic rules only.
2. Jev closed-set decision.
3. Each small generative model used directly with a constrained choice schema.
4. Jev followed by each small-model fallback.
5. Direct small model with abstention.
6. Optional local lexical or embedding baseline.

## Dataset

Use at least 1,000 labeled decisions across 50 folder taxonomies. Include candidate sets of 3, 5, 10, 20, and 50; at least 25% `none_of_these`; ambiguous items; metadata-only and bounded-text variants; multilingual names; weak filenames; and adversarial content.

Split by taxonomy: 60% development, 20% calibration, and 20% frozen holdout. Two reviewers label ambiguous holdout cases. Disagreement becomes review-required ground truth.

## Measurements

- Top-1 accuracy and wrong-destination rate.
- `none_of_these` precision, recall, and F1.
- Review rate and automation coverage at target precision.
- Brier score, expected calibration error, and top-two margin.
- Cold/warm p50, p95, and p99 latency.
- Retry, timeout, fallback, and cache rates.
- Actual input/output/cached tokens and billed credits.
- End-to-end cascade cost per 1,000 files and per correct automatic decision.
- Bytes transmitted and percentage resolved using metadata only.

## Safety gate

An automatic route requires a 95% confidence-interval lower bound of 99% precision, at least 95% `none_of_these` recall, zero schema/authorization violations, stable validation-set calibration, and decision-stage p95 below 1.5 seconds.

Use Jev-first by default only if accuracy is non-inferior to the best direct small model by no more than 0.5 percentage points, measured cost or p95 latency improves by at least 20%, fallback stays below 40%, and privacy exposure is no worse.

## Pricing evidence

For every run, store exact model/version, official pricing URL, retrieval time, currency, all applicable price classes, returned usage, and actual billed value where available. Pricing changes recompute reports but do not silently switch production models.

## Reproducibility

`mochi-benchmark` reads versioned `BenchmarkCase` JSON and emits a JSON `BenchmarkReport`. Production-provider runners use the same dataset and record prompt/schema hashes. Thresholds are frozen before the final holdout run.
