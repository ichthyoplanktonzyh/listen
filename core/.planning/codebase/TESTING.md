# LLPlayerNext — 测试体系

> 最后更新：2026-07-13

## 1. 测试层次

```
┌────────────────────────────────────────┐
│ E2E 验收测试                            │
│ 真实材料手工验收 (CNN10/NBC 新闻)        │
├────────────────────────────────────────┤
│ 集成测试                                │
│ api-http 路由 + persistence 读写        │
├────────────────────────────────────────┤
│ 契约测试                                │
│ OpenAPI + JSON Schema + LLTimeline     │
├────────────────────────────────────────┤
│ 单元测试                                │
│ domain / diagnosis / subtitle / speech │
├────────────────────────────────────────┤
│ 评估脚本与人工 QA                       │
│ phone evidence + rhythm/listening QA    │
├────────────────────────────────────────┤
│ 属性测试 + Fuzz                        │
│ subtitle 解析 / token 化               │
└────────────────────────────────────────┘
```

## 2. Rust 测试

### 单元测试（各 crate 内 `#[cfg(test)] mod tests`）

| Crate | 覆盖范围 |
|---|---|
| `domain` | ID 类型、枚举序列化、PhoneticAnalysis::validate()、SyntacticAnalysis span/mapping/tree/coverage validator |
| `subtitle-core` | SRT/VTT 解析、token 化、时间轴查询（空隙/重叠/边界） |
| `diagnosis-core` | 词义障碍、声音识别障碍、信息不足、其他因素 |
| `speech-analysis` | 100 句发音基线、OOV fallback-v2 stress、information-structure prior、Reference B text/syntax provenance 与未资格 fallback、syntax-aware SenseGroup clause/PP/subordinator boundary、phrase/标点保护、min/max + 3–5 教学粒度、低 coverage 精确 fallback、provider-neutral dependency candidate matcher、RhythmFrame bridge、chunk 分区 |
| `application` | AppServices 用例逻辑、chunk 检测、SyntacticAnalysisProvider fake/finalization seam、共享 consumer 单 batch/artifact ID、坏句隔离、timeout 精确 fallback |
| `syntactic-provider` | Stanza/spaCy 同构 neutral contract、缺模型 capability、畸形 stdout、timeout 闭合失败 |
| `dictionary-provider` | Provider 查询、缓存逻辑 |
| `persistence-sqlite` | CRUD 操作、幂等、唯一约束、事务 |
| `api-http` | 路由 handler、错误映射、认证中间件 |
| `api-events` | 事件 Schema 验证 |

### 集成测试（`tests/` 目录）

| 位置 | 内容 |
|---|---|
| `crates/persistence-sqlite/tests/persistence_integration_test.rs` | 持久化全流程集成测试（亦驱动 `AppServices` 编排） |
| `crates/persistence-sqlite/tests/migration_recovery_test.rs` | 迁移备份/失败恢复刻画：升级旧库建 `.pre-migration.bak`、全新/最新库不建备份、**迁移失败时原库完整保留在备份中可恢复**、版本不前进 |
| `crates/persistence-sqlite/src/tests.rs::current_version_with_legacy_lexical_schema_is_destructively_repaired` | 旧 v7 lexical schema 已跑过且 `user_version=15` 的坏库回归：v16 断代重建 lexical/learning-resource 表，恢复 `lexical_observations` 与 LexicalUnit identity columns |
| `crates/persistence-sqlite/src/tests/learning_loop.rs::session_summary_derives_stuck_point_statuses_from_events_attempts_and_review` | Phase 3.2 卡点 summary 聚合：事件、practice attempt、review item 派生状态与熟料标记 |
| `crates/persistence-sqlite/src/tests/learning_loop.rs::listening_inbox_capture_process_review_and_micro_intensive_round_trip` | Phase 3.3 泛听 Inbox 编排：soft interrupt capture、ReviewItem 去向、micro-intensive PracticeItem 去向、理解度自报事件 |
| `crates/persistence-sqlite/src/tests/timelines.rs::rule_and_syntax_sense_group_providers_keep_independent_runs` | rule/syntax SenseGroup provider/version、syntax artifact metrics 与独立 lifecycle 共存，且显式不依赖 ChunkTimeline |
| `crates/persistence-sqlite/src/tests/learning_loop.rs::shadowing_completion_persists_recording_without_creating_capability_evidence` | Phase 3.8 录音资产 round trip、幂等非评价 completion、零 observation/review 与删除语义 |
| `crates/api-http/src/tests/practice.rs::practice_routes_capture_and_process_listening_inbox_items` | Phase 3.3 HTTP 路由：Listening Inbox capture/list/process 端到端 JSON contract |
| `crates/api-http/src/tests/practice.rs::recording_and_unscored_shadowing_routes_round_trip` | Phase 3.8 recording create/get/delete 与 `completed` shadowing HTTP contract |
| `crates/api-http/tests/api_integration_test.rs` | 全栈 HTTP 集成：真实 `router(ApiState::new(...))` + in-memory SQLite，`tower::oneshot` 进程内驱动 `api-http → application → persistence`（鉴权拒绝、media 注册/读取/404、字幕导入往返、archive/restore/delete 生命周期、LLTimeline v1 文档导入往返、word timeline create→activate、句子 diagnosis、lexical entry upsert→list→detail→学习内容更新） |
| `crates/api-http/src/transcription.rs::tests::*dtw*` | whisper.cpp DTW preset 解析回归：内置模型名、自定义/量化 `ggml-*` 路径、非 whisper.cpp provider 降级 |
| `crates/speech-analysis/tests/asr_timing_integration_test.rs` | whisper.cpp JSON → 词级时间戳 |
| `crates/speech-analysis/tests/chunk_detection_integration_test.rs` | 声学 chunk 检测 |
| `crates/speech-analysis/tests/chunk_partition_golden_test.rs` | 金标准 chunk 分区 |
| `crates/speech-analysis/tests/syntactic_real_media_qa_test.rs` | 真实 Stanza 开发报告 token 经生产 SenseGroup 分区：教学粒度与多词专名完整性 |

### 属性测试（proptest）

- `subtitle-core`：随机生成合法/非法字幕输入，验证解析不变式

### Fuzz 测试（cargo-fuzz / libfuzzer）

| Target | 输入类型 | 覆盖 |
|---|---|---|
| `srt_parser` | 任意字节序列 | SRT 解析不 panic |
| `vtt_parser` | 任意字节序列 | VTT 解析不 panic |
| `tokenizer` | 任意 Unicode 文本 | token 化不 panic，重组保留文本 |

### 性能基准（criterion）

| Benchmark | 内容 |
|---|---|
| `crates/speech-analysis/benches/asr_timing_bench.rs` | ASR 词级时序提取性能 |
| `crates/subtitle-core/benches/parse_bench.rs` | 字幕解析吞吐量 |

## 3. Flutter 测试

### 测试文件（`apps/desktop/test/`）

| 文件 | 覆盖 |
|---|---|
| `timeline_test.dart` | TimelineCursor 位置查询、LLTimeline document-level rhythm frame parsing and sentence lookup |
| `backend_event_coordinator_test.dart` | SSE 推送核心：service-started / 转写 job（completed 加载 vs in-progress 报状态 vs 跨 media 忽略）/ 音素 job（primary 命中 vs 非 primary 早退）/ lexical-entry 转发 / 未知事件 no-op |
| `store_test.dart` | `Store<T>` 状态容器：selector 身份 memoize、字段级精准通知、equal-state no-op、replace 刷新全部 + 聚合通知 |
| `builder_test.dart` | `StoreBuilder` / `StoreBuilder2` widget：只在选中 slice 变化时重建、无关字段不重建、equal-state no-op |
| `api_service_test.dart` | LocalApi HTTP 客户端 sidecar 路径解析 |
| `api_service_transport_test.dart` | A1 transport seam（`LocalApi.withTransport`）：GET 解码、非 2xx → `HttpException`、body 编码经 seam 转发 |
| `practice_controller_test.dart` | Phase 3.1 practice item/attempt/review flow；Phase 3.8 chunk 逐步展开、录音权限、非评分 completion、录音资产与客观比较 seam |
| `extensive_listening_controller_test.dart` | Phase 3.3 extensive listening start/capture/process/finish 与理解度自报请求；Phase 3.7 可选 hunting summary wire shape |
| `hunting_controller_test.dart` | Phase 3.7 猎词单 controller：目标/候选加载、候选确认、active 目标归档与 HTTP seam |
| `hunting_list_panel_test.dart` | Phase 3.7 猎词单面板：active 数量、目标/候选展示与确认后的响应式刷新 |
| `hunting_session_controller_test.dart` | Phase 3.7 狩猎会话：media occurrence 加载、总预算 5、每目标 2、三态作答统计与 HTTP seam |
| `hunting_prompt_card_test.dart` | Phase 3.7 priming → check 面板与“没注意”合法操作 |
| `learning_workflow_controller_test.dart` | `LearningWorkflowController`：`refreshDiagnosis` generation guard（happy/null/**stale 丢弃**/切换 cue 丢弃/错误→null）+ `loadPhraseCandidates` 经 A1 seam 加载与清空 |
| `speech_enhancement_workflow_controller_test.dart` | `SpeechEnhancementWorkflowController.loadTimelineResource` 降级：4 子资源全失败→`unavailable`、部分失败→warning（经 A1 seam） |
| `settings_test.dart` | AppSettings 持久化与升级 |
| `controllers_test.dart` | 控制器状态管理 |
| `external_tools_test.dart` | ffmpeg/ffprobe/yt-dlp 适配器 |
| `diagnosis_card_test.dart` | 诊断面板 UI |
| `vocabulary_book_test.dart` | 词汇本视图 |
| `transcription_ui_test.dart` | 转写 UI |
| `learning_assets_ui_test.dart` | 学习资产、可下载资源与字幕搜索 UI |
| `phonetic_analysis_ui_test.dart` | 音素分析 UI |
| `contract/backend_event_contract_test.dart` | SSE producer golden envelopes 的 Flutter typed 解析契约 |
| `contract/lltimeline_parse_test.dart` | committed LLTimeline rhythm fixtures 的 Flutter typed 解析契约，覆盖 segments、WordTimeline、document-level rhythm_frames 与 PhoneTimeline.sound_analysis fallback |
| `contract/practice_contract_test.dart` | Practice / session summary / Listening Inbox / Hunting target+candidate typed DTO fixture parsing and request serialization |

| `diagnosis_card_test.dart` rhythm case | Phase 2.21 compact rhythm frame nuclei、anchors、weak groups、compression spans、hotspots、predicted/audible provenance 和 confidence state |
| `phoneme_ribbon_test.dart` rhythm case | Phase 2.21 subtitle-layer `RhythmFrameRibbon` timeline、nucleus/anchor/weak/compression/hotspot chips、provenance tooltip、cue loop、Rhythm A/B/C toggle、A citation reference 与 B connected-speech A → B 音标投影 |

Phase 3.7 的真实媒体产品验收已由 owner 确认通过，记录见
`.planning/phases/3.7-hunting-list/3.7-MANUAL-QA.md`；自动测试覆盖预算与证据语义，人工 QA
确认提示强度、连续感与关闭后的零残留。

Phase 3.8 自动化与完整 macOS Release 打包已通过；真实麦克风权限、A/B/A 听感和波形/停顿可理解性
等待 owner 按 `.planning/phases/3.8-shadowing-recording-comparison/3.8-MANUAL-QA.md` 验收。

### 运行

```bash
cd apps/desktop && flutter test
```

## 4. Python 评估脚本

| 脚本 | 测试类型 |
|---|---|
| `scripts/evaluate-word-timelines.py` | 词级时间轴比较（偏移分布/覆盖/gold 指标） |
| `scripts/phonetic-eval.py` | 音素分析评估（PER/timeline 有效性/token 关联） |
| `scripts/evaluate-sound-line-benchmarks.py` | Phase 2.19 real-media QA pack 对 TIMIT/Buckeye/TED-LIUM reference 的 phone/text/timing 初始评分 |
| `scripts/evaluate-rhythm-frame.py` | Phase 2.21 RhythmFrame 覆盖率、manual QA annotation validation/matching、document-level `rhythm_frames` fallback、provenance samples、hotspot score distribution、manual QA 汇总和 closeout quality gates |
| `scripts/test_evaluate_rhythm_frame.py` | RhythmFrame scorer 的 missing-artifact、manual matching、annotation validation、aggregate summary、quality gate、2.21 committed fixture CLI smoke、B-side connected refs 和 no-phone/document-level JSON consumer 单元测试 |
| `scripts/evaluate-helsinki-prosody.py` | Phase 2.21 Helsinki Prosody / LibriTTS weak-label regression adapter，比较 provenance-bearing `stress_anchors` 和 `phrase_boundaries` 对 prominence/boundary labels 的命中 |
| `scripts/test_evaluate_helsinki_prosody.py` | Helsinki prosody adapter 的 label parser、RhythmFrame matching、provenance counts、missing-rhythm 状态和 committed fixture CLI gate 单元测试 |
| `scripts/prepare-helsinki-libritts-benchmark.py` | Phase 2.20 local-only LibriTTS/Helsinki baseline manifest/LLTimeline builder，支持 extracted split directory 和 split `.tar.gz` |
| `scripts/test_prepare_helsinki_libritts_benchmark.py` | LibriTTS/Helsinki prep 的 directory/archive input、missing-audio handling 和 baseline LLTimeline shape 单元测试 |
| `scripts/timeline-production/test_production_pipeline_acoustic_cues.py` | Production-side `rhythm_word_acoustic_cues` artifact generation from synthetic wav |
| `scripts/validate-contracts.sh` | LLTimeline Schema smoke + 契约测试 |
| `scripts/syntactic-analysis/test_syntax_sidecar_contract.py` | JSONL stdout 洁净、missing runtime/language、Unicode scalar、1:N/N:1/unaligned mapping |
| `scripts/syntactic-analysis/evaluate_provider.py` | Phase 3.9.1 digest-locked Stanza/spaCy correctness、alignment、tree、cold/warm/RSS/size 资格评估 |
| `scripts/syntactic-analysis/test_evaluate_provider.py` | Rust tokenizer parity 与 future/motion、habitual/state、have-to idiom、wh-extraction 保守 query 单元测试 |
| `scripts/syntactic-analysis/real_media_qa.py` | 对 owner 本地 SRT 分批执行 mapping/tree/determinism/phrase QA；报告仅存输入 SHA、cue 编号和统计，不复制字幕正文 |
| `scripts/syntactic-analysis/test_real_media_qa.py` | real-media SRT 多行 cue 解析与时间戳隔离单元测试 |
| `scripts/syntactic-analysis/evaluate_provider_v2.py` | Phase 3.9.2 corrected artifact/query/policy 分层资格评估；validation digest locked |
| `scripts/syntactic-analysis/test_evaluate_provider_v2.py` | v2 ambiguous-policy 与逐 query `qualified` / `fallback_only` scorer 回归 |
| `scripts/syntactic-analysis/real_media_qa_v2.py` | corrected want-to query 下的真实媒体 mapping/tree/determinism 复核，不复制字幕正文 |

### Python 评估缺少自动化单元测试

多数 Python 脚本仍侧重评估/比较功能，单元测试覆盖有限；Phase 2.20 scorer 已有
`scripts/test_evaluate_rhythm_frame.py` 和 `scripts/test_evaluate_helsinki_prosody.py`。
Phase 2.20 LibriTTS/Helsinki prep 也已有 `scripts/test_prepare_helsinki_libritts_benchmark.py`。
Phase 2.24 已把 `production_pipeline.py` 收缩为 CLI/dispatch；核心函数位于按职责命名的
`production_pipeline_*.py` modules，后续测试应直接面向这些 module interface。

Phase 2.24 收口时 `./scripts/test.sh --full --strict --low-memory` 为严格绿：Rust workspace
608 tests、Flutter 348 tests、analyze、fmt、`clippy -D warnings` 与 5 个 contract examples
全部通过。另有 production pipeline acoustic/GUI contracts 1 + 10 tests。architecture guard
同时锁定 dependency direction、runtime ownership、application public type、Flutter raw-return
allowlist、production Rust wildcard=0、描述性 module 命名与 Python entrypoint locality。

## 5. 契约测试

| 契约 | 验证方式 |
|---|---|
| OpenAPI 规范 | CI 验证 spec 与实现一致 |
| 事件 Schema | `api-events` JSON Schema 文件 + 自动化验证 |
| LLTimeline JSON v1 | `scripts/validate-contracts.sh` + fixtures (`testdata/lltimeline/`) |
| LLTimeline Flutter parse | `cd apps/desktop && flutter test test/contract/lltimeline_parse_test.dart` over committed rhythm fixtures |
| 句法 Provider JSONL | `scripts/syntactic-analysis/test_syntax_sidecar_contract.py` + `cargo test -p syntactic-provider` |
| Syntax capability lifecycle | `cargo test -p api-http syntax` + Flutter DTO/transport/settings widget tests；真实隔离 HOME 覆盖 install/cancel/update/damage/disable/uninstall |

Phase 3.9.3 的真实媒体 qualification 固定记录在
`.planning/phases/3.9.3-syntax-capability-delivery-lifecycle/`：244 cue release 路径覆盖首次整轨、
常驻热分析、fingerprint cache、单句 partial、backend restart persistence 与资源损坏/移除。报告不复制
字幕正文，只保存输入 hash、cue index 和聚合指标。

## 6. 测试数据

| 目录 | 内容 |
|---|---|
| `testdata/subtitles/` | SRT/VTT 样本 |
| `testdata/media/` | 测试视频/音频 |
| `testdata/generated/` | 程序生成的测试媒体 |
| `testdata/lltimeline/` | LLTimeline v1 最小有效文档 |
| `testdata/word-timelines/` | Gold/Baseline/Candidate 时间轴 |
| `testdata/chunk/` | Chunk 分区金标准用例 |
| `testdata/asr/` | whisper.cpp DTW JSON 样本 |
| `testdata/pronunciation/` | 100 句英语发音基线 |
| `testdata/phonetic-analysis/` | M2.0 音素评估目录（60 用例） |
| `testdata/timeline-production/` | WhisperX 样本输出 |
| `testdata/rhythm-frame-qa/` | Phase 2.21 RhythmFrame manual QA schema、sample annotations、committed synthetic fixtures、document-level no-phone evidence fixture 和 strict gate regression |
| `testdata/rhythm-prosody-benchmarks/` | Phase 2.20 Helsinki-style prominence/boundary fixture、LLTimeline fixture 和 weak-label adapter README |

## 7. 统一测试编排器（`scripts/test.sh`）

项目提供了一个统一的测试入口脚本，覆盖 Rust + Flutter + 契约三层验证。

### 运行模式

| 模式 | 命令 | 覆盖范围 |
|---|---|---|
| 全量（默认） | `scripts/test.sh --full` | fmt → clippy → Rust test → Flutter analyze → Flutter test → contracts |
| 快速 | `scripts/test.sh --quick` | fmt + clippy + Rust **lib 单元测试** + Flutter analyze（跳过集成测试和契约） |
| 仅 Rust | `scripts/test.sh --rust` | fmt + clippy + Rust test |
| 仅 Flutter | `scripts/test.sh --flutter` | Flutter analyze + Flutter test |

### 7 项检查清单

| # | 检查项 | 类型 | 命令 |
|---|---|---|---|
| 1 | `cargo fmt` | fmt | `cargo fmt --check` |
| 2 | `cargo clippy` | clippy | `cargo clippy --workspace --all-targets` |
| 3 | `cargo test (lib)` | quick_test | `cargo test --workspace --lib`（仅 quick 模式） |
| 4 | `cargo test` | test | `cargo test --workspace`（全量/rust 模式） |
| 5 | `flutter analyze` | analyze | `flutter analyze` |
| 6 | `flutter test` | flutter_test | `flutter test` |
| 7 | `contracts` | contracts | `scripts/validate-contracts.sh` |

### 附加标志

| 标志 | 作用 |
|---|---|
| `--json` | 机器可读 JSON 输出（含每项耗时、错误摘要） |
| `--verbose` | 实时流式输出原始日志 |
| `--debug` | 打印脚本内部执行步骤 |
| `--strict` | cargo clippy 将 warning 视为 error，且要求 Cargo.lock 一致 |
| `--low-memory` | 限制构建/测试并发数，避免重复 `flutter pub get` |

### 透传参数

```bash
# 将 --nocapture --test-threads=1 传递给 cargo test 和 flutter test
scripts/test.sh --rust -- --nocapture --test-threads=1
```

### 失败日志保留

测试失败时，日志文件保留在临时目录中（路径在输出中显示），便于事后排查。全部通过则自动清理。

## 8. 关键测试命令

```bash
# Rust 全量
cargo test --workspace
cargo clippy --workspace -- -D warnings

# 特定 crate
cargo test -p speech-analysis
cargo test -p persistence-sqlite -- --nocapture
cargo bench -p speech-analysis

# Fuzz（需要 nightly）
cargo +nightly fuzz run srt_parser -- -max_len=65536
cargo +nightly fuzz run vtt_parser -- -max_len=65536

# Flutter
cd apps/desktop && flutter test
cd apps/desktop && flutter analyze

# Python 评估
python scripts/evaluate-word-timelines.py compare \
  testdata/word-timelines/baseline-v1.json \
  testdata/word-timelines/candidate-v1.json
python3 scripts/test_rhythm_benchmark_roles.py
python3 scripts/test_evaluate_rhythm_frame.py
python3 scripts/evaluate-rhythm-frame.py \
  --manifest testdata/rhythm-frame-qa/fixture-manifest.jsonl \
  --annotations testdata/rhythm-frame-qa/fixture-annotations.jsonl \
  --strict-annotations \
  --min-rhythm-coverage 1.0 \
  --min-annotated-sentences 2 \
  --min-overall-useful-rate 1.0 \
  --max-hotspot-misleading-rate 0.0 \
  --max-hotspot-unsupported-rate 0.0 \
  --fail-on-quality-gate

# 全体验证（统一入口）
scripts/test.sh --full
scripts/test.sh --quick          # 快速检查
scripts/validate-contracts.sh    # 单独契约验证
```

## 9. 测试缺口

### 测试体系建设路线（2026-06-30 起）

按"由便宜稳到贵脆"分三层推进，刻意不以 UI 驱动 E2E 起手：

- **Tier A（进行中）**：Rust `api-http`/`application` 集成测试 + Flutter
  controller/store/coordinator 单元&widget 测试。便宜、稳、快，直接覆盖跨语言
  断裂的后端侧与前端状态层。
- **Tier B（规划）**：Layer 2 契约 E2E —— Flutter 驱动**真实 Rust sidecar**
  （确定性 timeline fixture，不带 whisper/ffmpeg），验证完整请求-响应-SSE 全栈。
  `api_service.dart`（`dart:io HttpClient`，非注入式）的全栈消费契约归此层，
  本阶段不为凑覆盖改造生产客户端。
- **Tier C（最后）**：极少量 `integration_test` happy-path smoke（fake sidecar，
  不碰真实媒体/拖拽），不是 21-30 个 UI 场景。

| 缺口 | 优先级 | 状态 | 说明 |
|---|---|---|---|
| `api-http` 关键路由测试 | P1 | 🟡 部分 | Tier A `api_integration_test.rs` 已覆盖鉴权、media/subtitle 生命周期、LLTimeline 导入往返、word timeline create→activate、diagnosis、lexical entry 生命周期；pronunciation、phonetic/chunk timeline、transcription job 路由待补 |
| `application` 层集成测试 | P1 | 🟡 部分 | `persistence-sqlite/tests/` 已驱动 `AppServices` 编排；无独立 `application/tests/` 目录 |
| Flutter 状态/推送层测试 | P1 | 🟢 已建 | coordinator + store + builder + A1 transport seam；两个 workflow controller（generation guard + 降级）已覆盖；api_service 其余方法级测试待补 |
| Python 管线单元测试 | P2 | 🟡 部分 | 声学 cue 与 GUI contract 已覆盖；conversion/audio/orchestration 需继续扩充 |
| Flutter widget 交互测试 | P2 | 🔴 缺 | 播放器/字幕点击/拖放交互 |
| 跨语言 E2E 测试 | P2 | 🔴 缺 | Tier B：Flutter → 真实 Rust sidecar 端到端 |
| Rhythm-first 评测脚本 | P0 | 🟢 已建 | Phase 2.20 stress anchor / weak group / compression span / phrase boundary / explanation quality scorer |
| RhythmFrame full UI widget tests | P1 | 🟡 部分 | compact 诊断卡测试已覆盖 v0；完整声音视图仍需验证 rhythm frame 分组、hotspot、缺失/低置信降级和 phone detail 展开 |
| Manual listening QA material | P0 | 🟢 已建 | Phase 2.20 可复现标注表，避免只用 PER 判断真实听感解释质量 |
