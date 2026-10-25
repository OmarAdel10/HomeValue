# QA Post-Implementation Report

**Feature:** Model Selection, Joblib Serialization, and FastAPI Training Endpoint (Phase 6 Task 8)
**Branch:** feature/model-selection-serialization-api ← origin/master (141cce4)
**Head:** 0558afd
**Date:** 2026-10-25
**Status:** ❌ BLOCKED
**Risk Level:** Critical
**Phase:** Review (awaiting approval)
**Scope invoked:** full (code-review + security + spec-compliance + test-coverage)

---

## 0. Project Context

- **Project root:** /mnt/ALL/UniProjects/advanced-machine-learning
- **Repo:** https://github.com/OmarAdel10/HomeValue.git
- **Branch:** feature/model-selection-serialization-api ← origin/master
- **Stack:** Python 3.11+ / FastAPI / scikit-learn / pytest (test runner), ruff/mypy/black (linter/typecheck/format)
- **Monorepo:** no (single Python package `ml_backend` + Flutter app in root)
- **Intent docs found:** none (no SPEC.md, DESIGN.md, ARCHITECTURE.md, PRD.md, REQUIREMENTS.md in project root or .claude/specs/)
- **CI:** GitHub Actions (`.github/workflows/homevalue-ci.yml`, `.github/workflows/homevalue-cd.yml`) — runs on all branches + PRs to development/master
- **Change set:** M=4 A=27 R=0 D=0 ??=5 (total 36 files)
- **Sensitive surface area:** model serialization (joblib/pickle), FastAPI network endpoint (/train), config-driven hyperparameters, base_estimators injection, no auth/crypto/PII/payments
- **Security role selected:** security-architect (ML pipeline with serialization + network endpoint)

---

## 1. Executive Summary

This branch implements Phase 6 Task 8: model selection (lowest RMSE), joblib serialization (save_model/load_model), FastAPI training endpoint (POST /train) that runs the full pipeline (baselines → regularized → ensembles → tuning → select → save), and server with /health and /model_info endpoints.

**Critical Blocker:** The `run_full_training_pipeline()` function in `ml_backend/src/ml_backend/api/train.py:27-106` contains a **KeyError bug** — it attempts to access `baselines["RandomForestRegressor"]` but RandomForestRegressor is trained in the `ensembles` module, not `baselines`. Additionally, the `base_estimators` dict passes **fitted** models to `train_ensembles()`, but `StackingRegressor` requires **unfitted** estimators (sklearn clones/fits internally via CV). The full pipeline **will fail at runtime**.

**Security:** Inherits Critical/High findings from prior STRIDE analysis (STRIDE-001: arbitrary estimator injection → RCE via pickle; STRIDE-002/003/004: unbounded resources, input validation gaps, config upper bounds). These remain unaddressed in this branch.

**Test Coverage:** 96.15% overall (gate: 95%), but `train.py` only 72% and `server.py` only 55% — the core new functionality is undertested. No end-to-end test of `run_full_training_pipeline()`.

**Verdict:** ❌ BLOCKED — Critical runtime bug + security debt + undertested core logic. Do not merge until fixes applied and verified.

---

## 2. Verification

- **Acceptance criteria:** **Not Met** — Full training pipeline fails with KeyError; base_estimators architectural flaw.
- **End-to-end behavior:** **Fails** — `python -m ml_backend.api.train` raises `KeyError: 'RandomForestRegressor'` at `train.py:76`.
- **Tests:** 220 passed, 1 skipped, 7 warnings (coverage 96.15%)
- **Evidence:**
  ```bash
  $ cd ml_backend && python -c "from ml_backend.api.train import run_full_training_pipeline; run_full_training_pipeline()"
  KeyError: 'RandomForestRegressor'  # at train.py:76
  ```
- **Open issues:**
  1. `train.py:76` — KeyError accessing non-existent baselines["RandomForestRegressor"]
  2. `train.py:74-79` — base_estimators uses fitted pipelines; StackingRegressor requires unfitted
  3. No integration test for `run_full_training_pipeline()`
  4. `server.py` and `train.py` coverage below project average (55% / 72%)

---

## 3. Code Quality (Code Reviewer)

| Severity | File:Line | Finding | Suggested Fix |
|----------|-----------|---------|---------------|
| **Critical** | train.py:76 | `KeyError: 'RandomForestRegressor'` — baselines dict only has LinearRegression, DecisionTreeRegressor | Move RandomForestRegressor to baselines, OR fetch from ensembles after training, OR create fresh unfitted RF for base_estimators |
| **Critical** | train.py:74-79 | `base_estimators` passes **fitted** pipelines; `StackingRegressor` requires **unfitted** estimators (sklearn clones internally) | Create fresh unfitted estimators from config for base_estimators; do not extract from fitted pipelines |
| **High** | train.py:27-106 | No test coverage for `run_full_training_pipeline()` — core orchestration logic untested | Add integration test in `tests/test_train_api.py` or new `test_integration.py` that runs real pipeline (can use small dataset / reduced folds) |
| **High** | train.py:109-121 | `/train` endpoint catches all exceptions as 500; no structured error response | Define error response schema; log exception with traceback server-side; return generic message to client |
| **Medium** | server.py:13-26 | Global `_model` variable loaded at startup; no reload mechanism; race condition if file changes | Add `/reload` endpoint or file watcher; consider dependency injection pattern |
| **Medium** | server.py:52-59 | `/model_info` returns step names but no model metadata (hash, trained_at, config_hash) | Return model hash, training timestamp, config fingerprint for auditability |
| **Medium** | config.py:87-90 | API config (host, port, workers) hardcoded; no env var override for production | Add env var support: `API_HOST`, `API_PORT`, `API_WORKERS` |
| **Low** | train.py:45 | `Config()` instantiated without args; ignores env var `HOMEVALUE_ROOT` override pattern used elsewhere | Pass config explicitly or use module-level `config` singleton |
| **Low** | train.py:99 | Hardcoded model filename `"best_model.joblib"` — no versioning/timestamp | Use timestamped filename or include model hash in name |
| **Low** | selection.py:49-58 | `save_model` uses `joblib.dump` without compression; large pipelines waste disk | Add `compress=3` (or configurable) to `joblib.dump` |
| **Info** | models/__init__.py | Public exports list grows; consider `__all__` for clarity | Add `__all__ = ["train_baselines", "train_regularized", ...]` |

---

## 4. Security (security-architect)

- **Threat model scope:** ML training pipeline — user-controlled training data (X, y), config hyperparameters, base_estimators injection, model serialization (joblib/pickle), FastAPI network endpoint (/train), no auth/crypto/PII/payments/network-egress/file-upload/eval/IPC/contract/on-chain
- **Attack surface touched:** `/train` endpoint (POST, no auth), `base_estimators` dict (estimator injection), `Config` hyperparameters (resource exhaustion), model file write (pickle deserialization risk), `/health` and `/model_info` (info disclosure)

| Severity | File:Line | Finding | Suggested Fix |
|----------|-----------|---------|---------------|
| **Critical** | ensembles.py:61-86 (inherited) | **STRIDE-001**: Arbitrary estimator injection via `base_estimators` → RCE on pickle load via malicious `__reduce__` | Validate estimator types against allowlist; clone estimators; reject custom `__reduce__`/`__getstate__`; consider safetensors/ONNX instead of pickle |
| **High** | config.py:75, ensembles.py:43/54/80 (inherited) | **STRIDE-002**: `cv_n_jobs=-1` default consumes all CPU cores; no resource limits/timeouts | Cap `cv_n_jobs` at `min(cpu_count(), 4)`; add training timeout via subprocess + `resource.setrlimit` |
| **High** | ensembles.py:27-34, train.py:48-62 (inherited) | **STRIDE-003**: Input validation gaps — no max samples/features, dtype enforcement, constant-feature check | Add `MAX_SAMPLES`, `MAX_FEATURES`, `ALLOWED_DTYPES`; validate at pipeline entry; convert to float64 |
| **High** | config.py:58-63, 78-85 (inherited) | **STRIDE-004**: Config hyperparameters lack upper bounds (rf_n_estimators, gb_n_estimators, alpha values) | Add upper bounds in `Config.__post_init__`: rf_n_estimators ≤ 5000, alphas ≤ 1e6, etc. |
| **Medium** | ensembles.py:27-34 (inherited) | **STRIDE-005**: Verbose error messages leak internal validation logic | Use generic error messages in production; log details server-side |
| **Medium** | ensembles.py:68-73 (inherited) | **STRIDE-006**: VotingRegressor uses user estimators without cloning — shared mutable state | Clone estimators: `sklearn.base.clone(estimator)` |
| **Medium** | ensembles.py:17-88 (inherited) | **STRIDE-007**: No audit logging of training runs, data provenance, config used | Add structured audit logging (timestamp, data shape, config hash, models trained, duration) |
| **Medium** | selection.py:61-76 | **New**: `load_model` uses `joblib.load` (pickle) without integrity verification — model swap / RCE risk | Verify model hash/signature before loading; consider safetensors; restrict model dir permissions (0o750) |
| **Low** | server.py:36-42 | CORS allows `localhost:3000`, `localhost:8000` with credentials — dev-only config | Make CORS origins configurable via env; disable credentials in production |
| **Low** | config.py:146-147 | `ensure_dirs` uses mode `0o750` — good, but models dir should be `0o700` for serialized models | Tighten models_dir to `0o700` |
| **Info** | pyproject.toml:8-19 | Unpinned dependencies (scikit-learn, pandas, numpy, joblib, fastapi) — supply chain risk | Pin exact versions with hashes; add `pip-audit` to CI |

**Compliance notes:** No PII in California/Ames datasets. No auth/z/tls implemented — assume internal/trusted network only. GDPR/HIPAA/SOC2 not applicable to current scope.

---

## 5. Branch Status

- **Commits ahead of base (origin/master):** 1 (0558afd 💾 feat(ml): add model selection, serialization, and training API)
- **CI status:** Not run in this session (GitHub Actions would run on push/PR)
- **Merge conflicts:** None (clean rebase/merge from origin/master)
- **Uncommitted changes:** Yes — `pubspec.lock` modified, `STRIDE_ANALYSIS.md` untracked, coverage artifacts
- **Cleanup needed:** Remove coverage artifacts (`ml_backend/src/ml_backend/models/__init__.py,cover`, etc.); `STRIDE_ANALYSIS.md` should be in `docs/security/` or committed intentionally

---

## 6. Handoff Summary

- **User-facing change:** POST `/train` endpoint triggers full ML training pipeline (data load → split → preprocess → baselines → regularized → ensembles → tuning → select best by RMSE → save joblib). GET `/health` returns `{status, model_loaded}`. GET `/model_info` returns model steps if loaded.
- **How to use:**
  1. `cd ml_backend && pip install -e ".[dev]"`
  2. `make train` — runs full pipeline, saves `models/best_model.joblib`
  3. `make serve` — starts FastAPI on `127.0.0.1:8000`
  4. `curl -X POST http://127.0.0.1:8000/train` — triggers training via API
  5. `curl http://127.0.0.1:8000/health` — health check
  6. `curl http://127.0.0.1:8000/model_info` — model metadata
- **Rollback plan:** `git revert 0558afd` (single commit); model file `models/best_model.joblib` can be deleted manually
- **Follow-ups:**
  1. Fix Critical bugs in `train.py` (KeyError, base_estimators)
  2. Address inherited STRIDE Critical/High findings
  3. Add integration test for `run_full_training_pipeline()`
  4. Improve `server.py` / `train.py` coverage to >90%
  5. Add model integrity verification (hash/signature) before `load_model`

---

## 7. Proposed Fix Plan + Decision Matrix

| # | Severity | Fix target (file:line) | Diff sketch | Risk-of-fix | Needs test | Recommended action | Owner |
|---|----------|------------------------|-------------|-------------|------------|--------------------|-------|
| 1 | **Critical** | train.py:74-79 | Replace base_estimators creation with fresh unfitted estimators from config; remove baselines["RandomForestRegressor"] access | Low | **Yes** (integration) | **apply** | ML Eng |
| 2 | **Critical** | train.py:76 | Fix KeyError — either train RF in baselines, or get from ensembles, or create fresh | Low | **Yes** (integration) | **apply** | ML Eng |
| 3 | **High** | tests/test_train_api.py | Add integration test calling real `run_full_training_pipeline()` with reduced config (cv_folds=2, n_iter=2) | Low | N/A (is test) | **apply** | ML Eng |
| 4 | **High** | train.py:109-121 | Add structured error response schema; log traceback server-side | Low | Yes | **apply** | ML Eng |
| 5 | **High** | config.py:58-63,78-85 | Add upper bounds for rf_n_estimators, gb_n_estimators, alpha values in `Config.__post_init__` | Low | Yes (config tests) | **apply** | ML Eng |
| 6 | **High** | ensembles.py:27-34 | Add MAX_SAMPLES, MAX_FEATURES, ALLOWED_DTYPES validation | Medium | Yes | **apply** | ML Eng |
| 7 | **High** | config.py:75 | Cap cv_n_jobs at min(cpu_count(), 4) | Low | Yes | **apply** | ML Eng |
| 8 | **Medium** | selection.py:61-76 | Add model hash verification in `load_model`; store hash at save time | Medium | Yes | **apply** | ML Eng |
| 9 | **Medium** | server.py:13-26 | Replace global `_model` with dependency injection or add reload endpoint | Medium | Yes | **apply** | Backend Eng |
| 10 | **Medium** | server.py:52-59 | Return model hash, trained_at, config_hash in `/model_info` | Low | Yes | **apply** | Backend Eng |
| 11 | **Medium** | ensembles.py:68-73 | Clone base_estimators before passing to VotingRegressor/StackingRegressor | Low | Yes | **apply** | ML Eng |
| 12 | **Low** | train.py:99 | Use timestamped/model-hash filename instead of hardcoded "best_model.joblib" | Low | No | **defer** | ML Eng |
| 13 | **Low** | selection.py:49-58 | Add `compress=3` to `joblib.dump` | Low | No | **defer** | ML Eng |
| 14 | **Low** | config.py:87-90 | Add env var overrides for API host/port/workers | Low | No | **defer** | Backend Eng |
| 15 | **Info** | models/__init__.py | Add `__all__` for public API clarity | None | No | **defer** | ML Eng |
| 16 | **Info** | pyproject.toml:8-19 | Pin dependency versions with hashes; add pip-audit to CI | Low | No | **defer** | DevOps |

**Awaiting approval.** Reply with one of:
- `apply all` — execute every `apply` row
- `apply #1, #2, #3, #4, #5, #6, #7, #8, #9, #10, #11` — apply Critical/High/Medium fixes
- `defer #12, #13, #14, #15, #16` — leave Low/Info items
- `reject #N` — drop specific rows
- `proceed as-is` — merge without fixes (logged as explicit risk acceptance)

---

## 8. Prioritized Action Items

1. **[Critical]** Fix `train.py:74-79` base_estimators creation — use fresh unfitted estimators from config — blocks merge
2. **[Critical]** Fix `train.py:76` KeyError — RandomForestRegressor not in baselines — blocks merge
3. **[High]** Add integration test for `run_full_training_pipeline()` — blocks merge (untested core logic)
4. **[High]** Add upper bounds to Config hyperparameters (rf_n_estimators ≤ 5000, etc.) — blocks merge (DoS risk)
5. **[High]** Add input validation limits (MAX_SAMPLES, MAX_FEATURES, dtype enforcement) — blocks merge (DoS risk)
6. **[High]** Cap `cv_n_jobs` default to prevent CPU exhaustion — blocks merge (DoS risk)
7. **[High]** Structured error responses for `/train` endpoint — blocks merge (info disclosure)
8. **[Medium]** Model integrity verification (hash) in `save_model`/`load_model` — should fix before merge
9. **[Medium]** Replace global model state in server.py with DI or reload endpoint — should fix before merge
10. **[Medium]** Clone base_estimators in ensembles.py to prevent shared mutable state — should fix before merge
11. **[Medium]** Add audit logging for training runs — should fix before merge
12. **[Low]** Timestamped model filenames — nice to have
13. **[Low]** Joblib compression — nice to have
14. **[Low]** Env var overrides for API config — nice to have
15. **[Info]** `__all__` in models/__init__.py — FYI
16. **[Info]** Pin dependencies with hashes + pip-audit — FYI (tracked in HOME-1)

---

## 9. Appendix

### Tools / Agents / Skills / CLIs / MCP Endpoints Invoked

| Tool/Agent/Skill/CLI | Classification | Phase | Reason |
|---------------------|---------------|-------|--------|
| `git` (diff, log, status, rev-parse) | read-only | 0 | Project discovery, change set, branch info |
| `bash` (ls, cat, find) | read-only | 0 | Directory structure, file discovery |
| `read` (file reads) | read-only | 0-4 | Source code, config, tests, CI, docs inspection |
| `grep` / `glob` | read-only | 0-4 | Pattern searches across codebase |
| `shell` (make test, make lint, make format, pip install) | read-only* | 2, 3 | Verification gates (format/lint/test) — *test runs are read-only for verification |
| `python -c` (run pipeline) | read-only | 2 | End-to-end behavior verification |
| `qa-post-implementation` skill | observational | 2 | Framework for QA pipeline |
| `verification-before-completion` skill | observational | 2 | Evidence-before-claims discipline |
| `requesting-code-review` skill | observational | 2 | Structured review process |
| `finishing-a-development-branch` skill | observational | 2 | Merge readiness checks |
| `feature-summary` skill | observational | 2 | Handoff summary generation |
| **Sub-agents NOT dispatched** | — | 3 | **Contract violation**: Code Reviewer and Security sub-agents were NOT dispatched due to tool limitations in this host environment. Findings in Sections 3-4 are from manual analysis by this integrator agent, not from independent sub-agents. This downgrades confidence — report is incomplete per skill contract. |

### Commands Run (full text)

```bash
# Phase 0: Discovery
pwd && git rev-parse --show-toplevel && git rev-parse --abbrev-ref HEAD
git config --get remote.origin.url
git symbolic-ref refs/remotes/origin/HEAD
git branch -a && git diff --name-status origin/master...HEAD
ls -la /mnt/ALL/UniProjects/advanced-machine-learning/
ls -la /mnt/ALL/UniProjects/advanced-machine-learning/docs/ && ls -la /mnt/ALL/UniProjects/advanced-machine-learning/.github/workflows/
find /mnt/ALL/UniProjects/advanced-machine-learning -name "SPEC.md" -o -name "DESIGN.md" -o -name "ARCHITECTURE.md" -o -name "REQUIREMENTS.md" -o -name "PRD.md"
ls -la /mnt/ALL/UniProjects/advanced-machine-learning/.claude/ 2>/dev/null

# Phase 2: Verification
cd /mnt/ALL/UniProjects/advanced-machine-learning/ml_backend && make test
cd /mnt/ALL/UniProjects/advanced-machine-learning/ml_backend && make lint
cd /mnt/ALL/UniProjects/advanced-machine-learning/ml_backend && make format
cd /mnt/ALL/UniProjects/advanced-machine-learning/ml_backend && pip install -e .
cd /mnt/ALL/UniProjects/advanced-machine-learning/ml_backend && python -c "from ml_backend.api.train import run_full_training_pipeline; run_full_training_pipeline()"
git log --oneline origin/master..HEAD
git status --porcelain
```

### Sub-agents Dispatched

**None dispatched.** The host environment does not support `task`/`agent` tool for sub-agent dispatch. Per skill contract, this is a contract violation — Sections 3 (Code Quality) and 4 (Security) are produced by the integrator agent's manual analysis, not by independent context-free sub-agents. The report must be treated as **incomplete**; a full review requires independent Code Reviewer and Security sub-agent runs.

### Skills Loaded

- `qa-post-implementation` — primary skill, governs entire workflow
- `verification-before-completion` — evidence discipline
- `requesting-code-review` — review process
- `finishing-a-development-branch` — merge readiness
- `feature-summary` — handoff format

### Raw Findings Summary (truncated)

**Verification failure:** `run_full_training_pipeline()` raises `KeyError: 'RandomForestRegressor'` at `train.py:76`. Pipeline cannot complete.

**Code Quality:** 11 findings (2 Critical, 2 High, 4 Medium, 3 Low, 1 Info) — see Section 3 table.

**Security:** 11 findings (1 Critical, 4 High, 4 Medium, 2 Low, 1 Info) — see Section 4 table. Critical STRIDE-001 (RCE via pickle) inherited from prior phase unaddressed.

**Coverage gaps:** `train.py` 72% (missing lines 46, 80-101), `server.py` 55% (missing lines 20-26, 49, 54-56). No test exercises `run_full_training_pipeline()` or server lifespan/model loading.

### User's Approval / Override

**Pending.** Awaiting explicit decision on Decision Matrix (Section 7).

---

*Report generated by qa-post-implementation skill (integrator agent). Sub-agent dispatch was not possible in this host; findings are integrator's manual analysis. For production gate, independent sub-agent review is required.*