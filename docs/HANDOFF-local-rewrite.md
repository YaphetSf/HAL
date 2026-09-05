# HAL Local Rewrite — Agent Handoff

Updated: 2026-08-30 (Europe/London); suite v6 (curly-apostrophe fix, replay-verified), fifteen checkpoints measured, every alternative to Qwen3.5-9B-MLX-4bit closed with evidence; rewrite prototype shipped with two providers (Apple Intelligence + user-owned OpenAI-compatible server), with a user-editable Rephrase prompt

## Objective

Build and evaluate a local text-editing model for HAL that supports:

- Chinese, English, and mixed-language text.
- `correct`: conservative spelling/grammar correction that preserves names, numbers, commands, and already-correct input.
- `rephrase`: improve wording without changing meaning or returning chatbot commentary.
- Eventually run the final quantized model locally on the user's M4 Pro; use the M3 Ultra for downloads, baseline evaluation, fine-tuning, conversion, and quantization.

The current phase is **baseline evaluation**, not training yet. Only train/fine-tune after measuring existing specialist models against the shared eval suite.

## Non-negotiable machine split

- **M3 Ultra (`ssh m3u-ts`)**: all baseline checkpoints, datasets, Python/PyTorch dependencies, evaluation, training runs, adapters, exports, MLX conversion/quantization.
- **M4 Pro (current host)**: the shared production MLX runtime under `/Users/ding/Developer/MLX`
  and only the chosen deployable model at
  `/Users/ding/Developer/LLMs/Qwen3.5-9B-MLX-4bit`.
- Do not install PyTorch/training packages or accumulate baseline checkpoints on the M4 Pro.
- A former baseline copy was deleted after the M3 Ultra copy passed verification. Once Qwen was
  selected as the final user-operated model, it was downloaded again on the M4 Pro with aria2 and
  verified against Hugging Face revision `938d8919941c6e7efd3c7150eff7fe9d12afa631`.
  Hugging Face's Xet redirects initially gave the three LFS files content-addressed names; they were
  checksum-matched and restored to `model-00001-of-00002.safetensors`,
  `model-00002-of-00002.safetensors`, and `tokenizer.json`. No `.aria2` files remain; the LLMs root
  contains only the final model directory and `.DS_Store`.
- Clean exact temporary/incomplete artifacts when superseded; resolve and verify the exact target before destructive commands.

## Project rules

- Repository: `/Users/ding/Projects/HAL`
- Read and obey `/Users/ding/.codex/RTK.md`; prefix shell commands with `rtk`.
- No backward compatibility unless explicitly requested.
- Prefer the best end-state design and remove obsolete approaches.
- Preserve unrelated user changes in the dirty worktree.
- Use `apply_patch` for file edits.

## Current repository artifacts

Start with the documentation and scripts rather than reconstructing them from this handoff:

- Eval overview: `Evals/README.md`
- Eval cases: `Evals/src/cases.json` (suite **v7**, 18 cases)
- Shared Python checks/prompt contract: `Evals/src/eval_common.py`
- Prompt contract: `Evals/src/prompts.json` (**v2** — adds the profanity-preservation clause)
- **Canonical runner: `Evals/src/endpoint_eval.py`** — speaks the OpenAI-compatible
  `/v1/chat/completions` HAL speaks, so it measures what the product experiences. Models are
  external by construction; adding one means adding a URL to `endpoints.json`, never a checkpoint
  path. Reports a transport floor (round trip plus server overhead) separately from model time.
- Shared transport: `Evals/src/endpoint_client.py`
- Endpoint registry: `Evals/src/endpoints.json`
- Refusal/sanitization probe: `Evals/src/refusal_probe.py` (endpoint-based; reports to
  `Evals/results/probes/`)
- Foundation Models runner: `Evals/src/main.swift` — the only in-process runner left,
  because Apple's on-device model has no server, and `appleOnDevice` is HAL's default provider.
- Shell entry points: `scripts/eval-endpoint-rewrite.sh`, `scripts/eval-local-rewrite.sh`

**Deleted 2026-08-29** — `mlx_eval.py`, `transformers_eval.py`, `run_baselines.py`,
`download_baselines.py`, `macbert_probe.py`, `scripts/eval-mlx-rewrite.sh`,
`scripts/eval-transformers-rewrite.sh`. They loaded checkpoints from disk on the serving machine.
Their reports are preserved; the code is not, for two reasons. They measured a path HAL never
executes (in-process latency understates the user's wait by roughly half — 655 ms vs 988 ms for the
same checkpoint), and using them required copying the eval directory onto the serving machine,
where the copy silently aged: on 2026-08-29 that copy's `prompts.json` was one version behind and a
suite run there used stale instructions without saying so. Re-measuring a checkpoint now means
serving it and pointing `endpoint_eval.py` at it. **Do not reintroduce an in-process runner.**

Selection-rewrite feature sources (D28, shipped 2026-08-29 — see *Product decision*):
`Sources/Core/AIEditSettings.swift`, `Sources/Panel/AIEditEngine.swift`,
`Sources/Panel/AIEditPanel.swift`, `Sources/SettingsApp/TabViews/AIEditSettingsView.swift`,
plus `UserSettings.aiEdit` in `Sources/Core/UserSettings.swift` and the "AI Edit" tab in
`Sources/SettingsApp/ControlCenterView.swift`. Tests: `Tests/CoreTests/AIEditSettingsTests.swift`.

These were statically checked: Python AST parsing, `bash -n`, JSON parsing, and Swift typechecking all passed. They still require real model runs on the M3 Ultra.

The worktree was already dirty before this effort. Known pre-existing user work includes changes to `README.md`, `Sources/IMK/InputController.swift`, and an untracked `Sources/Panel/AIEditPanel.swift`. Do not discard or overwrite it.

## Eval suite state

`cases.json` is version 6 with ten cases covering:

- English, Chinese, and mixed correction.
- Preservation of proper nouns, versions, dates, paths, and commands.
- No-op behavior for already-correct English and Chinese.
- Chinese, English, and mixed rephrasing.
- Literal-preservation and forbidden-output checks.

**The v3/v4 contract split matters and must be respected when adding cases.** `preserve` was doing
two incompatible jobs, so it was replaced by:

- `protectedLiterals` — spans whose *exact form* is the thing under test: code-switched English spans,
  versions, dates, inline code, anchored technical terms. Checked byte-for-byte.
- `requiredPatterns` — semantic content that must survive, expressed so that equally correct wording
  passes (for example `等待(时间|时长|延迟)`).

Putting an ordinary semantic concept in `protectedLiterals` produces false failures. Three real
instances were found and fixed: `等待时间` in `rephrase-zh-product-risk` (v3); in v4 a required
past-perfect backshift in `correct-en-grammar` that contradicted the prompt's "no stylistic rewrite
beyond correctness" rule, plus reworded-noun literals in `rephrase-zh-remove-filler` and a redundant
`release` literal in `rephrase-en-direct`; and in v5 the literal `not ready for release` requirement in
`rephrase-en-direct`, which rejected the equally valid "I don't think this experience is ready to be
released yet". That last one is replaced by a form-tolerant meaning check plus an explicit ban on the
filler opener the case actually targets.

**None of these fixes changed any model's score.** Verify that property before accepting a rule
change — replay the new rule against every output already recorded in `Evals/results/*.json`. If a
score moves, the suite is being tuned to flatter a model rather than corrected.

`correct-en-grammar` fails for every model measured so far. That was checked and the case is sound:
mEdIT does fix `too much work` but substitutes `finished` for `completed` (a lexical change the
`correct` contract disallows), and the on-device model passes it 1 run in 3. It is simply the hardest
fixture, not a broken one.

The runners support specialist slicing: a model is evaluated only on tasks/languages it claims to support, while unsupported cases are explicitly reported as skipped rather than counted as success.

Both Python runners take `--report <path>` and write a structured JSON result: suite/prompt version,
backend, platform, model, profile, per-case output and violations, per-case and aggregate latency,
and peak memory. The report is written before the strict-mode exit-code decision, so a failing strict
run still leaves evidence. Report filenames carry no suite version; the JSON records `suiteVersion`.

## Measurements (suite v6)

Regenerate this table any time with `compare_results.py`; it reads `Evals/results/*.json` and warns if
reports span different suite versions. All rows are currently suite v6.

```text
model                        score   runs  cor/en cor/zh cor/mix rep/en rep/zh rep/mix  warm ms  peak GB
chinese-error-corrector4-4b   1/2      1    -     1/2     -      -      -      -          971      8.4
coedit-large                  1/4      1   1/3     -      -     0/1     -      -          321      3.3
foundation-models             8/30     3   5/9    3/6    0/3    0/3    0/6    0/3         525        -
gemma3-4b-it-4bit             7/10     1   2/3    1/2    1/1    1/1    2/2    0/1         448      3.2
macbert4csc                   2/2      1    -     2/2     -      -      -      -            11      1.1
medit-xl-7b                   3/10     1   2/3    1/2    0/1    0/1    0/2    0/1        1649     22.2
phi4-mini-4bit                3/10     1   2/3    1/2    0/1    0/1    0/2    0/1         396      2.9
qwen25-3b-gec-v2              2/3      1   2/3     -      -      -      -      -          364      6.3
qwen3-4b-instruct-mlx4        7/10     1   2/3    1/2    1/1    1/1    2/2    0/1         380      2.9
qwen35-0.8b-mlx4              4/10     1   1/3    1/2    0/1    1/1    1/2    0/1         206      1.0
qwen35-2b-mlx4                4/10     1   1/3    1/2    1/1    0/1    1/2    0/1         323      1.7
qwen35-4b-mlx4                6/10     1   2/3    1/2    0/1    1/1    2/2    0/1         437      3.2
qwen35-9b-3bit                6/10     1   2/3    2/2    0/1    1/1    1/2    0/1         630      4.8
qwen35-9b-mlx4                9/10     1   2/3    2/2    1/1    1/1    2/2    1/1         632      5.8
```

All numbers were taken on the M3 Ultra except `foundation-models`, which necessarily runs on the M4
Pro. Transformers rows report total latency only; the MLX rows' warm TTFT is 441 ms (Qwen3.5-9B) and
122 ms (Qwen2.5-3B-GEC).

Cells are passes/attempts, so the 3-run on-device row has 3x denominators. MLX and Transformers runs
are greedy and reproduced identically across re-runs; the on-device model is **not** deterministic
(`correct-en-no-op` flipped between runs when it echoed the `<selected_text>` wrapper into its
output), so always sample it with `HAL_REWRITE_EVAL_RUNS=3` or more.

What each result actually says:

- **Qwen3.5-9B MLX 4-bit — 9/10, the only model that covers every role.** Warm TTFT 441 ms, warm
  total 631 ms, peak 5.81 GB, load ~1.0 s. Its one failure is genuine: it left `too many works`
  uncorrected while fixing `goes`, `manager ask`, `report were`, and `haven't complete`.
- **Apple Foundation Models — 10/30, and 0/12 on rephrase.** It reliably leaves correct text alone
  and preserves literals, but never corrected the Chinese typos (0/3), never handled code-switch
  correction (0/3), and never rephrased anything (all four rephrase fixtures returned the input
  verbatim). It also sometimes emits the `<selected_text>` wrapper into its own output, which would
  paste literal tags into the user's document. As the "ship nothing extra" option it is not viable
  for Rephrase and not viable for Chinese correction.
- **mEdIT-XL 7B — 3/10, and disqualified on behavior, not just licensing.** It translated the
  code-switched English spans into Chinese (`feature`→`功能`, `release`→`发布`), which is fatal for a
  Chinese IME whose users code-switch constantly. It also deletes content when rewriting: it dropped
  `本地模型`/`输入法` and the whole "does it help users" clause. Its Chinese correction left `以经`
  and `检察` untouched. It refuses to rewrite English filler under every documented instruction.
- **ChineseErrorCorrector4-4B — 1/2 on its Chinese-correction slice.** It fixed `以经`→`已经` but
  left `检察`→`检查` uncorrected, and costs 998 ms warm and 8.4 GB — slower and heavier than the
  4-bit 9B that handles every role. Its `<think>` block stayed short (86 generated tokens), so the
  1024-token budget is ample.
- **CoEdIT-large 770M — 1/4 on its English-only slice.** Cheapest and fastest (~400 ms warm), but it
  **stripped the backticks** around `` `scripts/rebuild-dev.sh` ``, which would destroy inline code
  formatting in HAL, and it produced the ungrammatical `there was too many work`.
- **Qwen2.5-3B-GEC-v2 — 2/3 on its English-correction slice.** Fastest warm TTFT measured (122 ms,
  382 ms total), preserves backticks, handles the no-op. But it peaks at 6.3 GB in bf16, i.e. *more*
  than the 4-bit 9B that covers every role, so it is only interesting if quantized to 4-bit.

Two measurement bugs were found and fixed while collecting this; re-measure rather than trusting any
earlier numbers:

- The Transformers runner reported peak memory from `ru_maxrss` alone, which does not account for
  weights living in MPS driver-allocated memory. It claimed **0.587 GB for a 7B fp16 checkpoint**; the
  real figure is **22.2 GB**. It now reports `max(RSS, torch.mps.driver_allocated_memory())`.
- Every MPS model was loaded in fp16 regardless of the precision it was trained in. Precision is now
  per profile: fp32 for CoEdIT (T5 is a known fp16-overflow case), fp16 for mEdIT's LLaMA-1 base, and
  bf16 for the Qwen3-based Chinese corrector. Re-running under the corrected precision left every
  score unchanged, so the earlier quality numbers were not distorted — only the memory column was.

## Size ladder result (measured 2026-08-29): quality falls off a cliff below 9B

The open question above — "how small can a general model get and still hold ~9/10" — is now answered
with measurements, all on the M3 Ultra, same `hal` profile, greedy single runs:

```text
qwen35-9b-mlx4          9/10   643 ms   5.8 GB
qwen3-4b-instruct-mlx4  7/10   381 ms   2.9 GB   (text-only cross-check, different generation)
qwen35-4b-mlx4          6/10   436 ms   3.2 GB
qwen35-2b-mlx4          4/10   322 ms   1.7 GB
qwen35-0.8b-mlx4        4/10   204 ms   1.0 GB
```

Nothing in the 0.8-4B range holds ~9/10. 0.8B→2B buys nothing (both 4/10); the climb is 2B→4B→9B.
The failures are not noise — every ladder model fails `correct-zh-typos` (the 以经/检察 fixture) and
`rephrase-zh-en-code-switch`, i.e. the two capabilities that distinguish HAL's use case:

- **qwen35-4b** fixed 以经→已经 but left 检察 untouched (same failure as ChineseErrorCorrector4),
  wrote "there is still a few edge cases", and dropped "the" from the protected literal "the current UX".
- **qwen3-4b-instruct** returned correct-zh-typos input verbatim, and returned the rephrase-zh-en
  input verbatim too. It did fix "too much work" — which even the 9B misses — but broke
  "report was ready"→"report were ready".

So the fork stated in the Recommendation is now live and mandatory: **accept the 9B at ~1.7 s on the
M4 Pro, or fine-tune a small model.** There is no off-the-shelf middle.

**macbert4csc** (`shibing624/macbert4csc-base-chinese`, fill-mask, ~100M params, Apache-2.0) was
measured as the last specialist: 2/2 on its suite slice (`correct-zh-typos`, `correct-zh-no-op`) at
**36 ms warm** / 275 ms cold. One fixture is thin evidence, so a dedicated 22-probe CSC battery
(`macbert_probe.py`, since deleted; result formerly saved separately) then
measured it across the whole `correct` contract: **14/22 scored, and the failures are disqualifying.**

- Its home game is only ~75/50% reliable: phonetic same-length typos 6/8, visual 2/4 — and the
  misses are *confident wrong substitutions* (安状→安视 instead of 安装, 文按→文案 instead of 文件,
  苹杲→苹基), which for an IME is worse than leaving the typo. One case corrupted twice: 太度→耐度
  and 他→她, changing the pronoun's gender unasked.
- **It rewrites proper nouns**: 张伟→张玮, 李明→黎民. Fatal for a text input method.
- **It corrupts code-switched English**: `feature`→`布划` (a random Chinese word), and lowercases
  English identifiers (`Python`→`python`, `GitHub`→`github`) because the BERT Chinese tokenizer is
  case-folding. Fatal for HAL's user base.
- Clean where it should be: 3/3 no-op on correct Chinese, and numbers/versions/paths survive
  (v1.2.3, dates, /etc/nginx/nginx.conf) once the decode's whitespace artifact is normalized away.
- Insert/delete confirmed structurally impossible, as the fill-mask architecture predicts.

The 36 ms speed cannot buy back corrupted names and mangled English. **The specialist line is now
fully closed with evidence: no fast-path role exists for macbert4csc in HAL.**

### Closing the remaining alternatives (2026-08-29)

Three more hypotheses were measured the same day, all negative:

- **Gemma 3 4B (`mlx-community/gemma-3-text-4b-it-4bit`) — 7/10, 448 ms.** Ties Qwen3-4B-Instruct on
  score and loses on latency. Notable behavior: it *creatively* "fixed" the Chinese typos by
  rewriting the clause (以经检察过 → 认真检查过), which violates the no-content-change contract even
  though the typos are gone. On `rephrase-zh-en-code-switch` it translated the English spans into
  Chinese (feature→功能), the same disqualifying behavior as mEdIT.
- **Phi-4-mini (`mlx-community/Phi-4-mini-instruct-4bit`) — 3/10, 396 ms.** Chinese is too weak, as
  expected. Measured to close the category rather than from hope.
- **Qwen3.5-9B at 3 bits — 6/10, quantization cliff.** No 3-bit/2-bit quantization of the 9B exists
  upstream — every `Qwen3.5-9B-3bit`/`mixed_*` repo on the Hub is an **empty shell** (only
  `.gitattributes`), so the bf16 checkpoint was downloaded and quantized locally with
  `mlx_lm convert -q --q-bits 3 --q-group-size 64` (3.7 GB, 3.5 bits/weight effective). Quality fell
  9→6 and M3 Ultra latency did not move (630 ms vs 632 ms — fixed overheads dominate at this
  generation length). 4-bit is the model's safe depth; below it the task breaks. The bf16 source
  (18 GB) is **kept** under `general/Qwen3.5-9B-bf16` as the natural base for a fine-tune.

The evidence map is now complete and consistent: quality is a step function between 4B and 9B for
this task, and 4 bits is the quantization floor. **Qwen3.5-9B-MLX-4bit is the only off-the-shelf
checkpoint that works. No further model hunting is warranted.**

### Suite v6 (2026-08-29): curly-apostrophe fix

Gemma emitted `isn’t ready for release` (curly apostrophe) on `rephrase-en-direct` and the
`requiredPattern` `(not|n't)` rejected it — semantically correct output, mechanically failed. Fixed
to `(not|n[’']t)`, suite bumped v5→v6. Per the replay doctrine: every recorded output was replayed
against both patterns; exactly one verdict flips (Gemma's false failure) and no other model moves.
All fifteen reports were then re-measured under v6, so the table above is single-version. Note
`foundation-models` moved 10/30→8/30 across re-measurement — that is the documented run-to-run
nondeterminism of the on-device model (3-run sampling), not a rule change; every other model
reproduced identically.

## Recommendation

**The binding constraint is decode speed on the M4 Pro, not quality.** Read this before acting on the
table above: every Qwen latency figure in it was taken on the M3 Ultra, which is roughly 3x the
memory bandwidth of the deployment target.

An earlier session measured this same checkpoint on the M4 Pro at **1.13 s TTFT / 1.71 s total** and
concluded it performed poorly, which is what motivated hunting for specialist models. That conclusion
was correct on the axis that matters. The M3 Ultra numbers here (451 ms TTFT / 643 ms total, ~118
tok/s decode) do not contradict it: the ratio is 2.5-2.7x, consistent with the 273 GB/s vs 800 GB/s
memory-bandwidth gap for a bandwidth-bound decode. Expect roughly 40-45 tok/s on the M4 Pro.

The earlier session's quality verdict is a different story and was partly an artifact. It recorded
"strict 4/6, human 5/6" — it had already spotted one false failure from an over-strict rule, the same
bug class fixed three more times in v3-v5. Read against that, 83% then and 90% now are consistent, and
Qwen3.5-9B's *quality* was never really the problem.

**The hunt came back empty.** None of the five alternatives fixes latency without losing the feature:
the two fast ones (CoEdIT 328 ms, Qwen2.5-3B-GEC 382 ms) are single-role English models scoring 1/4
and 2/3, and the only multi-role alternative costs 1744 ms and 22 GB while translating code-switched
English into Chinese.

So the open question is not "which model is better" but "how small can a general model get and still
hold ~9/10", since size is what buys speed on the M4 Pro. A 3-4B at 4-bit should land near 600-700 ms
total there.

---

**Adopt `mlx-community/Qwen3.5-9B-MLX-4bit` as the quality reference and current fallback, and do not
fine-tune yet.**

- It is the only model that covers all six roles, and it is the best on every role it shares with a
  specialist. Apache-2.0, so it is shippable — unlike mEdIT and CoEdIT, which are non-commercial.
- **The specialists do not compose into a cheaper alternative.** Stacking the two best Apache-2.0
  specialists (Qwen2.5-3B-GEC for English, ChineseErrorCorrector4 for Chinese) still leaves nobody
  covering mixed-language correction and nobody covering rephrase in any language, while needing
  language-detection routing and 14.7 GB of resident weights against the 9B's 5.8 GB. It is worse on
  quality, memory, latency, and complexity simultaneously.
- Each specialist is also weak on its *own* slice: 1/4, 2/3, and 1/2 respectively.
- The Apple on-device model is not a viable "ship nothing extra" option: 0/12 on rephrase and it never
  corrected Chinese, though it is the right shape (fast, free, already installed) if HAL ever narrows
  the feature to English-only no-op-safe correction.

Two things to do before committing, in this order — the order matters, because measuring the 9B on
the M4 Pro first only confirms a bad number that is already predictable:

1. ~~Sweep 3-4B general models on the M3 Ultra~~ **Done 2026-08-29 — nothing holds ~9/10.** See
   *Size ladder result* above. The fork is live: accept the 9B's latency, or fine-tune.
2. **Copy the 9B to the M4 Pro and measure there**, including cold load time and whether the
   model can be loaded on demand rather than kept resident (5 GB is a fifth of 24 GB). That number
   decides whether the interaction ships. If ~1.7 s is deemed too slow, the fallback is a LoRA
   fine-tune on a 4B base targeting exactly the three measured failure modes: Chinese typo
   correction, code-switch literal preservation, and English tense consistency.

If no 3-4B holds up, the choice becomes: accept ~1.7 s with strong progress feedback in the UI, or
fine-tune a small model — and only then does training become the plan.

### Product decision (2026-08-29): two providers — Apple or a user-owned model server

The backend abstraction is the protocol HAL speaks, **not where the user's model happens to run**.
A server on `127.0.0.1`, the M3 Ultra, or another reachable machine is the same provider.
HAL therefore exposes exactly two choices:

- **`appleOnDevice`** (default): Apple Foundation Models, zero server configuration.
- **`openAICompatible`**: any user-owned OpenAI-compatible `/v1/chat/completions` server —
  mlx_lm.server, LM Studio, Ollama, or llama.cpp — configured in Settings → AI Edit (URL and
  timeout). HAL never sends a model name: mlx_lm.server treats the field as "load this model", so
  the endpoint itself is the deployment. HAL sends only standard Chat Completions fields;
  model-specific chat template arguments belong to the user-owned server. For the recommended Qwen
  checkpoint, launch
  mlx_lm.server with `--chat-template-args '{"enable_thinking":false}'`; without it Qwen3.5 may
  answer in `reasoning` and leave `content` empty.

HAL does **not** ship, download, install, locate, or run third-party model weights. Qwen3.5-9B
MLX 4-bit is the measured recommendation for a server the user operates, not an embedded HAL
backend. Do not add a native MLX backend or model directory to the app unless this product boundary
is explicitly changed.

Implemented 2026-08-29 (builds clean, CoreTests/EngineTests/SettingsAppTests all pass, and the
shipping endpoint engine was smoke-tested live against the M3 server — output matched the eval
record byte-for-byte, deterministic):

- `Sources/Core/AIEditSettings.swift` — `AIEditProvider`, `AIEditSettings` (URL/timeout),
  stored in shared `Settings.json` via `UserSettings.aiEdit` (D28).
- `Sources/Panel/AIEditEngine.swift` — `AIEditEngine` protocol; `AppleEditEngine`
  (FoundationModels structured output, moved out of the panel); `EndpointRewriteEngine`
  (URLSession, wall-clock timeout task group, typed `AIEditError`s); `AIEditEngineFactory`.
- `AIEditPanel` now routes through the active engine; "local" wording removed.
- Settings → AI Edit tab (`AIEditSettingsView`) with the two-provider picker and endpoint
  fields. The complete Rephrase system prompt is editable there, persists in `Settings.json`, is
  shared by both providers, and can be reset to HAL's default. Its copy explicitly says that local
  and remote servers share one protocol and HAL manages
  neither models nor runtimes. When the server provider is selected, a recommended-baseline card
  points to `mlx-community/Qwen3.5-9B-MLX-4bit` and records the 9/10 score plus approximate disk/RAM
  cost. README carries the full external mlx_lm.server quick start; this is guidance only, not a
  downloader or bundled dependency.
- Tests: `Tests/CoreTests/AIEditSettingsTests.swift` (defaults, legacy decode, roundtrip, URL
  scheme validation).

### The vision tower is not part of the runtime cost

Qwen3.5-9B-MLX-4bit is a vision-language checkpoint (`Qwen3_5ForConditionalGeneration`, with both
`text_config` and `vision_config`), but **`mlx_lm` never instantiates the vision tower.** Verified
directly: the loaded model exposes only a `language_model` submodule, holds 927 parameter tensors and
zero vision tensors, and reports 5.038 GB of parameters — exactly the on-disk size of the
`language_model.*` weights.

The on-disk split is `language_model` 5.038 GB / `vision_tower` 0.912 GB (5.950 GB total, cleanly
separated by tensor-name prefix). So stripping the tower is easy and safe, but it buys **disk and
download size only, not RAM**: the 5.8 GB runtime peak is 5.04 GB of language weights plus roughly
0.77 GB of KV cache and activations. **Decided 2026-08-29: do not strip it.** A disk-only saving does not justify maintaining a custom
checkpoint. Do not re-raise this unless the runtime cost changes.

Fine-tuning a bilingual editing LoRA is only justified if no off-the-shelf general model in that
range holds up. Nothing measured so far argues for training.

One quality note that a fine-tune would have to beat: `correct-en-grammar` is failed by **all five**
models that attempt it, including a dedicated English GEC model trained on BEA-2019 + CoEdIT. The
shared miss is the uncountable noun in `too many works`.

## Is there a purpose-built model for this task? (searched 2026-08-29)

No. The six baselines measured above came from a preset list, so the Hugging Face model index was
searched directly rather than assumed. Search by name substring (`csc`, `corrector`, `gec`,
`proofread`, `grammar`, `rewriter`, `paraphrase`), by `zh`/`chinese` language tag across the
text-generation and text2text-generation pipelines, and by the relevant authors (`shibing624`,
`twnlp`, `iioSnail`). Note that Chinese query strings return almost nothing — HF's `search` matches
model ids, not descriptions — and that `polish` matches the Polish language and `edit` matches image
editors, which is why a naive search drowns in noise.

The specialist landscape splits into three disjoint groups, and **none of them spans HAL's task**:

- **Chinese spelling/grammar correction**: `shibing624/macbert4csc-base-chinese` (527k downloads,
  Apache-2.0, ~100M params, BERT fill-mask so same-length character correction only),
  `shibing624/mengzi-t5-base-chinese-correction`, `twnlp/ChineseErrorCorrector3-4B` and `4-4B`
  (the 4B is measured above at 1/2). Correction only, Chinese only.
- **English GEC**: many T5 derivatives. The strongest-looking ones are non-commercial
  (`vennify/t5-base-grammar-correction`, `pszemraj/flan-t5-large-grammar-synthesis`, both CC-BY-NC-SA).
- **English paraphrase/rewrite**: many T5 derivatives, plus `chartreuse-verte/prose-rewriter-1.7b/4b`
  (released 2026-08-21, English-only and **AGPL-3.0**, so unusable in a distributed app).

Nothing published covers Chinese + English + code-switched input with both correction and rephrase.
That combination comes from HAL being a Chinese IME used by a bilingual developer; it is not a public
dataset category, so no one has trained for it. **Do not repeat this search expecting a different
answer** — the useful direction is a small general model, or eventually a LoRA trained for exactly
this combination.

## M3 Ultra environment

Remote root: `/Users/ding/Developer/LLMs`

Existing remote virtual environment:

- `/Users/ding/Developer/LLMs/.venv`
- Python 3.13.13
- MLX 0.32.0
- mlx-lm 0.31.3
- Transformers 5.15.0
- sentencepiece 0.2.2
- Added on M3 Ultra only: torch 2.13.0, peft 0.20.0, psutil 7.2.2, accelerate 1.14.0
- MPS availability was verified as true.

Remote layout:

```text
/Users/ding/Developer/LLMs/HAL/
  baselines/
    general/
    multilingual-editing/
    english/
    chinese/
  training/
    datasets/
    runs/
    adapters/
    exports/
  manifests/
  eval/
```

The current eval files have been copied to `/Users/ding/Developer/LLMs/HAL/eval/`. If local evaluator code changes, re-sync only the relevant files.

## Baseline download (complete)

The downloader was copied to:

`/Users/ding/Developer/LLMs/HAL/manifests/download_baselines.py`

It is running remotely with:

```bash
/Users/ding/Developer/LLMs/.venv/bin/python \
  /Users/ding/Developer/LLMs/HAL/manifests/download_baselines.py \
  --aria2 /opt/homebrew/bin/aria2c
```

Last observed remote processes:

- Python downloader PID 88414
- aria2 PID 88851

**Every checkpoint is downloaded and checksum-verified**; no `.aria2` control files remain
anywhere under `baselines/`. Original six: Qwen3.5-9B-MLX-4bit 5.6 GB, mEdIT-XL-7B 13 GB (adapter +
base), CoEdIT-Large 2.9 GB, Qwen2.5-3B-GEC-v2 5.8 GB, ChineseErrorCorrector4-4B 7.5 GB. Added
2026-08-29 for the ladder and alternative hunt: Qwen3.5-0.8B/2B/4B-MLX-4bit, Qwen3-4B-Instruct-2507-4bit,
macbert4csc-base (391 MB), gemma-3-text-4b-it-4bit, Phi-4-mini-instruct-4bit, Qwen3.5-9B-3bit
(3.7 GB, quantized locally — see *Closing the remaining alternatives*), and the bf16 source
(18 GB, **kept** as the fine-tune base). The M4 Pro duplicate of the Qwen baseline was removed
earlier, after that download passed its checksums.

The first downloader run stopped silently after the mEdIT base without starting the last three
baselines, leaving no error and no log. Relaunching the identical command worked immediately, so the
cause was almost certainly SIGHUP when the launching session ended. The relaunch used
`nohup ... & disown` with output redirected to `manifests/download.log`; do the same in future.

Check without mutating:

```bash
rtk ssh m3u-ts 'ps ax -o pid,etime,%cpu,%mem,state,command | grep -E "download_baselines|aria2c" | grep -v grep; du -sh /Users/ding/Developer/LLMs/HAL/baselines/* 2>/dev/null; find /Users/ding/Developer/LLMs/HAL/baselines -name "*.aria2" -print 2>/dev/null'
```

The downloader pins Hugging Face revisions, writes metadata and aria2 manifests, uses published SHA-256 values, verifies completed files, and advances sequentially through (all six are complete):

1. `mlx-community/Qwen3.5-9B-MLX-4bit`
2. `grammarly/medit-xl` adapter
3. `MBZUAI/bactrian-x-llama-7b-merged` base for mEdIT
4. `grammarly/coedit-large`
5. `amiya/qwen2.5-3b-gec-v2`
6. `twnlp/ChineseErrorCorrector4-4B`

Expected aggregate size is roughly 36 GB. Use aria2 on the M3 Ultra for model downloads; do not fall back to duplicating them on the M4 Pro.

## Model roles and licensing

- Qwen3.5-9B MLX 4-bit: Apache-2.0, general-model baseline, both tasks/languages. **Measured 9/10 and
  recommended.** It is a vision-language checkpoint, but `mlx_lm` loads only the language model, so the
  vision tower costs 0.912 GB of disk and nothing at runtime.
- mEdIT-XL 7B: multilingual correction/paraphrase baseline; adapter plus Bactrian-X LLaMA base.
  Non-commercial/share-alike license; evaluation only, not a shipping candidate. **Measured 3/10 and
  disqualified on behavior too:** it translates code-switched English into Chinese and deletes content.
- CoEdIT-large 770M: English editing baseline. Non-commercial license; evaluation only. **Measured 1/4;
  strips backticks from inline code.**
- `amiya/qwen2.5-3b-gec-v2`: Apache-2.0 English correction specialist, exact system prompt is `Correct the grammar of the user text. Preserve meaning.` **Measured 2/3; 6.3 GB in bf16.**
- ChineseErrorCorrector4-4B: Apache-2.0 Chinese correction specialist; it emits `<think>...</think>`
  before the correction, and its instruction goes in the **system** role. **Measured 1/2; 8.4 GB.**

The benchmark has now run. Qwen3.5-9B-MLX-4bit is the only checkpoint that satisfies commercial use,
Chinese + English + mixed input, correction + rephrase, and native MLX deployment at once. The
specialists each cover at most two of the six roles and are individually weak even there, so they do
not compose into a cheaper alternative.

## Immediate next steps

Downloads, prompt confirmation, and baseline measurement are all done; see **Recommendation** above
for what the numbers argue for. What remains:

1. ~~Re-measure Qwen3.5-9B-MLX-4bit on the M4 Pro as a local endpoint~~ **Done 2026-08-29.** A
   temporary `mlx_lm.server` on `127.0.0.1:8901`, launched with
   `--chat-template-args '{"enable_thinking":false}'`, accepted the same standard Chat Completions
   body HAL sends. Three real requests returned HTTP 200 with replacement-only `content`: 1.37 s
   initial English correction, 1.01 s warm mixed-language correction, and 1.66 s warm English
   rephrase. The server was stopped after the smoke test. It remains external user infrastructure,
   not a third HAL provider. The remote M3 Ultra reference remains ~450-850 ms end-to-end through
   a 163 ms-RTT Tailscale relay (see *Product decision*).
2. ~~Add a text-only 4-bit general model~~ **Done 2026-08-29** — the 0.8B/2B/4B ladder plus
   Qwen3-4B-Instruct all scored below the bar (see *Size ladder result*). macbert4csc measured
   2/2 on its slice but 14/22 on the dedicated CSC probe, rewriting proper nouns and corrupting
   code-switched English — disqualified (see *Size ladder result*). Gemma 3 4B, Phi-4-mini, and a
   locally-quantized 9B-3bit were also measured and closed the same day (see *Closing the remaining
   alternatives*). A fine-tune is now the only path below 9B.
3. Model prompt formats are **all confirmed from primary documentation** — do not re-guess them:
   - mEdIT: template `### Instruction:\n<task>\n### Input:\n<text>\n### Output:\n\n`, exactly what
     the runner emits; LoRA over `MBZUAI/bactrian-x-llama-7b-merged`, matching the downloaded base.
   - CoEdIT's documented task set is `Fix grammatical errors in this sentence`, `Make this text
     coherent`, `Rewrite to make this easier to understand`, `Paraphrase this`, `Write this more
     formally`, `Write in a more neutral way`. There is no "concise and direct" task, so the invented
     string that was there before was replaced by the simplification one, which is what HAL's
     `rephrase` actually asks for.
   - mEdIT's English simplification string is not published, so the candidates were probed on the
     checkpoint: `Paraphrase this` is inert (echoes the input), while `Rewrite to make this easier to
     understand`, `Write a simple version of the sentence`, and `Simplify this sentence` all activate
     rewriting and produce byte-identical output. The CoEdIT string is used for both profiles.
   - ChineseErrorCorrector4-4B: its card puts `假如你是一名专业的纠错专家，请分析输入句子的语法错误类型和修改原因，并只输出纠正后的语句`
     in the **system** role with the bare sentence as the user turn. The runner previously concatenated
     an invented instruction into a single user message; that is fixed. It reasons inside `<think>`
     first, so this profile's generation budget is 1024 tokens, not 192.
   - `amiya/qwen2.5-3b-gec-v2`: system prompt `Correct the grammar of the user text. Preserve meaning.`
     matches the card verbatim, and the card's own example loads it with `mlx_lm.load`, confirming the
     MLX backend choice. Its card notes it was scored with post-processing that strips BEA tokenization
     artifacts; the eval deliberately does not post-process, since HAL would not either.
4. If the user chooses to run the recommended checkpoint on the M4 Pro, keep its model and runtime
   outside HAL and point the existing OpenAI-compatible provider at that server.
5. Update this handoff file after each completed stage if the current agent is still active.

## Risks / likely troubleshooting points

- mEdIT's older Bactrian/LLaMA base may expose Transformers 5.15 or PEFT 0.20 compatibility issues.
- The Transformers runner measures total latency but not TTFT, so its latency column is not directly
  comparable with the MLX runner's warm TTFT. Compare total-ms across backends, or add streaming.
- `amiya/qwen2.5-3b-gec-v2` is confirmed loadable by `mlx_lm`: its config is `model_type: qwen2` /
  `Qwen2ForCausalLM` in plain safetensors, and its card's own usage example calls `mlx_lm.load`. The
  directory name says MLX-BF16 but the repo is not pre-quantized; that is harmless.
- **The downloader dies with the session that launched it.** The first run stopped silently after the
  mEdIT base with no error and no log, having never started the last three baselines; relaunching the
  exact same command worked immediately, so it was almost certainly SIGHUP when the previous agent's
  session ended rather than anything wrong with the repos. Launch it with `nohup ... & disown` and
  redirect to a log, as the current run does (`manifests/download.log`).
- The aria2 log is enormous because it records full signed CDN redirect URLs. Never `cat` it; filter
  with `grep -aoE` for the downloader's own `[n/N] name <- repo` and `revision ...` lines.
- Never treat non-commercial mEdIT/CoEdIT weights as product candidates.

## Suggested skills for the next agent

- `diagnose`: use if a download, model load, MPS execution, adapter attachment, prompt format, or performance run fails; follow reproduce → minimise → instrument → fix.
- `swiftui-expert-skill`: use when changing or reviewing HAL's selection/shortcut/window interaction or its settings UI.
- `tdd`: use only if the user asks for test-first implementation of the production integration; the current work is empirical model evaluation.

## Completion definition for this phase

This baseline phase is complete when all selected checkpoints are checksum-verified on the M3 Ultra, every supported eval slice has a saved result, model-specific prompts are confirmed from primary model documentation, the M4 Pro is clean of baseline/training assets, and there is an evidence-backed recommendation for either an existing deployable checkpoint or the exact fine-tuning target.

All five criteria are met as of 2026-08-29:

- Fifteen checkpoints downloaded and checksum-verified; no `.aria2` controls remain.
- Six saved reports in `Evals/results/`, all on suite v5.

Two things changed after that: the suite is now **v6** (all 14 reports regenerated under it; see
*Suite v6*), and the selection-rewrite prototype shipped with two providers (see *Product decision*)
— `Sources/Core/AIEditSettings.swift`, `Sources/Panel/AIEditEngine.swift`,
`Sources/SettingsApp/TabViews/AIEditSettingsView.swift`, and
`Tests/CoreTests/AIEditSettingsTests.swift` are new repository artifacts, with the shared
`UserSettings.aiEdit` field and an "AI Edit" tab in the control center. Treat server process
state as ephemeral and verify it before testing; the temporary M4 Pro server was intentionally
stopped after the smoke test.

- Every model-specific prompt confirmed from its own card (and mEdIT's unpublished simplification
  string resolved by probing the checkpoint directly).
- M4 Pro holds only the selected Qwen model directory plus `.DS_Store` under `Developer/LLMs`, with
  no training/PyTorch environment installed; the shared runtime remains under `Developer/MLX`.
- Recommendation recorded above, with its two follow-ups.

The phase deliverable is done. The two follow-ups under **Recommendation** — re-measuring on the M4
Pro and trying a smaller text-only general model — are the start of the next phase, not unfinished
work from this one.
