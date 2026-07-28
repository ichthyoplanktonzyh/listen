# LLPlayerNext — 代码库物理结构

> 最后更新：2026-06-28
> 回答"文件放在哪"。概念分层见 ARCHITECTURE.md。

## 1. 顶层目录布局

```
LLPlayerNext/
├── Cargo.toml              # Rust workspace 根（9 crates）
├── Cargo.lock              # 锁定的依赖版本
├── rustfmt.toml            # Rust 格式化配置（max_width=100, edition=2024）
├── .claude/                # Claude Code 会话配置
├── .github/                # CI/CD 工作流
├── apps/                   # Flutter 桌面端
│   └── desktop/            # macOS 应用
├── crates/                 # Rust workspace crates
│   ├── domain/             # 数据类型（0 外部依赖）
│   ├── api-events/         # 事件 Schema（serde）
│   ├── subtitle-core/      # 字幕解析 + token 化
│   ├── diagnosis-core/     # 听力诊断引擎
│   ├── speech-analysis/    # 语音分析（ASR 后处理/对齐/chunk/音素）
│   ├── application/        # 用例编排层（async-trait）
│   ├── dictionary-provider/# 词典查询 provider
│   ├── persistence-sqlite/ # SQLite 持久化（rusqlite bundled）
│   └── api-http/           # HTTP API 二进制入口（axum）
├── scripts/                # Python/Bash 工具脚本
│   ├── test.sh             # 统一测试编排器
│   ├── validate-contracts.sh # 契约验证
│   ├── timeline-production/  # 生产管线（Python）
│   ├── forced-align/         # 强制对齐 sidecar（Python）
│   └── verify-*.sh           # M1.x 验收脚本
├── testdata/               # 测试数据（9 个分类目录）
├── contracts/              # 契约定义
├── docs/                   # 长期参考文档（ADR/release/verification/planning）
│   └── decisions/          # ADR 编号归档
├── spikes/                 # 技术 spike（实验性代码）
├── third_party/            # 本地 fork 的第三方库（fvp）
├── dist/                   # 构建产物
├── .planning/              # 项目管理中枢
├── README.md               # 项目入口文档
└── CHANGELOG.md            # 变更历史
```

## 2. 目录职责

### crates/ — Rust 工作区（9 crate）

| Crate | 文件数 | 职责 | 依赖方向 |
|---|---|---|---|
| `domain` | 2+ | ID 类型、枚举、学习资产、timeline、learning-loop 模型、`DomainError` | 无外部依赖 |
| `api-events` | 1 | SSE 事件 Schema 定义 | domain |
| `subtitle-core` | 1 | SRT/VTT 解析、token 化、时间轴查询 | domain |
| `diagnosis-core` | 1 | 词义障碍、声音识别障碍、信息不足诊断 | domain |
| `speech-analysis` | 11 | ASR 时序提取、chunk 检测/分区、强制对齐、pause 精炼、音素对齐、韵律学习 | domain |
| `application` | 20+ | `AppServices` 编排器、Repository/Provider trait、DTO、按 use case 拆分的应用服务、practice foundation | domain, subtitle-core, diagnosis-core, speech-analysis |
| `dictionary-provider` | 1 | 词典查询 provider | application, domain |
| `persistence-sqlite` | 14+ | SQLite 连接/迁移、按 repository/表域拆分的持久化实现、幂等、唯一约束 | application, domain |
| `api-http` | 7 + `routes/` 10 | Axum HTTP 入口、route group handler、转录/音素/chunk/practice API、Bearer 认证 | application, api-events, dictionary-provider, persistence-sqlite |

### apps/desktop/ — Flutter macOS 应用

| 目录/文件 | 职责 |
|---|---|
| `lib/main.dart` | 应用入口，`AppControllers` 初始化，Rust sidecar 启动 |
| `lib/controllers/` | 5 个 ChangeNotifier 控制器（Player/Subtitle/Learning/Settings/AppControllers） |
| `lib/models/` | 数据模型（`timeline.dart` 等） |
| `lib/services/` | `api_service.dart`（Rust HTTP 通信）、`external_tools.dart`（ffmpeg 适配） |
| `lib/widgets/` | UI 组件树：player/panels/subtitle/vocabulary/settings |
| `lib/screens/` | 全屏页面（vocabulary_screen） |
| `lib/utils/` | 格式化、字幕定位、字幕样式、词表解析 |
| `test/` | 10 个 Flutter 测试文件 |

### scripts/ — 工具脚本

| 路径 | 语言 | 职责 |
|---|---|---|
| `test.sh` | Bash | 统一测试编排（Rust+Flutter+契约，4 模式） |
| `validate-contracts.sh` | Bash | LLTimeline Schema smoke |
| `timeline-production/` | Python | 生产管线 CLI（doctor/prepare/run-whisperx/produce） |
| `forced-align/` | Python | MMS_FA 强制对齐 sidecar |
| `evaluate-word-timelines.py` | Python | 词级时间轴比较评估 |
| `phonetic-eval.py` | Python | 音素分析评估引擎 |
| `verify-m*.sh` | Bash | M1.x 里程碑验收脚本 |

### testdata/ — 测试数据

| 目录 | 内容 |
|---|---|
| `subtitles/` | SRT/VTT 样本 |
| `asr/` | whisper.cpp DTW JSON 样本 |
| `chunk/` | Chunk 分区金标准用例 |
| `word-timelines/` | Gold/Baseline/Candidate 时间轴 |
| `lltimeline/` | LLTimeline v1 最小有效文档 |
| `pronunciation/` | 100 句英语发音基线 |
| `phonetic-analysis/` | M2.0 音素评估用例（60 个） |
| `timeline-production/` | WhisperX 样本输出 |
| `generated/` | 程序生成的测试媒体（.gitignore） |

## 3. 命名约定

### Rust

| 维度 | 约定 |
|---|---|
| Crate 名 | kebab-case（`subtitle-core`, `speech-analysis`） |
| 源文件 | snake_case（`asr_timing.rs`, `chunk_detection.rs`） |
| 类型/Struct/Enum | PascalCase（`WordTimeline`, `DomainError`） |
| 函数/方法 | snake_case（`parse_srt`, `from_fingerprint`） |
| 常量 | UPPER_SNAKE_CASE（`DICTIONARY_CACHE_TTL_MS`） |
| 测试模块 | 小模块可同文件；跨模块 fixture 放 `src/tests.rs` |
| 集成测试 | `crates/<crate>/tests/*.rs` |

### Flutter (Dart)

| 维度 | 约定 |
|---|---|
| 文件名 | snake_case（`subtitle_controller.dart`） |
| 类名 | PascalCase（`SubtitleController`, `ApiService`） |
| 函数/变量 | camelCase（`fromJson`, `primaryTrack`） |
| 私有成员 | 无前缀（Dart 默认） |
| 测试文件 | `test/<name>_test.dart`，与源文件对应 |

### Python

| 维度 | 约定 |
|---|---|
| 脚本名 | snake_case（`production_pipeline.py`, `align-cli.py`） |
| CLI 入口 | `<功能>-cli.py` 或 `<功能>.py` |

## 4. 新代码应该放哪

| 场景 | 位置 |
|---|---|
| 新增领域类型/ID | `crates/domain/src/lib.rs` |
| 新增字幕格式解析 | `crates/subtitle-core/src/lib.rs` |
| 新增诊断规则 | `crates/diagnosis-core/src/lib.rs` |
| 新增语音分析模块 | `crates/speech-analysis/src/<module>.rs` |
| 新增用例编排逻辑 | `crates/application/src/<use_case>.rs`；仅共享 glue 留在 `lib.rs` |
| 新增 HTTP 路由 | `crates/api-http/src/routes/<route_group>.rs` → 在 `lib.rs` 注册 |
| 新增 DB 表/迁移 | `crates/persistence-sqlite/src/migrations.rs` + 对应 repository 模块 |
| 新增 SSE 事件类型 | `crates/api-events/src/lib.rs` |
| 新增 Flutter UI 组件 | `apps/desktop/lib/widgets/<panel>/<name>.dart` |
| 新增 Flutter 数据模型 | `apps/desktop/lib/models/<name>.dart` |
| 新增 Python 管线步骤 | `scripts/timeline-production/production_pipeline.py` |
| 新增测试数据 | `testdata/<category>/` |
| 新增 ADR 决策 | `docs/decisions/NNNN-description.md`（递增编号） |
| 技术 spike | `spikes/<topic>/` |

## 5. 特殊目录

| 目录 | 性质 | 说明 |
|---|---|---|
| `target/` | 构建产物 | .gitignore，`cargo build` 生成 |
| `dist/` | 发布产物 | .gitignore，Flutter 打包输出 |
| `testdata/generated/` | 程序生成 | .gitignore，测试运行时生成 |
| `third_party/fvp/` | 本地 fork | 提交到 git，FFmpeg 播放器 fork |
| `.claude/` | Claude Code 配置 | 提交到 git，会话指令和设置 |
| `.planning/phases/*/` | Phase 文档 | 完成即冻结 |
# Phase 3.15.8 structure delta (2026-07-16)

- `crates/embedding-provider/`: local FastEmbed model lifecycle and compatible HTTP adapter.
- `crates/application/src/semantic_embedding.rs`: provider port and semantic read use cases.
- `crates/domain/src/semantic_embedding.rs`: typed descriptor/capability/source/search/enrichment DTOs.
- `crates/persistence-sqlite/migrations/0042_semantic_embedding_index.sql`: disposable vector projection.
- `apps/desktop/lib/models|services/api/semantic_embedding.dart`: typed Dart contract; vocabulary screen
  currently supplies the minimal opt-in install/rebuild/query consumer.
- `spikes/semantic-embedding/`: reproducible real-model spike, excluded from production workspace.
