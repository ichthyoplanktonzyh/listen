# LLPlayerNext — 测试体系

> 最后更新：2026-06-18

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
│ 属性测试 + Fuzz                        │
│ subtitle 解析 / token 化               │
└────────────────────────────────────────┘
```

## 2. Rust 测试

### 单元测试（各 crate 内 `#[cfg(test)] mod tests`）

| Crate | 覆盖范围 |
|---|---|
| `domain` | ID 类型、枚举序列化、PhoneticAnalysis::validate() |
| `subtitle-core` | SRT/VTT 解析、token 化、时间轴查询（空隙/重叠/边界） |
| `diagnosis-core` | 词义障碍、声音识别障碍、信息不足、其他因素 |
| `speech-analysis` | 100 句发音基线测试、规则型语流检测、chunk 分区 |
| `application` | AppServices 用例逻辑、chunk 检测 |
| `dictionary-provider` | Provider 查询、缓存逻辑 |
| `persistence-sqlite` | CRUD 操作、幂等、唯一约束、事务 |
| `api-http` | 路由 handler、错误映射、认证中间件 |
| `api-events` | 事件 Schema 验证 |

### 集成测试（`tests/` 目录）

| 位置 | 内容 |
|---|---|
| `crates/persistence-sqlite/tests/` | 持久化全流程集成测试 |
| `crates/speech-analysis/tests/asr_timing_integration_test.rs` | whisper.cpp JSON → 词级时间戳 |
| `crates/speech-analysis/tests/chunk_detection_integration_test.rs` | 声学 chunk 检测 |
| `crates/speech-analysis/tests/chunk_partition_golden_test.rs` | 金标准 chunk 分区 |

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
| `timeline_test.dart` | TimelineCursor 位置查询 |
| `api_service_test.dart` | LocalApi HTTP 客户端 |
| `settings_test.dart` | AppSettings 持久化与升级 |
| `controllers_test.dart` | 控制器状态管理 |
| `external_tools_test.dart` | ffmpeg/ffprobe/yt-dlp 适配器 |
| `diagnosis_card_test.dart` | 诊断面板 UI |
| `vocabulary_book_test.dart` | 词汇本视图 |
| `transcription_ui_test.dart` | 转写 UI |
| `m18_ui_test.dart` | M1.8 学习质量功能 UI |
| `phonetic_analysis_ui_test.dart` | 音素分析 UI |

### 运行

```bash
cd apps/desktop && flutter test
```

## 4. Python 评估脚本

| 脚本 | 测试类型 |
|---|---|
| `scripts/evaluate-word-timelines.py` | 词级时间轴比较（偏移分布/覆盖/gold 指标） |
| `scripts/phonetic-eval.py` | 音素分析评估（PER/timeline 有效性/token 关联） |
| `scripts/validate-contracts.sh` | LLTimeline Schema smoke + 契约测试 |

### Python 评估缺少自动化单元测试

当前 Python 脚本侧重评估/比较功能，缺少 `pytest` 单元测试。建议后续为 `production_pipeline.py` 核心函数（音频预处理、WhisperX JSON 转换）添加测试。

## 5. 契约测试

| 契约 | 验证方式 |
|---|---|
| OpenAPI 规范 | CI 验证 spec 与实现一致 |
| 事件 Schema | `api-events` JSON Schema 文件 + 自动化验证 |
| LLTimeline JSON v1 | `scripts/validate-contracts.sh` + fixtures (`testdata/lltimeline/`) |

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

## 7. 关键测试命令

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

# 全体验证
scripts/test.sh --full
scripts/validate-contracts.sh
```

## 8. 测试缺口

| 缺口 | 优先级 | 说明 |
|---|---|---|
| `application` 层集成测试 | P1 | AppServices 缺少独立的 `tests/` 目录 |
| `api-http` 关键路由测试 | P1 | 需要完整请求-响应集成测试 |
| Python 管线单元测试 | P2 | production_pipeline.py 核心函数 |
| Flutter widget 交互测试 | P2 | 播放器/字幕点击/拖放交互 |
| 跨语言 E2E 测试 | P2 | 端到端：生产管线 → 导入 → 播放验证 |
