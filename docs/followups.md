# Follow-ups

Out-of-scope findings recorded during review. Deferred items are tracked in the
Plane project `HOME` (HomeValue).

## Task 1-2 / Phase 1 review (2026-10-23)

- **HOME-6** — Phase 1 delivery: scaffold, California/Ames loaders, verified cache,
  exploration, CI/CD. Tracked as the parent work item for this branch.
- **HOME-1** — Dependency reproducibility: `ml_backend/pyproject.toml` uses lower
  bounds only. Add a lockfile with hashes and a `pip-audit` gate. Deferred to a
  dedicated `chore/` branch after Phase 2; it is not a preprocessing defect.
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

## Task 3 / Phase 2 review (2026-10-23)

- **HOME-10** — Phase 2 delivery: preprocessing pipeline, Week 02 ratio features,
  feature-type inference, and reproducible train/test split.
- Week 02 names `rooms_per_household` and `population_per_household` are intentionally
  not emitted as new columns: the bundled California dataset stores per-household
  averages, so those names would duplicate `AveRooms` and `AveOccup`. The pipeline
  derives `rooms_per_person`, `bedrooms_per_room`, and `households` instead.
- **HOME-11** — `ml_backend/src/ml_backend/preprocessing/pipeline.py`: one-hot encoding
  every level of high-cardinality Ames categoricals can explode the feature width.
  Add `min_frequency`/`max_categories` and a deliberate sparse-output policy before the
  API phase.
- **HOME-12** — When model persistence lands (HOME-7), store the train/test split digest
  and dependency versions alongside the artifact for reproducibility.
- Booleans and datetime columns are rejected by `infer_feature_types`; support requires
  an explicit encoding decision, so it stays out of scope until a dataset needs it.
- **HOME-13** — `infer_feature_types` classifies any `object` column as categorical;
  mixed values such as `["INLAND", 1, None]` fail later inside `OneHotEncoder` without
  naming the column. Add a pandas `infer_dtype` guard before Ames CSV ingestion.
- `_to_object_with_nan` is referenced by `FunctionTransformer`; promote it to a public
  symbol before model artifacts pickle the preprocessing pipeline (HOME-7/HOME-12).

## Pytest warning cleanup (2026-10-27)

- **HOME-35** — `ml_backend/tests/conftest.py:24-25` and
  `ml_backend/tests/test_selection.py:18` call `warnings.filterwarnings` at import
  time, suppressing `invalid value encountered in divide` for the whole pytest
  process. Collapse to the scoped autouse fixture at `conftest.py:14-21`.
- **HOME-36** — `.gitignore` ignores `/coverage/` but not `.coverage`; a root-level
  `pytest --cov` run leaves an untracked artifact. Add `.coverage` and `.coverage.*`.
- Pytest config now lives only in the repo root `pytest.ini`. Adding another inifile
  under `ml_backend/` would split `rootdir` discovery again and reintroduce unknown
  marker warnings.
- **HOME-37** — `ml_backend/tests/test_integration.py::TestFullPipeline` loads the
  California housing dataset over the network but carries no `integration` marker, so
  CI always fetches and deserializes a remote artifact. Add markers plus a dedicated
  CI job once measured: total coverage is 96.67% with these tests included and stays
  96.67% when they are excluded, so the cost is runtime (roughly 75% of the suite)
  rather than uncovered lines.

## Coverage remediation review (2026-10-27)

- **HOME-39** — `lib/features/settings/presentation/bloc/settings_bloc.dart:84-92`
  invoked `_maybeStartAutoRetrain` from every settings handler, so changing theme or
  the server URL issued `POST /train` and reset the 24h timer. Also unhandled:
  `SettingsFailure` is never rendered in `settings_screen.dart:35,45`.
- **HOME-40** — `ml_backend/src/ml_backend/api/models.py:24-30` exposes a dead
  `_save_comparison` duplicate, and `tests/test_models_api.py:51-63` asserts metrics
  only behind `if data["models"]`, so the populated `/model/comparison` path
  (`models.py:18-20`) is never exercised.
- **HOME-41** — `ml_backend/src/ml_backend/api/predict.py:69-84` batch validation is
  untested: defaulted `ocean_proximity`, rejected invalid category, and the 1000
  sample cap have no cases in `tests/test_predict_api.py`.

## HOME-39 Round 14 deferred findings (2026-11-15)

- **HTTPS socket-level IP pinning** — `lib/features/settings/presentation/bloc/settings_bloc.dart`
  (`_trainUri`) and `prediction_remote_datasource.dart` / `comparison_remote_datasource.dart`
  keep the hostname for https targets instead of pinning the resolved IP, because
  `uri.replace(host: ip)` breaks TLS SNI/cert verification. Socket-level pinning
  (connect to validated IP, SNI = hostname) is the complete fix; needs a custom
  connectionFactory or platform channel. Blocked-host validation still runs on
  every resolution, so the TOCTOU window is bounded, not closed.
- **bloc `e.toString()` error leakage** — `lib/features/prediction/presentation/bloc/prediction_bloc.dart`
  and `lib/features/comparison/presentation/bloc/comparison_bloc.dart` emit
  `e.toString()` in failure states, which can surface URLs/exception internals in
  the UI. Pre-existing (not introduced by this branch). Replace with generic
  messages + log type only.
- **Design decision: default serverUrl** — `AppConstants.apiBaseUrl` /
  `AppSettings.defaults()` use `http://example.com:8000` which routes to IANA if a
  user never configures the app. Consider empty/explicit-first-config UX.
- **Design decision: localhost workflow** — developers can no longer point the app
  at a local backend (loopback is blocked by the SSRF allowlist). Consider a
  debug-only override (kReleaseMode gate) for trusted-local development.

## HOME-39 Round 15 deferred findings (2026-11-15)

- **Extract shared resolve/validate/pin helper + repo.retrain()** (QA Medium M3) —
  the DNS-resolve + per-address-allowlist + IPv4-preferred-pin sequence is
  triplicated across `settings_bloc.dart` (`_trainUri`),
  `prediction_remote_datasource.dart` (`_resolveAndValidateHost`/`_pinnedUri`) and
  `comparison_remote_datasource.dart`. Extract into `lib/core/validation.dart`
  and move the retrain POST out of the presentation layer into
  `SettingsRepository.retrain()`. Refactor branch.
- **Default serverUrl product decision** (QA Medium M6) — `http://example.com:8000`
  default routes to IANA; awaiting user decision (empty/explicit-first-config UX).
- **DNS timeout drift** (Info) — `_trainUri` uses 10s, prediction datasource uses
  its `timeout` field, comparison datasource uses `AppConstants.apiTimeout`.
  Standardize on one constant/seam.
- **Domain-layer import** (Info) — `lib/features/settings/domain/entities/app_settings.dart`
  imports `flutter/material.dart` (ThemeMode); consider moving ThemeMode out of
  the domain layer.
- **Default URL duplicated in 3 files** (Info) — `AppConstants.apiBaseUrl`,
  `AppSettings.defaults()`, `SettingsLocalDataSource._defaultServerUrl`. Single
  source of truth.
- **fake_async flushMicrotasks ritual** (Info) — ~10 doubled/tripled
  `flushMicrotasks()` calls in `bloc_test.dart`; fragile but green. Consider a
  documented helper.
- **Response body not capped** (Info) — retrain/comparison responses are read
  fully into memory; cap size if untrusted servers are ever allowed.
- **Shorthand IPv4 (`127.1`) + trailing-dot `localhost.`** (Info) — current
  allowlist treats `127.1` as a non-4-part name (DNS lookup decides), and the
  trailing-dot strip covers `localhost.`; verify platform resolvers cannot map
  these to loopback in `validateServerUrl`.

## HOME-39 Round 16 deferred findings (2026-11-16)

- Extract documented `settle(async)` helper to replace the repeated
  `flushMicrotasks` ritual in bloc tests; make the retrain response
  deadline injectable (mirror the datasource `timeout` seam).
- Product decision: zero-delay immediate retrain when saving a first
  server URL with auto-retrain enabled (may be intended first-config
  UX; confirm with product).
- Extend di_test for the new datasource wiring (baseUrlProvider
  closure) and assert `AppConstants.apiBaseUrl` value.
- Info: retrain success-POST followed by a failed
  `updateLastAutoRetrain` persist is counted as a retrain failure
  (conservative; classify or comment).

## HOME-39 Round 17 deferred findings (2026-11-16)

- **Shared resolve/validate/pin helper** (Medium, refactor) — extract the
  duplicated DNS-resolve + revalidate + IPv4-preference + IP-pinning logic
  shared by the bloc `_trainUri`, prediction and comparison datasources into
  one `core/validation.dart` helper (already tracked as Round 15 M3; still
  open).
- **`_onTimerFired` fire-and-forget retrain** (Low) — `_triggerRetrain()` is
  un-awaited in the timer callback; make the timer path await the outcome or
  document why fire-and-forget is safe (in-flight guard already prevents
  overlap).
- **Teredo /32 + more IPv6 tunnel ranges not blocked** (Low) — evaluation
  decided not to expand the blocklist now; revisit if a hostile-allowlist
  threat model is adopted.
- **Mutable global `validation.dnsLookup`** (Low) — the test seam is a
  process-wide global; consider a zone-scoped or injected resolver later.
- **Test rename + misc asserts** (Low) — row 13: rename a misleading test
  description and strengthen a couple of loose assertions; cosmetic.
- **Three overlapping CI workflow files** (Medium, user decision) —
  `.github/workflows/` holds `ci.yml` (push, all branches),
  `advanced-machine-learning-ci.yml`, and `homevalue-ci.yml`
  (workflow_dispatch only) plus `homevalue-cd.yml` (tags). Consolidation
  needs a user decision on which definition to keep; per policy only CI may
  run on feature branches and CD belongs on `master` only.

## HOME-39 Round 19 deferred findings (2026-11-17)

- **https socket-level pinning via connectionFactory** (Medium) — tracked
  since Round 14; needs a TLS test rig before the datasources/bloc can pin
  at the socket layer for https bases (currently hostname-only for https).
- **Duplicate CI workflows** (Low, user decision) — same as Round 17 row 7;
  awaiting user choice on consolidation.
- **Extract shared `resolveAndPinHost` helper** (Low) — Round 15/17 M3
  refactor; duplicated resolve/validate/pin logic in bloc + 2 datasources.
- **Mutable global `validation.dnsLookup` seam** (Low) — Round 17 row 12;
  consider zone-scoped or injected resolver.
- **Teredo /32 + IPv6 tunnel ranges** (Low) — Round 17 row 12; not expanded.
- **prediction/comparison bloc `e.toString()` leakage** (Low) — tracked
  since Round 14: bloc error paths may surface raw exception text in the
  prediction/comparison UIs (settings bloc is leak-safe already).
- **304 redirect handling** (Info) — validation `rejectRedirect` treats 304
  as a 3xx rejection; harmless but semantically a cache response.
- **3xx consumes a retrain attempt** (Info) — a redirect response reaches
  the POST path (followRedirects=false) and is rejected as failed,
  consuming the consecutive-failure budget; consider classifying as a
  policy block.
- **G6-G12 defensive tests** (Info) — QA's residual low-priority test ideas
  (defensive branches in the retrain loop) not worth the churn now.
- **DI dispose hook + `apiBaseUrl` assert** (Info) — di_test never disposes
  datasource clients (app-lifetime singletons OK) and the
  `AppConstants.apiBaseUrl` value assertion remains unimplemented (Round
  16 note carried forward).
- **Default-URL product decision** (Info) — shipped default
  `http://example.com:8000` is a placeholder; confirm the real default.
- **Coverage Lows B-G5..G9** — screen validator message verbatim, removed
  snackbar absence, updateServerUrl trim, predictBatch 500,
  validateServerUrlSync space/tab; low-value assertions deferred.
- **Bloc suspension message verbatim assert** (Low) — bloc-level suspension
  test asserts `contains('suspended')`; the verbatim string is only
  asserted at the UI level. Tighten if the message becomes contractual.
- **DI-injected comparison client never closed** (Info) — datasource
  injected via DI is an app-lifetime singleton; closing is unnecessary,
  noted for dispose-hook work above.
