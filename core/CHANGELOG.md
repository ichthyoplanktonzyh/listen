# Changelog

## Unreleased

- 2026-06-25 CST: 修复桌面播放器播放位置不上报导致的进度条与字幕同步停滞。
  `DesktopPlayerAdapter` 恢复 100ms position polling，并通过
  `VideoPlayerController.position` 主动触发 fvp `getPosition()`，避免只读取缓存
  `value.position`。position stream 仅由主动 polling/seek/stop 发布，避免
  `VideoPlayerController` 的 buffering/state listener 用旧缓存 position 覆盖真实位置。
  切换媒体、播放失败与 dispose 会取消旧 timer，seek/stop 后立即发布当前位置；
  增加 generation 校验防止旧播放器异步结果污染新媒体。修复 Store-backed
  Player/Subtitle/Learning controllers 未转发 ChangeNotifier 通知的问题，确保
  `main.dart` 的 `ListenableBuilder` 在 position/cue 更新时重建进度条与字幕层。
  增加 controller 通知回归测试。验证: `flutter analyze` 0 issues,
  `flutter test` 65/65 passed, `flutter build macos --debug` passed。

- 2026-06-25 CST: Phase 2.10 Steps 2-6 — fb-espeak CTC phoneme provider 选型与集成。
  (1) **Step 2 补充 benchmark**: fb-espeak PER=30.5%（Apache 2.0）选定；
  vitouphy PER=19.5% 因 TIMIT 许可阻塞被排除。
  (2) **Step 3 生产管线集成**:
  - `DetectedPhone` 新增 `display_ipa` 字段，UI 以 IPA 为主显示
  - `speech-analysis/phone_recognition.rs`: IPA→ARPAbet 映射 + sidecar 封装
  - `phonetic_fixture.rs`: `build_ctc_phonetic_analysis()` 真实 CTC 推理路径
  - `api-http/phonetic_analysis.rs`: CTC provider 注册 + model seed + 执行分派
  - `scripts/wav2vec2-phoneme-cli.py`: Python sidecar（CTC decode + logit confidence）
  - `scripts/setup-phoneme-model.sh`: 命令行模型下载脚本
  - `scripts/download-phoneme-model.py`: 后台模型下载 sidecar（JSON 进度输出）
  - Flutter `diagnosis_card.dart`: IPA 优先显示
  - Flutter `phonetic_analysis_ui.dart`: 模型下载按钮 + 进度条（App 内一键下载）
  - `install_model` API: 后台 spawn Python 下载进程，带进度回报和状态更新
  - Flutter `api_service.dart`: 新增 `installPhoneticAnalysisModel()` API 调用
  (3) **Step 4 finding 升级**: 隐式完成（现有 alignment + findings 管线已支持真实 confidence）
  (4) **Step 5 端到端验证**: 待下载模型后测试
  (5) **Step 6 回归**: Rust 299 tests + Flutter 64 tests 全部通过
  使用方式: App 设置 → Audio analysis models → 点击下载按钮；或命令行 `./scripts/setup-phoneme-model.sh`。

- 2026-06-25 CST: Phase 2.11 Steps 1-3 完成 + Phase 2.10 研究计划。
  (1) **Step 3 — domain lib.rs 拆分**: 从 1317 行缩减到 194 行。新增 13 个领域模块
  (media / subtitle / pronunciation / word_timing / chunk_timeline / phone_timeline /
  lltimeline / phonetic_analysis / learning / dictionary / transcription / vocabulary /
  diagnosis)，测试下沉到各自模块。
  (2) **Step 1 — 能力矩阵 API**: Phase 2.12 已完成（`_isHan` 替换为 profile 驱动门控，
  `/v1/languages` + `/v1/languages/{code}/profile` 端点已就位）。
  (3) **Step 2 — 学习语言来源**: AppSettings 新增 `learningLanguage` 字段（默认 `auto`），
  优先级链：用户设置 > 字幕轨语言 > `en` fallback。设置对话框顶部新增学习语言下拉框。
  中英双语 localization。
  (4) **Phase 2.10 研究计划**: 编写 `2.10-RESEARCH-PLAN.md`，盘点已有基础设施
  (PhoneTimeline / MFA / ZIPA / 评估 harness)，规划 4 阶段研究流程
  (环境验证 → 候选 benchmark → 选型决策 → 结果记录)。
  (5) **验证**: 294 cargo tests + 64 flutter tests passed, `flutter analyze` 0 issues。

- 2026-06-25 CST: Phase 2.12 — UI State Management Refactoring (Flutter).
  (1) **Store\<T\> 基础设施**: 通用响应式状态容器，支持 `select()` 细粒度字段级
  ValueNotifier 订阅。新增 StoreBuilder/StoreBuilder2 声明式选择器 Widget。
  (2) **Typed domain models**: 新增 `models/types.dart`，提供 WordProfile、WordDetail、
  Diagnosis、PhraseCandidate 等 7 个 typed 类替代 `Map<String, dynamic>`。
  (3) **Controller 迁移**: PlayerController / SubtitleController / LearningController
  内部迁移到 Store，保留 ChangeNotifier 向后兼容。
  (4) **布局提取**: SubtitleOverlay（原 _playerSurface()）和 SidePanel（原 _sidePanel()）
  提取为独立 Widget 文件，减少 main.dart 的构建方法复杂度。
  (5) **验证**: `dart analyze` 0 issues, `flutter test` 64/64 passed。
  分支: `refactor/ui-state-management`。规划文档:
  `.planning/phases/2.12-ui-state-management-refactoring/`

- 2026-06-24 CST: Phase 2.9 closeout + Phase 2.10/2.11 planning.
  (1) **Phase 2.9 收口**: 生产管线多语言解耦完成。2.9-CLOSEOUT.md 记录 Rust 侧
  (AlignerRegistry/语言传播/CJK 分词) + Python 侧 (mlx-whisper/jieba/M:N 对齐)
  全部交付、中文端到端验证结果和设计决策。
  (2) **残留项总览**: 新增 `.planning/DEFERRED-ITEMS.md`，汇总 Phase 2.1–2.9 全部
  残留/延后项，按 P1(英语语流+架构)/P2(小项)/P3(中文/日语) 分级。
  (3) **Phase 2.10 规划**: English Real Speech Analysis — 选出 phone-level provider，
  让英语语流分析从文本预测升级为音频检测。候选 MFA/ZIPA/Wav2IPA/Allosaurus。
  (4) **Phase 2.11 规划**: Architecture Seam Consolidation — 能力矩阵 API、学习语言
  来源、domain 拆分、L1 诊断 seam、听觉锚定准备。Step 1–3 可与 2.10 并行。

- 2026-06-24 CST: Chinese word-level tokenization + mlx-whisper ASR integration.
  (1) **jieba word segmentation**: `tokenize()` in `lltimeline_common.py` now uses
  jieba for Chinese word segmentation instead of character-level splitting. "今天"
  is one token (not "今"+"天"), producing natural word-boundary highlights during
  karaoke playback. Falls back to per-character if jieba unavailable. English
  tokenization unchanged.
  (2) **ASR-to-token alignment**: new `align_asr_words_to_tokens()` handles M:N
  mapping between ASR word boundaries and jieba token boundaries via character-
  position alignment. Merges timing from multiple ASR words when they compose one
  jieba token (e.g. ASR ["上","海"] -> jieba "上海").
  (3) **mlx-whisper integration**: `mlx-whisper-transcribe.py` standalone script
  wrapping `mlx_whisper.transcribe()` with WhisperX-compatible JSON output.
  `production_pipeline.py` gains `--asr` flag (`whisperx`/`mlx-whisper`) and
  `resolve_mlx_whisper_command()`. ~7.5x faster than WhisperX CPU on Apple Silicon.
  (4) Quality comparison on 8-min Chinese audio: mlx-whisper avg_confidence 0.954
  vs WhisperX 0.953, fewer overlaps (2 vs 4), comparable word coverage.

- 2026-06-24 CST: Phase 2.9 — Production multilingual decoupling + pluggable model
  architecture.
  (1) **Pluggable aligner registry**: new `aligners/` package with `AlignerPlugin`
  base class, `MfaAligner` and `MmsFaAligner` plugins extracted from
  `production_pipeline.py`. Registry provides `register()`, `get_aligner()`,
  `available_aligners(language)`, `all_aligners()`. Adding a new aligner (e.g.
  Qwen3-ForcedAligner) requires one plugin file + one `register()` call.
  `production_pipeline.py` dispatch rewritten to use registry — no more if/elif.
  New `list-aligners` subcommand; `doctor` now reports registered aligner status.
  (2) **CJK tokenizer**: `lltimeline_common.py` tokenizer extended to emit each
  CJK character (Chinese, Japanese hiragana/katakana) as an individual word token.
  English tokenization unchanged. 11 new tests for CJK + regression.
  (3) **Language propagation**: `--language` parameter flows through entire
  production chain. `post_aligner_chain()` filters aligners by language: Chinese
  skips MFA (English-only) and uses MMS_FA directly. `apply-mfa-alignment` and
  `apply-mms-fa-alignment` subcommands accept `--language`.
  (4) **CJK chunk partition (Rust)**: `chunk_partition.rs` strong punctuation
  detection extended with CJK sentence-final punctuation (U+3002, U+FF1F, etc.).
  `build_chunk` text joining uses no separator for all-CJK chunks. `is_cjk_char`
  helper covers CJK Unified Ideographs, hiragana, katakana.
  (5) **Rust pipeline language propagation**: `ForcedAlignRequest` gains optional
  `language` field. `refine_transcription_word_timelines()` accepts and propagates
  language from `detected_language` through to the forced-align sidecar.
  (6) **GUI**: post-aligner dropdown dynamically populated from aligner registry.
  Verified: all 24 Python tests pass, all 294+ Rust workspace tests pass, clippy
  clean (no new warnings).

- 2026-06-24 CST: Phase 2.9 planning — Production engine multilingual decoupling.
  Created CONTEXT and PLAN docs identifying 5 English binding points in the
  production pipeline: language propagation, forced alignment language-aware
  degradation, pronunciation analysis provider-ization, text chunk language
  dispatch, and Chinese end-to-end validation. Consumer-side is now
  language-agnostic (Phase 2.6-2.8); this phase targets the production side.
  Updated STATE to reflect Phase 2.8 completion and Phase 2.9 planning.

- 2026-06-24 CST: Phase 2.8 — Token timing alignment + rhythm-aware estimation.
  (1) **Character-level time alignment**: `asr_timing.rs` rewritten to perform
  character-level time interpolation (`align_words_to_tokens`) when whisper BPE
  word count mismatches app tokenizer word count (common for CJK where BPE merges
  characters differently from jieba/lindera). English 1:1 direct path unchanged
  (`extract_direct`). New `TimingSource::AsrAligned` variant for interpolated
  timings. `MergedWord` now carries `text` for alignment computation.
  (2) **Rhythm-aware estimation fallback**: `estimate_word_timings_with_rhythm`
  selects strategy from `LanguageLearningProfile.rhythm_prosody`: `CharWeight`
  for stress-timed (en, clamped char count, `v1`), `SyllableEqual` for
  syllable-timed (zh, equal CJK char weight, `v2-syllable`), `MoraCount` for
  mora-timed (ja, kana/kanji mora counting with small-kana exclusion,
  `v2-mora`). `pronunciation.rs` wired to pass profile rhythm.
  (3) **Public alignment API**: `align_timings_to_tokens` exposed for lltimeline
  import and future re-tokenize scenarios. `word_timing_cache_is_usable` updated
  to accept `v2-*` provider versions.
  (4) **Match arm updates**: `AsrAligned` added to `chunk_partition.rs`
  `acoustic_gap_threshold` (same threshold as `AsrReported`) and
  `application/lib.rs` `timing_priority` (priority 2, same as `AsrReported`).
  Verified: 294 workspace tests pass (7 new: Chinese BPE alignment, English
  direct mapping regression, character time distribution, public alignment API,
  syllable-timed equal weight, mora counting, default rhythm regression),
  clippy clean.

- 2026-06-24 CST: Phase 2.7 — Pronunciation provider dispatch + language-agnostic
  timing/chunk. (1) **PronunciationProvider trait**: new dispatch trait in
  `providers.rs` with `analyze_sentence`, `lookup_word`, `rule_catalog` methods.
  `EnglishPronunciationProvider` wraps `speech_analysis` crate;
  `ChinesePronunciationProvider` produces pinyin from CC-CEDICT with per-character
  fallback. Providers registered in `ApiState::new`, dispatched by
  `sentence_language()` match against `info().languages`. (2) **pronunciation.rs
  rewrite**: `analyze_pronunciation`, `lookup_pronunciation`, `pronunciation_rules`
  all route through registered providers. Cache validation keyed on provider
  id/version. `analyze_pronunciation_track` uses `filter_map(.ok())` to skip
  sentences that fail (e.g. punctuation-only). API routes `/v1/pronunciation/lookup`
  and `/v1/pronunciation/rules` accept `language` query parameter (default "en").
  (3) **Chinese pinyin display**: Chinese subtitles now show tone-marked pinyin
  below the subtitle line via existing `display_ipa` rendering path — no Flutter
  code change needed. (4) **Timing/chunk language-agnostic**: `estimate_word_timings`
  (character-weighted time distribution) and acoustic chunk detection (gap-based)
  confirmed as language-agnostic algorithms. Chinese profile upgraded from
  `Unsupported` to `Supported` for `word_timeline` and `chunk_timeline`. Only
  `detect_text_chunks` (COCA n-gram / PHRASE List) remains English-gated.
  (5) **phonetic_fixture.rs**: non-English skips canonical phone alignment
  (empty canonical list). Verified: 286 workspace tests pass, user confirmed
  Chinese pinyin + word tracking + chunk highlight working, English regression clean.

- 2026-06-23 CST: Phase 2.6 extension — capability matrix API, language selection
  UI, and per-character meaning breakdown. Three user-visible features:
  (1) **Capability matrix API**: `GET /v1/languages` lists supported languages,
  `GET /v1/languages/{code}/profile` returns the full `LanguageLearningProfile`
  (tokenization, dictionary, pronunciation capabilities). Flutter API service
  wired with `listLanguages()` and `lookupLanguageProfile()`.
  (2) **Language selection UI**: `PATCH /v1/subtitles/{track_id}/language` lets
  users override auto-detected language on a subtitle track. Backend follows the
  `set_track_status` pattern (trait → sqlite UPDATE → return updated track).
  `_LanguageChip` widget in the subtitle resource tile shows current language with
  a popup menu; changing language refreshes word/phrase profiles for the active
  track.
  (3) **Per-character meaning**: `DictionaryLookup` extended with
  `character_breakdowns: Vec<CharacterBreakdown>` (character + phonetic + meaning).
  `ChineseDictionaryProvider::resolve()` splits multi-character words and does
  per-char CC-CEDICT/seed lookups to populate meanings. Word learning panel reads
  backend breakdowns first, falls back to client-side syllable splitting. Meaning
  row renders below pinyin in small text. Gate changed from hardcoded
  `profile['language'] == 'zh'` to profile-driven
  `pronunciation == 'zh.pinyin'`. `character_breakdowns` uses
  `skip_serializing_if = "Vec::is_empty"` for backward compatibility with cached
  dictionary entries. Verified: workspace 250 tests, flutter 64, contracts pass,
  no-default-features clean, en/zh/ja regression baseline unchanged.

- 2026-06-23 15:28 CST: Promoted Japanese from a guard fixture to a real language
  (lindera morphological tokenization + JMdict/EDICT2 dictionary), empirically
  validating the dispatch-layer fix from the earlier falsification spike. Added
  `JapaneseTokenizer` with lindera 4.0 + embedded IPADIC behind an opt-in
  `lindera` feature (default off — not vendored offline; offline/default builds
  use character-level fallback). Added `JapaneseDictionaryProvider` reading
  EDICT2 line format with a 15-word seed fallback, registered in the api-http
  dictionary stack. The ja profile now declares `ja.morphological` tokenization,
  `jmdict` dictionary, and `ja.kana` pronunciation — all routed by profile and
  provider with zero edits to dispatch core, `detect_language`, per-char gating,
  or diagnosis. This empirically confirms ROADMAP §14.11: adding a real
  Han-script-sharing language required only profile + provider + registration.
  Surfaced a deferred seam: `core.surface` normalization does not unify Japanese
  inflections (食べる/食べた) because Fix 4 re-derives the normalized key from
  surface text, discarding lindera's base form — base-form unification needs
  the provider-supplied opaque key to flow through `tokenize()`. Updated
  maintenance checklist to require minute-precision changelog timestamps.
  Verified: workspace 286 tests, `--features lindera` morphological proof,
  `--no-default-features` 24 tests, flutter 64, clippy clean, contracts pass;
  en/zh regression baseline unchanged.

- 2026-06-23 09:07:10 CST: Closed out Phase 2.6 (step 7). Consolidated the
  bilingual regression into an explicit set and added a crown-jewel capstone test
  proving English and Chinese vocabularies and their source snapshots stay
  language-isolated (a Chinese word never appears in the English vocabulary and
  vice versa). Wrote `2.6-CLOSEOUT.md` and updated STATE / ROADMAP / REQUIREMENTS
  to mark Phase 2.6 complete for the English + Chinese acceptance set. LANG-001/
  002/003/005/006/007/008/010 are implemented; LANG-004 (auditory-anchored
  observation) and LANG-009 (L1 diagnosis seam) remain reserved seams by design,
  as does non-English audio → listening-unit production (a separate future
  program). English behavior stayed the regression baseline throughout. Verified
  with the full workspace suite (279 tests), flutter analyze/test (63), and
  validate-contracts.

- 2026-06-22 21:49:03 CST: Added the Phase 2.6 Chinese learning panel and
  language-aware diagnosis (step 6). Sentence diagnosis now layers the learning
  language's listening factors onto the recognition barrier as namespaced,
  per-profile *possibilities* (zh: tone_confusion/word_boundary/homophone/
  neutral_tone/tone_sandhi; en: weak_form/linking/...), explicitly framed as
  factors to consider rather than detections from audio — there is no Chinese
  audio analysis yet (deferred per ADR 0012). The decoration lives in the
  application layer (`diagnose_sentence`), keeping `diagnosis-core` language-
  agnostic; a new `reasons` field on `DiagnosisHint` carries them. The word panel
  gained a per-character breakdown for multi-character Han words, aligning each
  character with its pinyin syllable (字 → 拼音/声调) — derived from the dictionary
  phonetic with no extra lookups and gated on script, not language. The diagnosis
  card renders reasons localized with a clean fallback for unknown reasons.
  Verified with new application and widget tests; English diagnosis stays the
  regression baseline.

- 2026-06-22 21:09:21 CST: Integrated CC-CEDICT as the real Chinese dictionary
  source, replacing the 25-word built-in stub with the full ~120k-entry community
  dictionary while keeping the seed as an offline fallback. `ChineseDictionaryProvider`
  now reads an installed CC-CEDICT `.u8` file (cached, mirroring the ECDICT loader),
  parsing `Traditional Simplified [pin1 yin1] /glosses/` and converting tone-numbered
  pinyin to tone marks (handling `u:`→`ü`, neutral tone, capitalized proper nouns, and
  the standard a/e/ou/last-vowel placement); both simplified and traditional headwords
  resolve. Registered CC-CEDICT in the learning-resource catalog with a pinned mirror
  commit and verified SHA-256 (CC-BY-SA 4.0), so it installs like ECDICT/CMUdict.
  Known limitation: words with multiple readings keep the first entry. Verified with
  new parser/tone tests and a throwaway smoke check against the real 118k-entry file.
- 2026-06-22 21:00:00 CST: Fixed two backend `language=en` hardcodes that Step 4
  (client-scoped) missed, so Chinese diagnosis and phrase detection use the sentence's
  actual track language. Added a `sentence_track_language` repository method (joining
  `subtitle_sentences` to `subtitle_tracks`) and a `sentence_language` application
  helper (track language, else `en`); `diagnose_sentence` and `phrase_candidates` now
  resolve through it instead of assuming English. Previously a Chinese sentence's
  diagnosis read English word profiles and ignored the user's Chinese statuses. Added a
  test proving zh diagnosis reads zh profiles and en does not leak.
- 2026-06-22 20:20:02 CST: Added the Phase 2.6 Chinese dictionary and
  pronunciation provider (step 5). Introduced a built-in `ChineseDictionaryProvider`
  in `dictionary-provider` (`supported_languages: ["zh"]`) seeded with common
  words/characters, each carrying tone-marked pinyin (the `zh` profile's
  `zh.pinyin`/`zh.tone`) and a short gloss, and registered it in the api-http
  dictionary stack. The existing `lookup_dictionary` dispatch already routes by
  `supported_languages`, so clicking a Chinese token now shows pinyin + meaning
  while English providers are skipped; unknown words degrade to no result without
  affecting playback or word status. Pinyin is delivered through the dictionary
  phonetics, and the word-learning panel now hides the IPA pronunciation section
  when no variant has real content (Chinese has no IPA provider). Seed data is a
  placeholder for a licensed CC-CEDICT-scale source behind the same interface.
  Verified with new provider, language-routing, and Flutter checks.
- 2026-06-22 17:30:00 CST: Removed the Phase 2.6 `language=en` hardcoding (step 4)
  so the learning language comes from the active subtitle track instead of a
  constant. `subtitle_core::import` now detects the language from the subtitle
  script when the caller does not declare one (Han -> zh, else en) and uses it for
  both tokenization and the stored `track.language`; a declared language still
  wins and English tokenization stays the regression baseline. The Flutter
  `SubtitleTrack` model reads the language the core already serialized, and a
  `_learningLanguage` resolver (active primary track language, `en` fallback)
  threads it through the vocabulary, dictionary, word-profile, source-snapshot and
  phrase paths and `_sourceFor`. The `LocalApi` vocabulary/dictionary/lexical
  methods take a required language; also dropped the dead `normalizeLexical`
  client wrapper. Verified with workspace tests, flutter analyze/test and
  validate-contracts.
- 2026-06-22 16:06:45 CST: Added the Phase 2.6 LexicalUnit model (step 3) in
  `domain` (`lexical_unit.rs`): a language-relative vocabulary learning object
  whose identity is two orthogonal axes — granularity
  (core.char/word/phrase/morpheme) x normalization
  (core.surface/lemma/citation/root) — plus an opaque normalized_key with no
  substring/affix assumption (ADR 0012 R2). Word-granularity identity stays
  `language:normalized_key` so existing English WordProfile ids remain readable;
  non-word granularities namespace the key so Chinese characters never pollute
  Chinese words or English lemmas. English normalizes to a lowercased lemma,
  Chinese keeps the surface form (no lemma assumed), and a
  baseline_normalized_key helper leaves real citation/root normalization to
  per-language providers. Verified with new domain tests and clippy.
- 2026-06-22 16:00:04 CST: Implemented the Phase 2.6 language-aware
  tokenization foundation (steps 1-2 of the multilingual learning phase).
  Added a `LanguageLearningProfile` capability matrix in `domain`
  (`language_profile.rs`) with open namespaced-string `kind` fields (per ADR
  0012 R0), English/Chinese/degraded profiles, and a `profile_for` resolver
  that maps regional variants to their base language and degrades unknown
  languages cleanly; the global `WordStatus` enum is left untouched as the
  language invariant. Replaced the single `tokenize_english` call path in
  `subtitle-core` with a `Tokenizer` trait and a profile-driven
  `tokenize(language, text)` dispatch: English keeps the existing baseline,
  unknown/absent languages degrade to whitespace, and `zh.word_segmentation`
  routes to a Chinese tokenizer. Chinese tokenization uses jieba-rs 0.7.4 word
  segmentation by default (`jieba` feature), with a character-level fallback
  under `--no-default-features`; both preserve original character spans and
  handle mixed CJK/Latin/number runs. Verified with the full workspace test
  suite (255 tests), the no-default-features fallback path, and clippy; the
  English tokenization path is unchanged. jieba-rs is now pinned in Cargo.lock.
- 2026-06-22 11:59:40 CST: Documented the multilingual listening-learning
  product direction across the strategic docs after the Phase 2.5.5 validation,
  following the `.planning/MAINTENANCE.md` rules. Updated PROJECT.md (vision is
  now multilingual and listening-first; new §4.4 principles, §10.9 concepts, and
  §15.5 Milestone 2 multilingual direction). Added REQUIREMENTS.md section 18.4
  with LANG-001..LANG-010 (capability matrix/profile, language-aware
  tokenization, LexicalUnit granularity×normalization, ListeningUnit view plus
  listening-anchored observation, `language=en` removal, Chinese
  dictionary/pinyin provider, Chinese learning panel/diagnosis, comprehension-axis
  invariant with per-profile diagnosis reasons, L1 seam, open kind taxonomy) and
  a release-matrix row; noted TXT-001 is generalized by LANG-002. Added
  ROADMAP.md §14.11 multilingual workstream under Milestone 2. Recorded the
  architecture decision as ADR 0012 and added forward-looking multilingual
  sections to codebase/ARCHITECTURE.md and codebase/DATA-MODEL.md. No code
  changed; English behavior remains the regression baseline.
- 2026-06-22 11:45:56 CST: Added Phase 2.5.5 Language Learning Abstraction
  Validation as a design/validation phase inserted before Phase 2.6
  (Multilingual Learning Foundation), mirroring the earlier 2.3.5-before-2.4
  pattern. Validated the multilingual learning abstraction against real
  second-language-acquisition research rather than engineering aesthetics:
  the meaning-vs-sound diagnosis axis maps to Field's decoding-vs-meaning
  listening model, language-specific listening units to Cutler's
  cross-linguistic segmentation (English stress, French syllable, Japanese
  mora, Mandarin syllable/tone), the LexicalUnit to Nation's word family,
  chunks to Wray's formulaic language, lexical competition to the
  Marslen-Wilson cohort model, and L1 filtering of L2 perception to Best
  (PAM) and Flege (SLM). Locked the comprehension axis as the single language
  invariant: the global vocabulary status enum stays language-agnostic and
  reusable, while diagnosis reason taxonomy becomes per-profile and
  extensible. Added an L1->L2 diagnosis seam (nullable, unused in v1, no
  schema change). Ran a typological falsification with Japanese and Arabic
  that forced three abstraction revisions: R0 `kind` taxonomies must be open
  namespaced strings with clean degradation instead of exhaustive enums
  (Japanese mora, Arabic templatic morphology fall outside the original
  closed sets); R1 listening observations must be able to anchor to a
  `ListeningUnit`, not only a `LexicalUnit`, so tone/pitch minimal-pair
  failures have a home; R2 `normalized_key` must be provider-opaque because
  Arabic non-concatenative roots (k-t-b) are not surface substrings. Scoped
  the architecture to the top-15 learning languages with typological
  clustering and flagged Hindi's abugida as the next writing-system probe.
  Fed the validated foundation back into Phase 2.6 as seven implementation
  constraints and resolved two of its open questions. No production code
  changed; deliverables are design docs (SLA foundation, falsification,
  closeout) plus updates to STATE and the Phase 2.6 plan.
- 2026-06-22 10:30:00 CST: Updated `validate-contracts.sh` MFA strategy
  assertion from `--strategy align-one` to `--strategy align` to match the new
  batch-align default. All 16 Python tests and the full contract validation
  suite now pass with the updated defaults.
- 2026-06-22 09:15:00 CST: Switched the MFA default strategy from `align-one`
  to batch `align`. The `align-one` strategy spawned a separate `mfa
  align_one` process per segment, incurring ~11 s of model-loading overhead
  each time; for 115 segments this meant 210 s total. Batch `align` loads the
  model once and aligns all segments in a single process (58 s, 3.6× faster)
  with identical output. The original reason for `align-one` was an MFA 3.3.9
  SQLite export bug (empty interval CSVs); re-testing confirmed the bug is no
  longer present. `align-one` is kept as `--mfa-strategy align-one` fallback.
- 2026-06-22 09:04:00 CST: Completed Phase 2.5 Sound Pattern /
  PhoneTimeline. PhoneTimeline is now a first-class resource with SQLite schema
  v14, candidate/active/archive lifecycle APIs, LLTimeline import/export
  round-tripping, OpenAPI coverage, and desktop resource management. Completed
  phonetic analyses now bridge to PhoneTimeline candidates; the desktop app can
  show, activate, archive, delete, and consume active PhoneTimeline resources
  for current-phone highlighting and diagnostic sound-pattern display, while
  falling back to legacy phonetic analyses when no active resource exists.
  Added the Phase 2.5 provider benchmark gate and recorded the no-release
  provider decision: research fixtures and candidate models stay out of the
  default product path until benchmark, provenance, and license gates pass.
- 2026-06-21 21:16:48 CST: Completed Phase 2.4 ChunkTimeline generation and
  consumption. Chunk boundaries are now persisted as first-class
  `ChunkTimeline` resources with SQLite schema v13, active/candidate/archive
  lifecycle APIs, LLTimeline import/export round-tripping, and OpenAPI
  coverage. The desktop app now lists ChunkTimeline candidates in Subtitle
  Resources, can generate/activate/archive/delete them, prioritizes the active
  ChunkTimeline for playback, and adds chunk navigation, click-to-seek, loop
  current chunk, and expanded chunk practice controls. Updated Phase 2.4
  closeout docs. Verified with `cargo test --workspace --quiet`,
  `flutter analyze`, `flutter test`, `./scripts/validate-contracts.sh`, and
  `git diff --check`.
- 2026-06-21 10:19:08 CST: Implemented the first Phase 2.3 manual
  WordTimeline review pass in the desktop app. Manual Review now opens a
  sentence-level inspector backed by a full cloned WordTimeline draft, supports
  integer-millisecond start/end editing with ±10ms/±50ms controls, plays the
  current sentence or word using draft boundaries, and saves a full
  `created_by=user` / `status=active` user-adjusted WordTimeline revision.
  Added complete Flutter WordTimeline read/create client methods, millisecond
  payload serialization, draft validation/dirty tracking, and focused tests.
  Verified with `flutter analyze` and `flutter test` (59 tests passed).
- 2026-06-21 10:31:53 CST: Made Phase 2.3 Manual Review discoverable as a
  labeled button in the Timeline Resource Summary instead of an icon-only
  action, and fixed word-click navigation so selecting a subtitle word opens the
  Word Learning side panel rather than the Subtitle Resources panel. Verified
  with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 10:39:53 CST: Fixed Manual Review playback verification leaking
  its temporary source loop after closing the dialog. The review flow now
  restores the previous source loop state when the inspector exits, so using
  Play sentence / Play word no longer leaves normal playback looping the review
  segment. Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 10:51:01 CST: Reworked subtitle resource export so the existing
  Export action asks for an output format. Users can now choose SRT or
  LLTimeline JSON from the same export flow; LLTimeline export writes the full
  `.lltimeline.json` document via `GET /v1/subtitles/{track_id}/lltimeline/export`.
  Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 11:02:30 CST: Added a direct Export LLTimeline JSON action to the
  Timeline Resource Summary so users can export the full resource from the same
  area that shows active/manual WordTimeline versions. The button reuses the
  same track-level `.lltimeline.json` export path and is covered by widget
  tests. Verified with `flutter analyze` and `flutter test` (60 tests passed).
- 2026-06-21 02:55:00 CST: Hardened the timeline-production browser GUI so it
  cancels cleanly and previews without blocking. `cancel()` now signals the
  whole process group (`start_new_session` + `os.killpg` SIGTERM, escalating to
  SIGKILL after a 3s grace) instead of orphaning the whisperx/MFA worker, and
  reports a real exit code (130 on cancel) so the UI no longer sticks on
  "Running..." Command preview no longer synchronously SHA256-hashes multi-GB
  media (instant placeholder for preview; real hash computed only on `/run`);
  previewed commands survive `poll()` until the next run; and `main()` forces
  line-buffered stdout so the server URL appears even under pipe redirection.
  Added `test_production_pipeline_gui_contract.py` (10 tests) covering the
  process-group cancel, fingerprint resolution, placeholder, and stdout
  behavior. Verified end-to-end against the Brooklyn middle-school sample:
  whisperx baseline + `from-whisperx-json` convert and MMS-FA post-alignment
  both produce a valid `llplayer.timeline.v1` `.lltimeline.json`.
- 2026-06-20 21:08:52 CST: Added subtitle-resource consumption capability
  visibility in the standalone Subtitle Resources panel. Each resource now
  reports sentence, word, chunk, and phone timing availability with counts;
  resource refresh probes capabilities independently so partial failures do not
  hide usable subtitles; and opening a new media clears stale resource
  capability state before reloading.
- 2026-06-20 21:08:52 CST: Hardened active subtitle-resource consumption after
  LLTimeline import by loading word timings, chunk partitions, phone analyses,
  and pronunciation independently. Resource-list capability refresh no longer
  triggers full-track chunk partition generation, so importing a large
  `.lltimeline.json` is not blocked by panel capability probing.
- 2026-06-20 21:36:31 CST: Promoted subtitle resources to a top-level desktop
  entry, opening a dedicated management page like the vocabulary book instead
  of relying on the right-side transcript panel. LLTimeline import now refreshes
  visible resources after success, and current-media imports reuse an existing
  same-media/same-subtitle fingerprint track id so repeated or previously
  imported `.lltimeline.json` resources remain visible and consumable.
- 2026-06-20 21:46:04 CST: Fixed the desktop development sidecar selection trap
  where a stale `target/release/api-http` was preferred over the freshly built
  debug sidecar, leaving real user databases at schema v9 without
  `word_timeline_runs`, `lltimeline_resources`, or subtitle lifecycle status.
  Rebuilt the release sidecar, migrated the local database to schema v12, and
  verified the desktop sample MP4 plus `baseline.lltimeline.json` imports as a
  visible subtitle resource with 1,755 word timings.
- 2026-06-20 10:14:20 CST: Added the first full subtitle-resource lifecycle
  management pass. `SubtitleTrack` resources now carry `available|archived`
  status with SQLite migration `0012_subtitle_resource_lifecycle`; the local API
  can archive, restore, delete, export, and list resources; and the Subtitle
  Resources panel exposes archive/restore/delete/export actions while preventing
  archived resources from being activated.
- 2026-06-20 10:05:16 CST: Reworked Phase 2.2 app-side subtitle resource
  handling so subtitles and `.lltimeline.json` files behave as attachable,
  visible resources for the current media. Added current-media LLTimeline
  import with fingerprint mismatch confirmation, remapped imported track /
  sentence / WordTimeline identifiers for exchange-safe attachment, exposed
  media subtitle-resource listing APIs, and moved Timeline Resource Summary out
  of the Transcript panel into a standalone Subtitle Resources side panel that
  can import, list, activate, and refresh subtitle resources.
- 2026-06-20 08:39:01 CST: Hardened the MFA `align-one` sidecar so a single
  segment `mfa align_one` subprocess failure is recorded as a per-segment
  diagnostic/skipped timing instead of crashing the whole run, while still
  failing fast when every segment fails so production fallback can engage.
- 2026-06-20 00:34:23 CST: Created Phase 2.3 manual timeline review UI
  planning docs, defining the sentence-level Word Timing Inspector approach,
  user-adjusted WordTimeline save/activate/export flow, playback verification
  controls, and Phase 2.4 handoff boundary.
- 2026-06-20 00:18:59 CST: Replaced the timeline production Tkinter GUI with a
  local browser-based GUI backed by Python's standard-library HTTP server,
  using macOS `osascript` only for folder/media selection and avoiding Tk file
  dialogs entirely.
- 2026-06-20 00:11:42 CST: Attempted to reduce the timeline production Tk save
  dialog crash on macOS/Python 3.13 by removing the multi-pattern file type
  filter; this was later superseded by replacing the Tk GUI entirely.
- 2026-06-19 23:59:47 CST: Fixed timeline production GUI/CLI WhisperX discovery by
  auto-detecting the default timeline-production venv under
  `~/Library/Caches/LLPlayerNext/research/timeline-production/venv/bin/whisperx`;
  the GUI now pre-fills this path when present.
- 2026-06-19 23:28:09 CST: Added a standalone Tkinter GUI wrapper for the local
  LLTimeline production pipeline at
  `scripts/timeline-production/production_pipeline_gui.py`, covering media
  selection, output paths, SHA256 fingerprinting, WhisperX/post-aligner options,
  dry-run command preview, live logs, cancellation, and output-folder access.
- 2026-06-19 23:18:55 CST: Completed Phase 2.2 app timeline resource UI alignment. Added
  LLTimeline resource metadata/artifact persistence (`lltimeline_resources`),
  import/export artifact round-trip coverage, Flutter LLTimeline client methods,
  timeline resource controller state, and a Transcript-panel Timeline Resource
  Summary UI for import, active/candidate WordTimeline visibility, production
  readiness/artifacts, candidate activation, and a Phase 2.3 manual-review
  entry placeholder. Verified active WordTimeline playback binding remains on
  `trackWordTimings()` with legacy fallback.
- 2026-06-19 16:20:39 CST: Added the Phase 2.2 start handoff document at
  `.planning/handoff/project-handoff-2026-06-19-phase-2.2-start.md`, summarizing
  the completed Phase 2.1 hardening work, verified commands, remaining
  non-blocking architecture debt, and the recommended Phase 2.2 audit-first
  entry path for LLTimeline resource UI alignment.
- 2026-06-19 16:10:34 CST: Completed the Phase 2.1 application orchestration
  debt fix for transcription word timelines. Added
  `AppServices::refine_transcription_word_timelines` with a
  `ForcedAlignSidecar` input and `WordTimelinePipelineResult`, moving
  DTW extraction, MMS_FA sidecar invocation, forced-alignment merge,
  pause-refinement, WordTimeline snapshot creation, activation, and legacy
  fallback storage out of `api-http`. `crates/api-http/src/transcription.rs`
  now only reads the generated Whisper JSON, resolves the optional sidecar, and
  calls application orchestration. Updated Phase 2.1 and CONCERNS docs to mark
  this architecture debt handled while keeping mega-file splitting and
  monotonicity ablation as later standalone work.
- 2026-06-19 16:10:34 CST: Also moved the phonetic research fixture's canonical
  phone alignment and finding construction out of
  `crates/api-http/src/phonetic_analysis.rs` into
  `AppServices::build_research_fixture_phonetic_analysis`, so the HTTP
  coordinator keeps job state, queueing, repository writes, and events while
  application owns the speech-analysis composition.
- 2026-06-19 16:10:34 CST: Removed the remaining direct `speech_analysis`
  references from `crates/api-http/src/lib.rs` by exposing chunk partition
  response types and learned prosodic provider catalog access through the
  application layer.
- 2026-06-19 16:01:48 CST: Closed Phase 2.1 with a documented scope cut after
  completing the current hardening work: P0 word-index placeholders, P1 shared
  tokenizer/evaluation guardrails, production post-aligner fallback, and P3
  evaluation-stat de-duplication. Deferred the application orchestration
  extraction, application/persistence mega-file split, and forced-align
  monotonicity ablation into explicit architecture debt so Phase 2.2 can start
  without a risky broad refactor. Updated `.planning/STATE.md`,
  `.planning/codebase/CONCERNS.md`, and Phase 2.1 docs accordingly.
- 2026-06-19 15:55:21 CST: Marked the timeline-production / aligner-evaluation
  phase as temporarily closed and moved it into long-running research and
  production-script maintenance. Prepared Phase 2.2 planning docs for app-side
  `.lltimeline.json` resource UI alignment, covering resource import visibility,
  WordTimeline candidate summaries, active timeline selection, playback binding,
  and a later manual-review entry point.
- 2026-06-19 15:51:14 CST: Generalized the timeline-production post-alignment
  stage into a selectable degradation strategy. `produce-whisperx` now accepts
  `--post-aligner auto|mfa|mms-fa|none`; `auto` and `mfa` try MFA first, fall
  back to MMS_FA, and preserve the original WhisperX WordTimeline if all
  post-aligners fail, recording `post_alignment_failure` artifacts in the
  reusable `.lltimeline.json` resource. Added `apply-mms-fa-alignment`,
  extended `doctor` with MMS_FA runtime visibility, and updated contract
  dry-runs for the ordered fallback chain.
- 2026-06-19 15:41:28 CST: Paused further aligner benchmark expansion and
  documented deferred Qwen3-ForcedAligner, BFA/easytranscriber/CTC, and MMS_FA
  research directions under the timeline-production research docs. Advanced the
  current production mainline by adding MFA post-alignment orchestration to
  `scripts/timeline-production/production_pipeline.py`: `produce-whisperx` now
  supports `--post-aligner mfa`, appending an MFA `align-one` WordTimeline while
  preserving the WhisperX timeline as a candidate fallback, and
  `apply-mfa-alignment` can append MFA timings to an existing `.lltimeline.json`
  without rerunning WhisperX. Extended contract dry-runs for both production
  MFA entrypoints.
- 2026-06-19 15:19:15 CST: Completed the first MFA English US ARPA
  `align-one` TIMIT TEST 100 evaluation: 881/881 matched words, start MAE
  14.46ms, start P95 48.0ms, end MAE 18.20ms, end P95 53.0ms, tail mean abs
  34.12ms, tail P95 112.05ms, and no text mismatches. Updated Phase 4 docs to
  mark MFA as the strongest observed word-boundary aligner under a high-quality
  transcript/utterance-anchor condition, with WhisperX transcript + MFA as the
  next realistic production-route test.
- 2026-06-19 14:43:16 CST: Installed the local research-only MFA runtime via
  Homebrew `micromamba`, created the isolated MFA 3.3.9 environment under
  `~/Library/Caches/LLPlayerNext/research/mfa/env`, and updated the MFA setup
  and alignment sidecar scripts to force `MFA_ROOT_DIR` into the same research
  cache and prepend the MFA environment's `bin` directory to subprocess `PATH`
  so model files, MFA temporary defaults, and OpenFST/Kaldi binary resolution do
  not spill into `~/Documents/MFA` or the user's shell profile. Added a
  parallel `align-one` MFA sidecar strategy after batch `mfa align` reached
  successful first-pass alignment on TIMIT TEST 100 but failed in MFA's SQLite
  interval collection/export path with empty interval CSVs; `align-one` now
  resolves saved dictionaries and pre-extracted acoustic model directories
  before launching parallel jobs and gives each MFA child process an isolated
  `MFA_ROOT_DIR` to avoid concurrent model-cache extraction and
  command-history YAML writes.
- 2026-06-19 11:44:19 CST: Expanded the TIMIT TEST 100 alignment benchmark
  comparison across MMS_FA + TIMIT transcript, full WhisperX CLI, and
  WhisperX CLI + MMS_FA post-alignment; documented that MMS_FA remains the best
  current upper-bound route with a high-quality transcript, while the WhisperX
  CLI + MMS_FA post-pass improves start timing but regresses end/tail timing.
  Added the research-only MFA sidecar scaffold (`setup-mfa-research.sh`,
  `mfa-align-cli.py`) plus TextGrid parser contract coverage, with MFA
  installation and real runs still pending because this machine does not yet
  have `mfa`, `conda`, `mamba`, or `micromamba` available.
- 2026-06-19 11:00:47 CST: Implemented the M2.1 P1 tokenizer/evaluation
  guardrail: added shared `scripts/lltimeline_common.py`, moved benchmark,
  production, and evaluation tooling onto the same word normalization/token
  helpers, added regression coverage for multi-apostrophe words, and extended
  word timeline comparison reports with normalized text mismatch counts, rates,
  and samples.
- 2026-06-19 10:54:54 CST: Implemented the M2.1 P0 forced-alignment
  `word_index` contract fix: `align-cli.py` now emits `skipped: true`
  placeholders using unfiltered word indexes, `forced_align::merge_alignments`
  treats placeholders as per-word DTW fallback, contract tests cover CJK and
  punctuation skip cases, and ADR 0011 / M2.1 planning docs now match the
  existing top-level `timings[]` sidecar JSON shape.
- 2026-06-18 20:45:41 CST: Fixed the timeline-production research venv setup
  to install with `uv pip`, downloaded and smoke-loaded the WhisperX
  `large-v3` ASR stack plus the English wav2vec2 alignment model, added
  `scripts/timeline-production/whisperx-align-request.py` for known-transcript
  benchmark alignment, and produced the first TIMIT TEST 20 WhisperX alignment
  report: 171/171 matched words, start MAE 65.50ms, start P95 141.5ms, end MAE
  45.02ms, end P95 151ms, and tail lag mean -142.55ms.
- 2026-06-18 20:23:44 CST: Added TIMIT benchmark candidate tooling with
  `prepare-alignment-bundle` and `add-alignment-candidate`, fixed the MMS_FA
  sidecar for torchaudio 2.9 audio loading and tokenizer behavior, and produced
  the first real TIMIT TEST 20 MMS_FA evaluation report: 171/171 matched words,
  start MAE 56.38ms, start P95 128ms, end MAE 33.71ms, and end P95 81.5ms.
- 2026-06-18 20:15:11 CST: Validated local TIMIT full gold intake from
  `/Users/shadow/data/lisa/data/timit/raw`, generating local TEST/TRAIN
  LLTimeline gold resources under the research benchmark cache. Hardened the
  TIMIT converter for overlapping word rows, non-positive-duration rows,
  transcript-unmapped words, and leading/trailing apostrophe tokens, with
  smoke-test and contract validation coverage.
- 2026-06-18 19:47:03 CST: Reordered Phase 4 benchmark work to use existing
  high-quality gold corpora before CNN10/NBC self-built samples, documented the
  TIMIT → Buckeye → LibriSpeech alignments → news gold set sequence, added
  `scripts/benchmark-datasets.py timit-to-lltimeline` for local TIMIT
  `.WRD/.PHN/.TXT` conversion into `LLTimeline JSON v1`, and covered it with a
  synthetic TIMIT-style smoke fixture in contract validation.
- 2026-06-18 19:37:24 CST: Started Phase 4 evaluation work by adding
  document-level `compare-lltimeline` reports for comparing baseline,
  candidate, and gold word timelines inside one `.lltimeline.json`, including
  P95 boundary offsets, sentence-tail lag metrics, a multi-candidate LLTimeline
  fixture, contract validation coverage, and updated `.planning/` evaluation
  docs.
- 2026-06-18 19:30:22 CST: Completed Phase 3 Production Pipeline V1 by adding
  `production-report.json` generation for LLTimeline outputs, automatic report
  emission from `produce-whisperx`, contract validation for production quality
  reports, and `.planning/` status updates that move the project into Phase 4
  evaluation work.
- 2026-06-18 18:00:00 CST: Completed the `.planning/codebase/` documentation system.
  Renamed `CONVENTIONS.md` → `MAINTENANCE.md` (项目维护规则，与代码约定区分).
  Created three new codebase files: `STRUCTURE.md` (物理文件布局 + 新代码放哪),
  `CONCERNS.md` (技术债/已知问题/脆弱区域/测试缺口清单), and `CONVENTIONS.md`
  (项目级代码约定: crate 依赖规则、错误处理、异步、API 设计、Flutter/Python 模式).
  Added dedicated section for the unified test runner (`scripts/test.sh`) in TESTING.md.
  Co-Authored-By: Claude <noreply@anthropic.com>
- 2026-06-18 17:32:00 CST: Restructured the project documentation system by
  introducing the GSD-inspired `.planning/` directory as the project management
  hub. Moved `prd.md` → `.planning/PROJECT.md`, `roadmap.md` → `.planning/ROADMAP.md`,
  `requirements.md` → `.planning/REQUIREMENTS.md`. Created `.planning/STATE.md`
  as living project memory, `.planning/MILESTONES.md` as completed milestone index,
  `.planning/MAINTENANCE.md` as maintenance rules, and `.planning/codebase/` with
  ARCHITECTURE / STACK / DATA-MODEL / TESTING architecture skeleton docs.
  Consolidated `docs/discuss/` → `.planning/discuss/`, `docs/handoff/` →
  `.planning/handoff/`, `docs/timeline-production/` → `.planning/phases/2.0-
  production-engine/timeline-production/` (long-term subsystem). Migrated M2.0
  planning and feature docs from `docs/planning/`, `docs/features/`, and
  `docs/development/` into the 2.0-production-engine phase directory with
  upstream design notes in a dedicated `design-notes/` subdirectory. Frozen
  M1.x documents remain in `docs/` with index links from MILESTONES.md.
  Co-Authored-By: Claude <noreply@anthropic.com>
- 2026-06-18 16:08:50 CST: Added the `produce-whisperx` Phase 3 orchestration
  command to run media preparation, WhisperX execution, and LLTimeline
  conversion as one production pipeline entrypoint, with dry-run validation.
- 2026-06-18 16:06:35 CST: Added `run-whisperx` to the Phase 3 production
  pipeline with default/custom WhisperX command support, dry-run contract
  validation, run reports, and JSON output discovery for downstream LLTimeline
  conversion.
- 2026-06-18 16:02:53 CST: Extended the Phase 3 production pipeline with
  `prepare-media`, preprocessing artifacts, optional external vocal isolation
  command support, and LLTimeline artifact embedding for preprocessing reports.
- 2026-06-18 15:57:18 CST: Started Phase 3 production pipeline work with a
  research-only timeline-production script set, ffmpeg audio preparation,
  WhisperX JSON to `LLTimeline JSON v1` conversion, a sample WhisperX fixture,
  and contract validation coverage for the conversion bridge.
- 2026-06-18 15:53:09 CST: Completed Phase 2 resource lifecycle support for
  word timelines with summary, publish, archive-active, delete, OpenAPI/client
  coverage, and `lltimeline-resource.py` lifecycle commands; transcription job
  lifecycle methods are now represented in the handwritten local API client.
- 2026-06-18 15:36:01 CST: Completed the LLTimeline JSON v1 Phase 1 core by
  adding OpenAPI schemas, handwritten client methods, contract validation, and
  `scripts/lltimeline-resource.py` for validating, importing, and exporting
  `.lltimeline.json` files through the local API.
- 2026-06-18 15:21:41 CST: Added LLTimeline JSON v1 import support with
  `POST /v1/lltimeline/import`, round-trip HTTP coverage, and a minimal
  `.lltimeline.json` contract fixture that deserializes through the domain
  model.
- 2026-06-18 15:11:06 CST: Added the `docs/timeline-production/` documentation
  structure and started Phase 1 of the production-engine route with
  `LLTimeline JSON v1` domain contracts plus an HTTP export endpoint that wraps
  subtitle segments and active/candidate `WordTimeline` resources into a
  resource document.
- 2026-06-18 14:50:26 CST: Reframed the product definition around two
  coordinated tracks: a local heavy production engine for high-precision
  WordTimeline/PhoneTimeline/ChunkTimeline generation, evaluation, correction,
  and `.lltimeline.json` export; and a lightweight LLPlayerNext consumer that
  reads those resources for word highlighting and chunk playback without
  bundling heavy ASR/FA runtimes.
- 2026-06-18 11:40:04 CST: Transcription now preserves staged word timeline
  candidates from a single ASR run: raw Whisper DTW, MMS forced-alignment merge
  when available, and pause-refined final timings. The final stage is activated
  while prior candidates remain exportable for objective comparison without
  rerunning transcription.
- 2026-06-18 11:28:07 CST: Added a developer-facing word timeline evaluator
  that compares exported `WordTimeline` JSON files, reports weak DTW-vs-FA
  drift and anomaly metrics, optionally scores against gold word boundaries,
  and emits JSON/Markdown reports with smoke fixture coverage in contract
  validation.
- 2026-06-18 11:14:42 CST: Started Phase 1 word timeline resources with
  versioned `WordTimeline` domain contracts, SQLite schema v10 persistence,
  activation/archive semantics, active-timeline compatibility sync back to
  legacy `word_timings`, and HTTP management/export endpoints.
- 2026-06-18 11:07:27 CST: Added research-mode acoustic forced alignment for Whisper transcription:
  developers can prepare an isolated torchaudio MMS_FA venv, and transcription
  will auto-detect it, merge validated per-word aligned timings after DTW, and
  silently retain DTW timings when the sidecar is unavailable or fails.
- 2026-06-18 11:07:27 CST: Added transcription job regeneration and archiving
  support so subtitle timing experiments can rerun with current algorithms while
  old completed jobs stay queryable by id but hidden from the active job list
  and reuse lookup.
- Fixed development sidecar discovery: the Flutter desktop app now walks
  up directory ancestors to find the `api-http` binary (preferring
  `target/release` over `target/debug`), and the Rust API sidecar walks up
  from both its own executable path and the current working directory to
  locate `whisper-cli`, `ffmpeg`, and `ffprobe` inside
  `third_party/runtime/macos-arm64`. Together these fixes let the app find
  the full ASR toolchain when launched from anywhere inside the repository
  tree.
- Added `resolve_bundled_tool` and `runtime_candidates_from` to the
  transcription coordinator so the API sidecar discovers the bundled
  `whisper-cli` runtime by walking ancestor directories from both
  `current_exe` and `current_dir`. Flutter's sidecar resolution checks
  `target/release/api-http` before `target/debug/api-http`, so both
  profiles must be rebuilt after upgrading the Rust source.
- Started Milestone 2.0 Phase 0 with a fixed 60-slot real-speech evaluation
  catalog covering news, interview, conversation, speech rate, recording
  quality, and six target connected-speech phenomena.
- Added a provider-neutral phonetic evaluation tool that reports Phone Error
  Rate, detected-phone timeline validity, and subtitle-token association
  coverage, with success and failure smoke fixtures.
- Recorded candidate-provider roles, licensing constraints, a concrete Phase 0
  execution plan, and a proposed ADR that prevents product integration or
  `detected_in_audio` claims before quality and licensing gates pass.
- Added Vosk/Kaldi as a lightweight ASR and forced-alignment research baseline,
  without treating canonical decoder alignment as real detected-phone output.
- Proposed an AGPL/commercial dual-license direction and a permissive,
  versioned out-of-process provider SDK boundary while preserving the current
  no-license-granted repository state until legal and contributor preparation
  is complete.
- Added an isolated candidate-research harness that checks the pinned ZIPA
  dependency/artifact boundary, requires licensed external audio, rejects
  sequence-only output without phone timestamps, and records reproducibility
  and performance metadata.
- Added provider-neutral Milestone 2.0 domain contracts, schema v9 persistence,
  durable analysis jobs, detected-phone timelines, alignment findings, user
  feedback, API/events, and explicit model-management rejection paths.
- Added a deterministic research fixture that is disabled in normal builds,
  cannot be distributed as a model, never upgrades its low-confidence findings
  to `detected_in_audio`, and supports repeatable contract verification.
- Added desktop settings v8, current-sentence experimental analysis triggering,
  SSE progress refresh, detected-phone highlighting, and clearly labeled
  audio-detection results that remain hidden by default.
- Added focused widget coverage for the audio-analysis model/job center and
  distinct current-sentence and whole-track analysis triggers.
- Verified detected-phone highlighting across non-monotonic playback position
  changes and passed the existing packaged macOS build/runtime/signing smoke.
- Added `scripts/verify-m20.sh`, v8-to-v9 migration coverage, fake-provider
  idempotency checks, and low-confidence finding safety tests.
- Passed the complete M2.0 historical headless regression with 150 Rust tests,
  Flutter analysis, and 45 Flutter tests; the latest Flutter suite contains 46
  passing tests after the playback-position coverage increment.
- Passed the packaged macOS release build, bundled-runtime discovery, ad-hoc
  signing verification, extracted-package launch, video/audio smoke, and
  persistence checks.
- Milestone 2.0 remains incomplete: no real provider has passed the licensed
  evaluation, quality, performance, provenance, and distribution gates.
- Added an external evaluation-input manifest validator and preparation guide
  that check catalog membership, immutable audio checksums, explicit license
  decisions, bounded word/phone timelines, and independent human review before
  candidate development runs.
- Separated ZIPA code and model revisions and added a smoke-tested experimental
  CTC argmax frame-span projection, while retaining an explicit real-audio
  calibration gate before treating projected timestamps as stable.
- Added a research-only ZIPA CTC ONNX runner and explicit opt-in environment
  setup with pinned dependencies, separate code/model revisions, and
  checksum-verified external downloads.
- Started C2 acoustic-first partition quality with partitioner V2. Gap scoring
  now uses source-specific thresholds for ASR-reported, forced-aligned, and
  user-adjusted timings, while estimated timings remain excluded from acoustic
  evidence.
- Added moderate-gap evidence that can combine with punctuation support without
  overriding phrase protection on its own. Strong acoustic gaps remain able to
  split inside a text phrase.
- Treat punctuation from known ASR-generated subtitle tracks as inferred model
  output instead of a forced boundary. Inferred punctuation must combine with
  acoustic or product evidence before it changes the display partition.
- Reduced weak-evidence single-word fragments at chunk edges and added
  regression tests for ASR punctuation reliability, timing-source sensitivity,
  phrase protection, and fragment suppression.
- Added structured sentence chunk diagnostics containing selected and rejected
  boundary candidates, raw scores, thresholds, forcing state, primary source,
  and evidence. Product-facing partition responses remain unchanged.
- Added an initial golden calibration baseline covering ordinary short
  sentences, preferred-length splitting, single-word-tail suppression, and
  decisive acoustic gaps.
- Completed C2 acoustic-first partition quality. Readability scoring now
  favors supported boundaries near the preferred chunk length, weak evidence
  cannot create undersized fragments, soft/hard length limits prevent
  protected phrases from producing unreadably long chunks, and stronger
  phrase protection still yields to decisive acoustic gaps.
- Added a version-controlled V2 golden corpus covering fast speech, hesitation,
  moderate pauses, ASR-inferred versus trusted punctuation, fixed expressions,
  and long subtitles. The corpus enforces fragment and overlong-chunk quality
  bounds.
- Added `GET /v1/subtitles/{track_id}/chunk-diagnostics` for inspecting selected
  and rejected candidates using the same source-aware configuration as the
  product-facing track partition.
- Completed C3 rich acoustic evidence with partitioner V3. An independent
  pre-boundary-lengthening provider compares real word duration against a
  robust local baseline and can select meaningful boundaries without a pause.
- Added a conservative filled-pause hesitation provider that lowers boundary
  confidence around ASR-recognized `uh`, `um`, `erm`, `hmm`, and `mm` tokens.
  Ordinary hesitation gaps are suppressed while very large pauses remain
  eligible boundaries.
- Rich evidence is provider/version attributed, includes concrete measurement
  details, appears in existing chunk diagnostics, and is consumed as bounded
  signed score changes. Estimated timings and disabled/missing providers
  exactly degrade to C2 behavior.
- Added a C3 golden corpus covering no-pause lengthening, ordinary word
  durations, hesitation-gap suppression, and decisive pauses that survive the
  hesitation penalty.
- Completed C4 with an optional learned prosodic boundary provider and
  partitioner V4. The bundled project-authored MIT linear model runs locally,
  emits provider/revision/license-attributed evidence, and can assist only
  ambiguous rule-based boundaries.
- Added `GET /v1/chunk/providers` for inspecting learned-provider availability,
  runtime, and distribution metadata. Model or feature failures emit no
  evidence, and disabling the provider exactly preserves the C1-C3 pipeline.
- Added a C4 golden corpus covering learned-model contribution, ordinary
  delivery, decisive rule boundaries, and model-disabled fallback.
- Changed the default chunk presentation to static rounded capsules with clear
  visual spacing while preserving word-level highlighting inside each chunk.
  Current-chunk highlighting is now disabled by default and independently
  configurable as static background, slow scale bounce, or slow glow.
- Added an optional spacing-only chunk presentation and migrated existing v7
  desktop settings to the new static-capsule default.
- Added the Word Timing Accuracy milestone. Whisper DTW v2 now ignores
  punctuation timestamps when deriving lexical word edges and gives lexical
  alignment points a bounded duration so punctuation cannot consume audible
  pauses.
- Added optional local PCM energy pause refinement during Whisper
  transcription. Sustained audible pauses near coarse DTW boundaries restore
  adjacent word gaps as provider-attributed `ForcedAligned` timings, while
  missing or unsupported audio safely retains DTW timings.
- Changed timing precedence so refined forced alignment can replace coarse ASR
  timing while user-adjusted timing remains authoritative. Added
  `GET /v1/subtitles/{track_id}/word-timing-diagnostics` for inspecting final
  gaps and adjacent timing providers.
- Existing ASR tracks remain unchanged and must be re-transcribed to receive
  DTW v2 and audible-pause refinement.

## 0.7.2 - 2026-06-14

- Added the first user-visible chunk listening MVP. Primary subtitle sentences
  are rendered as complete, non-overlapping chunk groups and the active chunk
  follows playback using the existing local word-timing timeline.
- Added the stable `SentenceChunkPartition` display contract and V1
  acoustic-first rule partitioner. Real timing gaps, punctuation, phrase
  protection, and deterministic length fallback are resolved into one complete
  partition while estimated timings are excluded from acoustic evidence.
- Added `GET /v1/subtitles/{track_id}/chunk-partitions`, application-layer
  sentence and track partition methods, OpenAPI coverage, and independent
  fallback so chunk analysis failure never interrupts ordinary subtitles,
  word highlighting, or pronunciation enhancements.
- Added desktop chunk grouping and active-chunk highlighting settings. Chunk
  rendering preserves word clicks, vocabulary styles, and phrase interactions.
- Hardened text and acoustic chunk detection by rejecting invalid external
  phrase ranges, preventing phrase matches across punctuation, preserving
  empty-input sentence identity, and correcting gap-confidence interpolation.
- Added the staged C0-C4 chunk listening implementation plan. C0-C1 deliver the
  product loop; later milestones prioritize acoustic boundary quality and keep
  the display/API contract stable.
- Verified with workspace Rust tests, strict targeted clippy, Flutter analysis,
  Flutter tests, and whitespace checks.

## 0.7.1 - 2026-06-13

- Implemented text-level (lexical) chunk detection in the `speech-analysis` crate
  (`text_chunk_detection` module) as a companion to the existing acoustic
  (gap-based) chunk detection. The text detector partitions entire sentences
  into contiguous chunks where every word token belongs to exactly one chunk.
- Three data sources feed the text detector: (1) COCA n-gram collocations
  (MI ≥ 3.0, ~1K seed entries, compiled into the binary via `include_str!`),
  (2) PHRASE List (Martinez & Schmitt 2012, 505 pedagogically-selected
  functional phrases with category labels), and (3) existing ECDICT/built-in
  phrase candidates forwarded from the application layer.
- Sliding-window longest-match-first greedy overlap resolution ensures
  competing multi-word spans (e.g. "a lot of" vs "a lot") are resolved
  deterministically with longer spans taking priority.
- Cross-reference support between acoustic and text layers: new
  `BoundaryMarker::LexicalPhrase` variant, `CombinedChunkResult` type,
  `combine_chunks()` merging acoustic and text evidence with four-quadrant
  confidence logic (mutual-reinforcement, acoustic-only discount, text-only
  discount, no-signal), and `annotate_acoustic_with_text()` for decorating
  acoustic boundaries with lexical phrase markers.
- Added `AppServices::detect_text_chunks`, `detect_text_chunks_for_track`,
  and `detect_combined_sentence_chunks` methods.
- 18 new unit tests across `text_chunk_detection` covering empty/single-word
  input, COCA collocation matching, PHRASE List detection, external candidate
  forwarding, longest-match resolution, case-insensitive matching, partition
  coverage integrity, boundary count consistency, token order preservation,
  punctuation filtering, MI→confidence mapping, and source counts.

- Enabled whisper.cpp DTW (Dynamic Time Warping) token-level timestamps during
  ASR transcription so generated subtitle tracks produce `asr_reported` word
  timings instead of falling back to the weighted estimator.
- Added `-ojf` (JSON-full) and `-dtw <preset>` flags to the whisper-cli
  invocation. The JSON-full output carries per-token `t_dtw` cross-attention
  alignment timestamps in centiseconds.
- New `asr_timing` module merges whisper subword tokens into lexical words by
  leading-whitespace rules and produces `WordTiming` entries with
  `timing_source = asr_reported`.
- DTW is enabled only for `whisper`-family models; custom models skip the step.
- Every stage degrades safely: unavailable `t_dtw` values, segment count
  mismatches, word count mismatches, boundary violations, and non-monotonic
  timestamps all fall back to the existing deterministic weighted estimator on a
  per-sentence basis.
- The Flutter frontend, database schema, and `timing_priority` logic required
  zero changes — `AsrReported` (priority 3) already overrides `Estimated`
  (priority 1) in the existing word-timing pipeline.
- Established a unified testing workflow (`scripts/test.sh`) that consolidates
  `cargo fmt`, `clippy`, `test`, `flutter analyze`, `flutter test`, and contract
  validation into a single command with structured pass/fail summary output.
  Supports `--quick`/`--rust`/`--flutter`/`--full` modes, `--json` for
  machine-readable CI/AI output, `--verbose` for raw logs, `--debug` for
  internal tracing, and `--strict` to require `Cargo.lock`, deny Rust warnings,
  and make Flutter infos/warnings fatal. Successful-run logs are deleted;
  failed-run logs remain at the reported path while the terminal prints only
  the summary and key error lines.
- Extracted shared test utilities (`scripts/lib-testing.sh`) from the six
  `verify-m*.sh` acceptance scripts: cargo resolution, API lifecycle
  (start/stop/wait), curl helpers, and JSON assertion functions.
- Added the project's first Rust integration test
  (`crates/speech-analysis/tests/asr_timing_integration_test.rs`) with a
  real whisper `-ojf` JSON fixture covering subword merge, `t_dtw=-1` filter,
  special tokens, repeated DTW points, and boundary/segment-count mismatch
  fallback.
- Completed the ASR timing fix against real bundled whisper.cpp output:
  `[_BEG_]` / `[_TT_*]` special tokens and punctuation no longer corrupt the
  final lexical word, merged words are text-validated before mapping, repeated
  DTW points become deterministic non-empty intervals, and zero-duration word
  timings are rejected by the storage contract. Previously stored zero-length
  timing caches are detected as unusable and automatically fall back to the
  deterministic estimator.
- Updated CI to invoke `./scripts/test.sh --rust` and `--flutter` instead of
  individual `cargo`/`flutter` commands, keeping the same check coverage while
  producing more actionable failure logs.
- Migrated all 6 `verify-m*.sh` acceptance scripts to source `lib-testing.sh`,
  eliminating duplicated cargo resolution, API lifecycle, cleanup traps, and
  curl helpers. `setup_test_dir()` now registers cleanup automatically, API
  startup restores signal handling for graceful shutdown, and M1.7/M1.8 use
  the shared environment-aware `start_api()` path. Fixed schema drift (v6→v8)
  in verify-m17 and verify-m18 that accumulated across milestones.
- Added the project's second Rust integration test suite
  (`crates/persistence-sqlite/tests/persistence_integration_test.rs`) covering
  file persistence across reopen, migration backup creation, concurrent access
  safety, subtitle import/export, and media availability lifecycle (6 tests,
  25 total for the crate).
- Added `cargo-llvm-cov` coverage collection to CI (`lcov.info` artifact) for
  tracking coverage trends across PRs.
- Fixed the dictionary-provider parallel-test flake by replacing PID/time-based
  fixture paths with `tempfile::NamedTempFile`; 50 repeated parallel runs pass.
- Added 42 unit tests to the `application` crate (previously zero coverage)
  covering `require_text`, `clean_optional`, `normalize_american_english` (19
  irregular/suffix rules), `normalize_phrase`, `phrase_candidates` (including
  token boundary and non-word-token handling), `lexical_from_word`,
  `lexical_source_from_word`, and `timing_priority`. Total workspace tests
  increased from 58 to 100+.
- Fixed a boundary bug in `phrase_candidates` where sentences shorter than a
  phrase's word count could trigger an out-of-bounds index panic; corrected
  the window count formula.
- Set CI coverage gate at 50% line coverage (`--fail-under-lines 50` in the
  coverage job) to prevent coverage regressions, with a planned increase to
  55%+ as test coverage expands.
- Enhanced `./scripts/test.sh --quick` to include `cargo test --workspace
  --lib` (unit tests only, excluding integration/doc tests) while remaining
  under 30s. Quick mode now runs: fmt → clippy → lib unit tests → analyze.
- Added fuzz testing infrastructure with 3 fuzz targets:
  `crates/subtitle-core/fuzz/` (SRT and WebVTT parsing),
  `crates/speech-analysis/fuzz/` (ASR timing JSON extraction). The manifests
  are independent workspaces with committed lock files, the ASR target matches
  the current API, and CI runs every target for a 10-second nightly-Rust smoke
  test.
- Rewrote `testdata/README.md` as a comprehensive fixture catalog documenting
  every test data file, its purpose, and which tests consume it.
- Created `docs/features/testing-milestone.md` as the tracking document for
  the test system improvement initiative with P0/P1/P2 tiered goals and
  progress tracking.
- Added 16 unit tests to the `diagnosis-core` crate (2 → 18) covering all
  `diagnose` function branches: `MeaningBarrier`, `RecognitionBarrier`,
  `InsufficientInformation`, `OtherFactors`, mixed scenarios, non-word token
  filtering, `None` status handling, duplicate lemma dedup, and edge cases.
- Added `criterion` performance benchmarks for `subtitle-core` (SRT/VTT parse,
  tokenize, normalize) and `speech-analysis` (ASR timing extraction, word
  timing estimation). 10 benchmark cases in total covering small fixtures and
  large synthetic inputs (2k sentences, 500 segments). CI compiles all
  benchmarks with `cargo bench --workspace --no-run --locked`.
- Added `proptest` property-based testing with 10 property tests across
  `speech-analysis` (timing output count, monotonicity, bounds, start≤end)
  and `subtitle-core` (normalize idempotence, tokenize word normalization,
  SRT/VTT no-panic, SRT draft field validity). Total workspace tests: 132.
- Added API surface regression test (`openapi_version_snapshot`)
  in `api-http` that snapshots the OpenAPI 3.1.0 version, 51-path count, 18
  key schema definitions, and /v1/ prefix convention. Full semantic
  breaking-change detection remains future work.
- Added `scripts/test-infrastructure.sh` to test cleanup traps, API process
  teardown, quick/full mode selection, strict flags, JSON output, and retained
  failure logs. CI runs this self-test before desktop checks.
- Added `scripts/test.sh --low-memory` to limit Cargo, Rust-test, Rayon, and
  Flutter-test concurrency, reuse Flutter dependency resolution, and diagnose
  child exit code 137 as `SIGKILL` / external resource enforcement. Human
  output now emits a lightweight progress heartbeat before each check so quiet
  commands remain visible to external executors.
- Added a focused ASR word-timestamp handoff documenting the completed
  real-whisper validation, fallback/storage invariants, verification baseline,
  and the current environment's direct-script `SIGKILL` limitation.
- Prevented quick/full mode duplication: the Rust lib-test subset now runs only
  in `--quick`, while Rust/full modes execute the complete suite once.
- Fixed Rust test pass-through handling so arguments after the runner's `--`
  are forwarded after Cargo's test-harness separator.
- Added `.claude/worktrees/` to `.gitignore` so local product/refactor worktrees
  are not accidentally staged.

## 0.7.0 - 2026-06-13

- Integrated the modular Flutter controller/widget architecture while
  preserving Milestone 1.9 pronunciation and word-sync behavior.
- Fixed nullable controller state so media, subtitle, selection, diagnosis,
  and loop state can be cleared without retaining stale values.
- Provider-neutral pronunciation, phoneme, speech-rule, and word-timing
  contracts with schema v8.
- Pinned CMUdict canonical en-US pronunciation with deterministic fallback,
  lexical stress, ARPAbet, IPA display, variants, and token mapping.
- Deterministic bounded word timings for ordinary subtitles and local
  current-word highlighting that remains correct after seek, loop, and rate
  changes.
- Rule-based weak form, contraction, linking, flapping, deletion, and
  assimilation hints from a fixed 18-rule catalog that explicitly does not
  claim real-audio detection.
- Provider/version-isolated canonical pronunciation caching, explicit cache
  invalidation events, and non-blocking track jobs with cancellation and retry.
- Desktop settings v7, pronunciation diagnostics, API/event contracts, and
  Milestone 1.9 automated verification.
- Fixed current-word timing loading by reading the API contract fields
  `timing_source` and `provider_id`.
- Added background, scale-bounce, and glow current-word styles while keeping
  word-timing provenance in diagnostics instead of the playback overlay.
- Confirmed AV1 playback during collaborative functional acceptance.
- Removed the startup stall caused by re-hashing installed learning resources,
  added an explicit core-starting/error/retry screen, and fixed short-sentence
  ECDICT phrase scanning.
- Completed collaborative functional acceptance. Independent Developer ID
  distribution signing and notarization remain deferred release work.

## 0.6.0 - acceptance candidate

- Unified word and user-confirmed phrase learning assets with schema v7 and
  vocabulary asset bundle v3.
- Versioned lemma normalization, persistent corrections, and phrase candidates.
- Clickable phrase underlines in learning subtitles; confirmed phrases remain
  independent assets with their own status and source ranges.
- Explicit checksum-verified ECDICT and CMUdict resource manager.
- Provider-neutral OpenSubtitles title, filename, and media-hash workflows.
- Provider-supplied pronunciation audio in the unified word learning panel.
- Vocabulary asset v3 import preserves newer local state and independently
  merges learning content, history, and durable source encounters.

## 0.5.0 - 2026-06-10

Milestone 1.7 local ASR learning subtitle release.

- Provider-, runtime-, model-, and profile-neutral transcription contracts.
- Durable single-concurrency whole-media jobs with progress, cancellation,
  retry, restart interruption handling, provenance, and idempotent completion.
- whisper.cpp model catalog, explicit verified downloads, custom model
  registration, model management, and persistent job center.
- Generated subtitles become ordinary interactive learning tracks and support
  SRT export.
- Reproducible macOS arm64 whisper.cpp and LGPL-only FFmpeg runtime build,
  license validation, application bundling, and deterministic fake-runtime
  acceptance test.

## 0.4.1 - 2026-06-10

- Draggable viewport-relative subtitle placement, independent primary/secondary
  font controls, and a stable video viewport when subtitle visibility changes.
- Restored the media-kit video texture layout after the subtitle overlay
  refactor, fixing the black video screen regression.

## 0.4.0 - 2026-06-10

Milestone 1.6 desktop learning experience release.

- Responsive subtitle presets and automatic native-subtitle suppression.
- Simplified Chinese and English desktop localization.
- TXT/CSV existing vocabulary import with conflict-safe status initialization.
- Unified word learning panel with durable user definitions and notes.
- Provider-agnostic aggregated dictionary API and multi-source UI.

## 0.3.0 - 2026-06-10

Milestone 1.5 vocabulary learning asset release.

- Status-driven vocabulary books with user-selected status as the authority.
- Durable status history and source sentence snapshots.
- Missing-media recovery and independent vocabulary asset backup/restore.
- Latest-effective context observations with clear support.
- Schema v4 migration with legacy history and source backfill.

## 0.2.0 - 2026-06-09

Milestone 1 macOS Apple Silicon MVP.

### Added

- Local video/audio playback and complete subtitle-learning loop.
- SRT/WebVTT import, interactive transcript, sentence navigation and loop.
- Word status, dictionary lookup, context observations, and diagnosis.
- Dual text subtitles with independent offsets.
- Drag-and-drop import and configurable subtitle appearance/layout.
- Embedded text-subtitle extraction through optional ffprobe/ffmpeg.
- Online-media URL resolution through optional yt-dlp.
- Versioned local settings, progress recovery, diagnostics, and release package.

### Deferred

- Windows/Linux, OpenSubtitles, bitmap subtitle interaction, mobile, ASR, and
  translation.
