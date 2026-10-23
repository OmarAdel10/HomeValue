# Follow-ups

Out-of-scope findings recorded during review. Deferred items are tracked in the
Plane project `HOME` (HomeValue).

## Task 1-2 / Phase 1 review (2026-10-23)

- **HOME-6** — Phase 1 delivery: scaffold, California/Ames loaders, verified cache,
  exploration, CI/CD. Tracked as the parent work item for this branch.
- **HOME-1** — Dependency reproducibility: `ml_backend/pyproject.toml` uses lower
  bounds only. Add a lockfile with hashes and a `pip-audit` gate. Deferred while the
  phase surface is still small; revisit before Phase 2.
- **HOME-2** — `ml_backend/src/ml_backend/data/loader.py`: cache writes are atomic but
  reopen by path, and verification/read are separate opens. Harden with fd-based
  writes and `O_NOFOLLOW` before model persistence lands.
- **HOME-3** — `ml_backend/src/ml_backend/data/explore.py`: calling
  `matplotlib.use("Agg")` mutates the global backend. Move to `Figure`/`FigureCanvasAgg`
  when plotting becomes part of the API.
- **HOME-4** — `linux/flutter/generated_plugins.cmake`: the `jni` plugin adds a host
  JDK dependency to the Linux bundle. Pin `path_provider`/`shared_preferences` or
  document the requirement in the Flutter phase.
- **HOME-5** — `RUN_INTEGRATION=1` tests are skipped in CI. Add a scheduled job that
  exercises the real California/Ames fetches.
- **HOME-7** — Model persistence will introduce `joblib`/`pickle` deserialization.
  Use a non-executable format or verify a trusted hash before loading.
- **HOME-8** — Upstream dataset digest pinning. Deferred: transport is HTTPS, the
  OpenML dataset version is pinned, and sklearn verifies its cached archives.
- Exploration helpers do not redact PII. Not applicable today: the bundled
  California/Ames datasets are public and contain no personal data.
- Cache helpers are module-level functions; extract a cache manager only if the
  operations grow.
- Hyperparameter grids are hardcoded in `Config`; externalize them only if tuning
  needs to change without code edits.
