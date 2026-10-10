# ADR 0005: AI Provider Boundary

Status: accepted

AI providers return domain suggestions only. They cannot access bookmarks, absolute paths, the operation journal, or the executor. Decision and generation are separate protocols because closed-set routing and open-ended rule/folder generation have different safety and benchmarking properties.
