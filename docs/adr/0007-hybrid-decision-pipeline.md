# ADR 0007: Hybrid Decision Pipeline

Status: provisional, benchmark gated

Run deterministic rules first, Jev second, and a small generative model only for abstention or ambiguity. This minimizes likely inference work while retaining a generation path. The route remains provisional until it beats or matches direct small-model classification on Mochi's frozen holdout.

BYOK requires both TypeSafe Jev and one supported generative configuration. New folders and generative fallbacks remain review-only in v1.
