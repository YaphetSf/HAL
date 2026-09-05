# HAL AI Editing Eval

Measures whether a model is good enough for HAL's selection-based Proofread and Rephrase.
It is not a unit test: results change after an OS, runtime, or model update.

## The model is external

HAL speaks one thing to one thing: an OpenAI-compatible `/v1/chat/completions` endpoint (D28).
Where the weights live, which runtime loads them, and how they are quantized are the operator's
business, not HAL's. **The eval is built the same way.** `endpoint_eval.py` is the canonical
runner: it sends the same request HAL sends, so what it measures is what the product experiences.

Adding a model to the eval means adding a URL to `endpoints.json`, never a checkpoint path to
this repository.

```bash
# Against a server on this machine, or any machine you can reach.
Evals/src/endpoint_eval.py \
  --endpoint http://127.0.0.1:8901/v1/chat/completions \
  --label my-model \
  --cases Evals/src/cases.json \
  --prompts Evals/src/prompts.json \
  --report Evals/results/my-model.json
```

Standard library only, so the eval runs wherever HAL runs. `--model` is omitted from the request
when unset: `mlx_lm.server` reads that field as "load this model" and an empty string starts a
bogus load. The eval talks directly to the same user-owned model server as HAL.

### Transport floor

Every run first measures a near-empty completion five times and reports the median as the
transport floor — network round trip plus server fixed overhead. Case latency is then reported
both as a total and as an estimated model time.

This separation is not cosmetic. Against an M3 Ultra over a relayed Tailscale link the floor was
**424 ms with 244 ms of jitter**, i.e. 43% of the 988 ms average was not the model at all, and the
jitter alone was comparable to the gap between two candidate models. The same checkpoint measured
in-process on the server host averaged 655 ms. **A number taken in-process understates what the
user waits by roughly half**, so never compare an in-process figure with an endpoint figure.

### Serving a checkpoint

Any OpenAI-compatible server works — `mlx_lm.server`, LM Studio, Ollama, llama.cpp. For a
thinking-capable Qwen, thinking must be off or `content` comes back empty with the answer stranded
in `reasoning`; the runner detects exactly that and says so instead of reporting a blank failure:

```bash
mlx_lm.server --model <dir> --host 0.0.0.0 --port 8901 \
  --chat-template-args '{"enable_thinking":false}'
```

## Refusal and sanitization probe

`cases.json` measures editing quality on neutral text and says nothing about charged input. A
refusal, a moralizing preamble, or a silent softening are all product failures in an input method,
and the last is invisible to the main suite because a reworded output is what `rephrase` is
supposed to produce.

```bash
Evals/src/refusal_probe.py \
  --endpoint http://127.0.0.1:8901/v1/chat/completions \
  --prompts Evals/src/prompts.json --report Evals/results/probes/refusal-<name>.json
```

Twenty probes over control, politics, profanity, security, medical, drugs, fiction, and
self-harm-adjacent text. Every probe carries a real typo, so a model that echoes the input is
distinguishable from one that corrects it: bailing scores `not_fixed`, working but stripping the
charged span scores `sanitized`. They need different fixes, so they are reported separately.

Measured 2026-08-29 across seven checkpoints: **zero safety refusals in 140 generations.** The one
`refused` verdict was Phi-4-mini misreading the prompt contract, not declining the content. The
real and universal finding was profanity laundering during `rephrase` — 7/7 models — fixed by one
clause in `prompts.json` rather than by an uncensored checkpoint, which would have traded a rare
refusal for systematically worse instruction-following.

## Comparing results

```bash
Evals/src/compare_results.py
```

Prints a role matrix (action x language) instead of one leaderboard, because each model is scored
only on the slice it claims to support. It lists fixtures that fail across many models and warns
when reports span different suite versions.

## Controls

```bash
HAL_REWRITE_EVAL_RUNS=3     # sample a nondeterministic model
HAL_REWRITE_EVAL_CASE=<id>  # one fixture while iterating on a prompt
HAL_REWRITE_EVAL_STRICT=1   # quality failure exits 1, for a release gate
```

The default is report-only: every case prints its output, latency, and failed invariants, but a
quality failure does not change the exit code. The report is written before the strict-mode exit
decision, so a failing gate still leaves evidence.

## The fixture contract

`cases.json` is the stable evaluation contract. Each fixture carries an illustrative reference
answer plus machine-checkable invariants: language preservation, protected literals that must
survive byte-for-byte, required or forbidden patterns that admit equivalent wording, and — for
concise rewriting — a maximum length ratio. The reference is for human review and is never
compared byte-for-byte.

`protectedLiterals` is only for spans whose *exact form* is under test: code-switched English
spans, versions, dates, inline code, anchored technical terms. Ordinary semantic concepts belong in
`requiredPatterns` with their acceptable synonyms (`等待(时间|时长|延迟)`), and a required pattern
must never demand a rewrite the prompt itself discourages. Getting this wrong produces false
failures that look like model defects; it has happened four times.

**Adding cases is safe. Changing a rule is not.** New fixtures cannot move an existing verdict, so
they only add resolution. A rule change must be replayed against every output already recorded in
`Evals/results/*.json`: if any score moves, the suite is being tuned to flatter a model rather than
corrected. Verify that before accepting the change.

Increment `version` in `cases.json` when the fixture contract changes, and `version` in
`prompts.json` when the prompt changes. Keeping them independent is what makes runtime and
checkpoint comparisons meaningful. Report filenames carry no version; the JSON records
`suiteVersion`.

## The one runner that cannot be an endpoint

`main.swift` evaluates Apple's on-device Foundation Model, which has no server and no wire
protocol — it is reached through `FoundationModels` in-process, or not at all. It stays because
`appleOnDevice` is HAL's **default** provider, so leaving it unmeasured would mean shipping the
default path blind.

```bash
scripts/eval-local-rewrite.sh
```

It requires macOS 26+, Apple Silicon, and an available Apple Intelligence model, and it is **not**
deterministic unlike a greedy served model, so sample it with `HAL_REWRITE_EVAL_RUNS=3` or more
before drawing any conclusion. It writes the same report shape as `endpoint_eval.py`.

## What was removed, and why

`mlx_eval.py`, `transformers_eval.py`, `run_baselines.py`, `download_baselines.py`, and
`macbert_probe.py` were deleted on 2026-08-29, along with `scripts/eval-mlx-rewrite.sh` and
`scripts/eval-transformers-rewrite.sh`. They loaded checkpoints from disk on the machine holding
the weights. They produced the fifteen-checkpoint baseline survey and the macbert CSC probe, both
closed with evidence, and the reports they wrote are preserved.

They were removed for two reasons, not one. They measured a code path HAL never executes, so their
latency numbers understated what a user waits by roughly half. And running them required copying
this directory onto the serving machine, where the copy silently aged: on 2026-08-29 that copy's
`prompts.json` was a version behind, and a suite run there used the older instructions without
saying so. Nothing was invalidated that time, by luck.

`endpoint_eval.py` and `refusal_probe.py` both run from this repository and reach the model over
HTTP, so no HAL code needs to exist on the serving machine and that failure class cannot recur.
Re-measuring a checkpoint now means serving it and pointing the endpoint runner at it.
