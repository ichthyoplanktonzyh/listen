# LLPlayerNext — 系统架构

> 最后更新：2026-06-21
> 基于 `feature/forced-alignment-research` 分支

## 1. 架构全景

```
┌─────────────────────────────────────────────────────────┐
│  生产引擎 (Python)                                       │
│  scripts/timeline-production/  +  forced-align/         │
│  WhisperX ASR → 强制对齐 → LLTimeline JSON v1           │
└────────────────────────┬────────────────────────────────┘
                         │ .lltimeline.json (文件交换)
┌────────────────────────▼────────────────────────────────┐
│  桌面客户端 (Flutter)                                    │
│  apps/desktop/                                          │
│  UI + fvp(mdk)播放器 + 本地TimelineCursor                │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP REST + SSE (localhost sidecar)
┌────────────────────────▼────────────────────────────────┐
│  Rust API 服务 (api-http)                                │
│  Axum HTTP Server, ~78 routes, SSE事件总线               │
└──────────┬──────────────────────────────────────────────┘
           │
┌──────────▼──────────────────────────────────────────────┐
│  Rust Application (application)                         │
│  AppServices: 用例编排 + Repository/Provider trait定义   │
└──┬──────────┬──────────┬──────────┬─────────────────────┘
   │          │          │          │
   ▼          ▼          ▼          ▼
domain    subtitle  diagnosis  speech      dictionary
(数据类型) -core     -core      -analysis   -provider
          (字幕)     (诊断)     (语音分析)   (字典)
                               │
                        persistence-sqlite
                        (SQLite 实现)
```

## 2. Rust Crate 依赖图

```
api-http (二进制)
  ├── application ─────────────┬── domain (叶子crate，0内部依赖)
  │   ├── diagnosis-core ──────┤
  │   ├── subtitle-core ───────┤
  │   └── speech-analysis ─────┤
  ├── dictionary-provider ─────┤
  ├── persistence-sqlite ──────┤
  ├── api-events ──────────────┘
  └── domain (直接)

依赖方向：domain ← 领域crates ← application ← api-http/persistence
api-http 不直接依赖 speech-analysis；语音分析编排通过 application 暴露。
```

## 3. 各 Crate 职责

### `domain` — 领域数据类型
- 零内部依赖的叶子 crate
- `string_id!` 宏生成类型安全 newtype（MediaId, SubtitleSentenceId, WordProfileId 等）
- 核心结构体：`MediaItem`, `SubtitleTrack`, `SubtitleSentence`, `WordProfile`, `WordTimeline`, `LLTimelineDocument`, `DictionaryLookup`, `TranscriptionJob`, `PhoneticAnalysisJob`
- 枚举：词汇状态（Unclassified/UnknownMeaning/KnownNotRecognized/KnownRecognized）、上下文观察、工作状态
- `DomainError` 统一错误类型

### `subtitle-core` — 字幕解析与时间轴
- SRT / WebVTT 解析（UTF-8/UTF-16）
- 英语 token 化（word/whitespace/punctuation/other）
- `Timeline` 运行时位置→字幕句查询
- 内容指纹与幂等导入
- Fuzz targets + proptest

### `diagnosis-core` — 听力诊断引擎
- 单个公开函数 `diagnose()`
- 输入：SubtitleSentence + WordProfile[] + WordObservation[]
- 输出：词义障碍 / 声音识别障碍 / 信息不足 / 其他因素
- 纯函数，确定性规则

### `speech-analysis` — 语音分析引擎（10个模块）
| 模块 | 职责 |
|---|---|
| `asr_timing` | whisper.cpp JSON → 词级时间戳提取 |
| `forced_align` | torchaudio MMS_FA 强制对齐集成 |
| `pause_refinement` | WAV 静音检测优化词边界 |
| `chunk_detection` | 声学 chunk 边界检测 |
| `chunk_partition` | 词级时间轴 → 学习 chunk 分区 |
| `text_chunk_detection` | 基于 COCA n-gram 的文本 chunk |
| `phonetic_alignment` | 音素序列动态规划对齐 |
| `phonetic_findings` | 弱读/省音/连读等发现 |
| `learned_prosodic_provider` | 规则型韵律分析 |
| `rich_acoustic_evidence` | 声学证据聚合 |

### `application` — 应用服务层
- Repository trait 定义：Media / Subtitle / WordProfile / VocabularyAsset / Transcription / PhoneticAnalysis / DictionaryCache / PlaybackProgress / LexicalEntry
- Provider trait 定义：DictionaryProvider / LexicalNormalizationProvider
- `AppServices` 中央编排器：媒体登记、字幕导入、发音分析、词级时间估算、WordTimeline CRUD、LLTimeline 导入导出、词汇资产 CRUD、字典查询缓存、chunk 检测、诊断
- 源码按 `dto` / `repositories` / `providers` / `error` / use case 模块拆分，root `lib.rs` 只保留 `AppServices` 装配、re-export 和共享 helper

### `dictionary-provider` — 字典数据源
- `FreeDictionaryProvider`：HTTP 调用 `api.dictionaryapi.dev`
- `EcdictProvider`：离线 CSV（ECDICT stardict 衍生），同时实现 `LexicalNormalizationProvider`
- 词形还原（went → go）+ 短语检测

### `persistence-sqlite` — SQLite 持久化
- `migrations.rs` 管理 schema 版本和迁移 SQL
- 按 repository / 表域实现所有 Repository trait 接口
- 自动迁移 + 预迁移备份
- 词级时间轴资源管理（activation/deactivation/archival）
- 词汇资产导入导出

### `api-http` — HTTP API 二进制
- Axum 本地 HTTP 服务（loopback 绑定 + Bearer token 认证）
- ~78 路由，按领域分组：media / subtitles / pronunciation / word-timings / chunking / vocabulary / dictionary / transcription / phonetic-analysis / speech-batch / learning-resources / lexical-entries / diagnosis
- HTTP handler 位于 `api-http/src/routes/`；root `lib.rs` 负责 router 装配、认证、SSE 和错误响应
- SSE 事件流（`/v1/events`）
- 协调器：TranscriptionCoordinator / PhoneticAnalysisCoordinator / SpeechBatchCoordinator

### `api-events` — 事件 Schema
- `EventName` 枚举（28 种事件类型）
- `EventEnvelope`（name + version + JSON payload）
- JSON Schema 验证

## 4. 数据流

### 播放路径（实时，不经过后端 API）
```
播放器位置事件 → TimelineCursor（客户端）→ 当前句/当前词 → UI 更新
```

### 学习路径（经过后端 API）
```
用户点击单词 → Flutter UI → HTTP POST /v1/dictionary/lookup
  → AppServices.lookup() → DictionaryProvider → 缓存写入 → 返回结果
```

### 字幕导入路径
```
SRT/VTT 文件 → Flutter 选择文件 → HTTP POST /v1/media/{id}/subtitles
  → subtitle_core::import() → 解析 → token化 → SQLite 持久化 → 返回标准化轨道
```

### 生产管线路径
```
媒体文件 → Python prepare-media → run-whisperx → from-whisperx-json
  → .lltimeline.json → ll timeline-resource.py import → SQLite 资源存储
```

## 5. 关键架构边界

| 边界 | 规则 |
|---|---|
| 播放 vs 后端 | 播放位置事件在客户端本地，不经过 HTTP API |
| 领域 vs 传输 | `application` 定义 trait，`api-http` 只做 HTTP 适配 |
| 消费端 vs 生产端 | 消费端不依赖 Python/PyTorch/WhisperX 运行时 |
| LLTimeline 契约 | Schema 版本化（`llplayer.timeline.v1`），不兼容变化升版本 |
| 词汇资产 vs 媒体 | 媒体/字幕删除不级联删除词汇学习资产（外键置空） |

## 6. 已知架构债务

1. **`speech-analysis` 职责过重**：10 个模块覆盖 ASR 后处理、对齐、chunk、音素分析四个不同关注点。M2 稳定后建议拆分。

2. **Flutter 搜索 Rust binary 路径脆弱**：从 CWD 向上遍历找 `target/release/api-http`，生产发布包应固化路径。
