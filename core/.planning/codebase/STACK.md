# LLPlayerNext — 技术栈

> 最后更新：2026-07-11

## 1. 总览

| 层 | 技术 | 版本 |
|---|---|---|
| 桌面 UI | Flutter (Dart) | SDK ^3.12.1 |
| 视频播放 | fvp (mdk/FFmpeg) | 本地 fork (`third_party/flutter/fvp`) |
| 后端核心 | Rust | edition 2024, rustc 1.94+ |
| HTTP 框架 | Axum | 0.8 |
| 异步运行时 | Tokio | 1 (multi-thread) |
| 数据库 | SQLite (rusqlite bundled) | 0.37 |
| 序列化 | Serde + serde_json | 1 |
| 生产管线 | Python | 3.11 |
| ASR/对齐 | WhisperX + torchaudio MMS_FA | 研究模式 |

## 2. Rust Workspace

```
workspace: Cargo.toml (9 crates, resolver 2)
├── domain              (数据类型，无外部依赖)
├── api-events          (serde, serde_json)
├── subtitle-core       (domain, sha2, hex, thiserror + proptest)
├── diagnosis-core      (domain)
├── speech-analysis     (domain, hound, serde, serde_json, thiserror)
├── application         (domain, diagnosis-core, subtitle-core, speech-analysis, async-trait, serde)
├── dictionary-provider (application, domain, csv, reqwest, async-trait)
├── persistence-sqlite  (application, domain, rusqlite, serde_json, sha2)
└── api-http (bin)     (application, api-events, speech-analysis, dictionary-provider, domain,
                         persistence-sqlite, axum, tokio, reqwest, tower, rand, async-stream)
```

### 共享依赖（workspace.dependencies）

| 依赖 | 版本 | 用途 |
|---|---|---|
| axum | 0.8 | HTTP 框架 |
| tokio | 1 | 异步运行时 |
| serde / serde_json | 1 | 序列化 |
| rusqlite | 0.37 (bundled) | SQLite |
| reqwest | 0.12 (rustls-tls) | HTTP 客户端 |
| thiserror | 2 | 错误类型派生 |
| sha2 | 0.10 | 内容指纹 |
| csv | 1 | CSV 解析 |
| hound | 3.5 | WAV 读写 |
| rand | 0.9 | 令牌生成 |
| async-trait | 0.1 | 异步 trait |

## 3. Flutter 桌面端

### 核心依赖

| 包 | 用途 |
|---|---|
| `fvp` | 视频播放（本地 fork，基于 mdk/FFmpeg） |
| `video_player: ^2.11.1` | 播放器接口 |
| `desktop_drop: ^0.7.1` | 拖放文件导入 |
| `file_selector: ^1.0.3` | 原生文件选择器 |
| `flutter_localizations` | 国际化（中/英） |
| `crypto: ^3.0.6` | SHA-256 文件指纹 |
| `csv: ^6.0.0` | CSV 词表导入 |

### 状态管理

纯 Flutter ChangeNotifier + InheritedWidget：
- `PlayerController` — 播放状态
- `SubtitleController` — 字幕同步
- `LearningController` — 词汇学习
- `SettingsController` — 设置持久化
- `AppControllers` — InheritedWidget 依赖注入

### 与 Rust 后端通信

- **模式**：Sidecar 进程（Flutter 启动 `api-http` 二进制）
- **协议**：HTTP REST（`127.0.0.1:{port}/v1/*`）+ SSE 事件流
- **认证**：随机 Bearer token（stdout JSON handshake）
- **设置存储**：`~/Library/Application Support/LLPlayerNext/settings-v8.json`（Flutter 侧）
- **数据库**：`~/Library/Application Support/LLPlayerNext/llplayer.db`（Rust 侧）

## 4. Python 生产管线

### 环境

| 组件 | 位置 |
|---|---|
| 生产管线 venv | `~/Library/Caches/LLPlayerNext/research/timeline-production/` |
| 强制对齐 venv | `~/Library/Caches/LLPlayerNext/research/forced-align/` |
| ZIPA 研究 venv | `~/Library/Caches/LLPlayerNext/research/zipa/`（实验） |

### 依赖

```
# 生产管线 (requirements.txt)
torch, torchaudio, whisperx, soundfile

# 强制对齐 (requirements.txt)
torch==2.9.1, torchaudio==2.9.1, soundfile==0.14.0

# 评估
datasets (可选，用于 TIMIT/Buckeye)
```

### 脚本清单

| 脚本 | 功能 |
|---|---|
| `scripts/timeline-production/production_pipeline.py` | 核心生产 CLI（doctor/prepare/run-whisperx/produce） |
| `scripts/timeline-production/setup-venv.sh` | 生产环境安装 |
| `scripts/forced-align/align-cli.py` | MMS_FA 强制对齐 sidecar |
| `scripts/forced-align/setup-venv.sh` | 对齐环境安装 |
| `scripts/lltimeline-resource.py` | LLTimeline 资源管理工具 |
| `scripts/evaluate-word-timelines.py` | 词级时间轴比较评估 |
| `scripts/phonetic-eval.py` | 音素分析评估引擎（实验） |
| `scripts/phonetic-research-adapter.py` | 音素研究适配器（实验） |
| `scripts/zipa-ctc-onnx-research.py` | ZIPA CTC ONNX 研究脚本（实验） |

## 5. 数据库

- **引擎**：SQLite（rusqlite bundled）
- **位置**：`~/Library/Application Support/LLPlayerNext/llplayer.db`
- **迁移**：33 个版本（0001 ~ 0033），自动迁移 + 预迁移备份
- **关键表**：media_items, subtitle_tracks, subtitle_sentences, lexical_entries, lexical_occurrences, lexical_status_history, lexical_observations, practice_sessions, practice_items, practice_attempts, review_items, review_attempts, hunting_candidates, hunting_targets, recording_assets, learning_events, listening_inbox_items, word_timeline_runs, chunk_timeline_runs, phone_timeline_runs, lltimeline_resources, dictionary_cache, transcription_jobs, phonetic_analysis_jobs

## 6. 构建与测试

### Rust

```bash
cargo build --release -p api-http       # 构建后端
cargo test --workspace                   # 全部测试
cargo test -p speech-analysis           # 单 crate 测试
cargo bench -p speech-analysis          # 性能基准
cargo +nightly fuzz run srt_parser      # Fuzz 测试
```

### Flutter

```bash
cd apps/desktop && flutter build macos  # macOS 构建
cd apps/desktop && flutter test         # Flutter 测试
```

### Python

```bash
scripts/timeline-production/setup-venv.sh  # 安装生产环境
scripts/forced-align/setup-venv.sh         # 安装对齐环境
python scripts/evaluate-word-timelines.py compare baseline.json candidate.json  # 评估
```

### 全量验证

```bash
scripts/test.sh --full                   # 综合验证
scripts/validate-contracts.sh            # 契约验证
```
