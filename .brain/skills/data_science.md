# .brain/skills/data_science.md - ADVANCED DATA SCIENCE & SIGNAL PROCESSING PROTOCOL

*COGNITIVE DIRECTIVE: This is a living evolutionary document. If you encounter a more optimized methodology, a newer API standard, or a superior architectural pattern during development, you are strictly mandated to activate the Cognitive Evolutionist persona during Gate 6 and rewrite these rules to permanently upgrade this skill.*

When this skill is activated at Gate 0, you must treat honest evaluation, data validation, mathematical consistency, and model scaling as hard software requirements.

SCOPE LAW: apply only the sections matching the project's declared work. Section 2's RF/CSI signal rules bind only projects actually processing signal or telemetry data; Section 3 binds only projects training models. A generic Python project (matched via `requirements.txt` etc.) takes only what its plan actually does — a Flask website owes nothing to subcarrier filtering.

## 1. Honest Evaluation Is a Hard Requirement (the number must be trustworthy before it is high) *(harvested 2026-07-15 from child: EnviroNet — ledger L-004/L-005)*
- Evaluation that must predict performance on unseen entities MUST split by that entity: leave-one-subject-out / leave-one-group-out, never a random row/window split that lets the same subject or overlapping windows appear in train and test.
- Early-stopping and model selection use a held-out VALIDATION subject — never the test fold. Selecting the best epoch on the test set silently inflates every reported number.
- Report POOLED metrics across folds, and verify no fold is degenerate (single-class or trivially separable) before trusting any per-fold score.
- A metric that DROPS under honest evaluation is a measurement correction, not a regression — surface it plainly with the reason. Truth-in-reporting outranks a good-looking number.
- Before a modeling campaign, judge whether the ceiling is DATA or MODEL. When repeated honest improvements plateau, stop and record the dead ends; more/diverse data is usually the dominant lever, and data-hungry methods (SSL, contrastive) underperform simple baselines below ~10–100× their data threshold.
- Results exist only if they are REPRODUCIBLE from the committed pipeline: no hand-edited result files, no ad-hoc scripts diverging from the committed harness. A sudden large jump over a validated baseline is presumed error until an independent re-run confirms it. *(L-006)*
- FALSIFY leakage, don't just avoid it: a domain-adversarial probe (DANN with gradient reversal λ→1) that drives entity/subject-identity recovery to chance while the target metric HOLDS proves the result rides on the signal, not on memorizing entities — stronger evidence than a clean split alone. (EnviroNet Phase 6: subject-ID scrubbed to 0.00%, HAR held at 74.6%.)
- UNIT OF ANALYSIS: measure significance at the EXCHANGEABLE unit (subject/group/site), never at pooled correlated samples. Overlapping windows or repeated measures make a pooled McNemar/accuracy look significant when a per-subject t-test or sign-test shows it is not — a "+2.83 pt" gain that vanishes (to −0.01) when one subject is removed was never demonstrated. Report a CI at the right unit (n = subjects, not windows). (EnviroNet Phase 8, L-007/L-009)
- SYMMETRIC SKEPTICISM: apply the SAME statistical scrutiny to welcome and unwelcome results. A tripwire that guards only the "it got worse" branch lets a REAL number acquire a FALSE causal story and sail past its own guard. And a correct prediction of the NUMBER does not validate the MECHANISM — check per-class/per-fold effects before claiming why it worked. (L-009)
- VERIFY THE REPRESENTATION before recording a dead end: confirm the code actually computed the quantity the lever is named after. ("Signed Doppler adds nothing" was measured on sign-FOLDED data — the information was destroyed before the test; a valid result about the wrong quantity.) (L-006)
- CEILING ATTRIBUTION: before declaring a data ceiling, check every metadata field the harness IGNORES (room, site, device, session). Measure cross-ENVIRONMENT generalization, not just cross-subject — an unused `room_id` column was the difference between "we need more subjects" and "we need more rooms" for three phases (cross-room accuracy 80.5%→44% where cross-subject barely moved). (L-010)

## 2. Signal Processing & Preprocessing Pipelines
- When managing high-frequency telemetry or RF data (e.g., Wi-Fi Channel State Information amplitude and phase matrices over subcarriers), enforce strict noise-filtering layers (Butterworth, Hampel, or phase calibration filters) prior to array manipulation.
- Validate tensor input arrays explicitly for dimension mismatches, exploding values, or missing subcarrier frames at the entry boundary.
- Verify preprocessed caches against an independent re-derivation from raw data before training on them; a silently wrong parser (e.g., a mis-split amplitude/phase column layout) corrupts every downstream result.

## 3. Deep Learning Optimization (TensorFlow / Keras / PyTorch)
- Recurrent and spatial modeling layers (LSTM, CNN, Transformers) must feature structured regularization steps (Dropout, Layer Normalization, Batch Normalization).
- Loss functions, custom learning rate schedules, and optimization passes must feature explicit gradient clipping thresholds to handle exploding/vanishing gradients.
- Guard numerical stability at the data boundary: normalize by mean-of-absolute-values (not raw mean) for zero-centered inputs to avoid divide-by-near-zero; watch fp16 overflow in custom losses (e.g., NT-Xent).
- Noisy auxiliary labels are DEAD WEIGHT as anchors: forcing clean features to align with a noisy auxiliary modality (e.g., single-camera pose, interpolated far above its capture rate) via an alignment/embedding loss degrades the primary task — the noise becomes a constraint pulling against the signal. Only anchor to auxiliary data whose noise floor sits below the primary signal's. (EnviroNet Phase 7 ACMA: 76% → 68.3%.)

## 4. Data Engineering & Analytics Infrastructure
- Enforce strict tracking schemas on all feature engineering steps. Data ingestion loops must stream large binary matrices through vectorized memory mapping frameworks to prevent system out-of-memory panics.

## 5. Experiment-Harness & ML Security *(harvested 2026-07-29 from EnviroNet Phase 8, L-008)*
- **`torch.load(weights_only=True)` ALWAYS.** The default pickle path is a code-execution sink (a `__reduce__` gadget runs on load) — critical when the checkpoint dir is writable by other accounts. RNG/random state can still be saved: encode `random.getstate()[1]` and `np.random.get_state()[1]` as int64 tensors plus scalar fields. Load checkpoints with `map_location='cpu'` — `map_location=device` puts RNG ByteTensors on CUDA and `set_rng_state` then raises `TypeError`, crashing every resume.
- **Never hardcode live credentials** (webhooks, tokens, keys) in source. Gitignore is not enough for one already written — a token readable by any local account is a live secret and must be ROTATED, not just un-committed. A new network capability needs an acceptance criterion or it is unauthorized egress.
- **Destroy-after-validate, and validate includes the lock.** Destructive harness ops (`--fresh`, cleanup) must acquire the run lock and pass every check BEFORE deleting anything — never delete a live run's checkpoints on the way to refusing to start.
- **Resume/skip fingerprints derive from the CONSTRUCTED model** (type name + parameter count + per-tensor shapes), not from CLI/argparse values — a flag-only fingerprint misses in-source hyperparameter edits and republishes stale folds under a new configuration.
- **A smoke test that persists its state stops being a test** — a repeated `--smoke` that skips "already complete" folds trains nothing and still prints green. Smoke runs clear their own state at startup.
