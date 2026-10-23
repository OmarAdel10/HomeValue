# Follow-ups

Out-of-scope findings recorded during review. Each entry has a file reference and
is tracked as a Plane work item.

## Task 1-2 review (2026-10-23)

- `ml_backend/src/ml_backend/data/loader.py` — Dataset integrity is verified with a
  local SHA-256 sidecar, but the upstream OpenML record is not checksum-pinned.
  Deferred: transport is HTTPS and the OpenML dataset/version is pinned; add a
  checksum pin only if dataset provenance becomes a requirement.
- `ml_backend/src/ml_backend/data/loader.py` — Model artifact deserialization
  (`joblib`/`pickle`) is not implemented yet. When model persistence lands, prefer a
  non-executable format or verify a trusted hash before loading.
- `ml_backend/src/ml_backend/data/explore.py` — Exploration helpers do not redact
  PII. Deferred: the bundled California/Ames datasets are public and contain no PII.
- `ml_backend/src/ml_backend/data/explore.py` — Plot names are sanitized, but error
  messages still surface internal paths. Deferred: intentional for local debugging.
- `ml_backend/src/ml_backend/data/loader.py` — Cache helpers are module functions.
  Revisit a `CacheManager` class only if cache operations grow.
- `ml_backend/src/ml_backend/config.py` — Hyperparameter grids are hardcoded.
  Revisit external YAML/JSON config if the grids need tuning without code changes.
