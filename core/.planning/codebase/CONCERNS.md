# LLPlayerNext — 代码库问题清单

> 最后更新：2026-06-21
> 记录已知的技术债、脆弱区域和需要关注的问题。**每条必须包含文件路径。**

---

## 1. 技术债

### `api-http` 直接耦合 `speech-analysis` ✅ 已处理

- **文件**：`crates/api-http/src/routes/transcription.rs`, `crates/api-http/src/routes/phonetic_analysis.rs`, `crates/api-http/src/routes/speech.rs`, `crates/api-http/Cargo.toml`
- **问题**：HTTP handler 直接调用 `speech_analysis::asr_timing`、`forced_align`、`pause_refinement` 等模块，跳过了 `application` 编排层
- **影响**：修改语音分析模块可能直接破坏 HTTP API；无法在 `application` 层统一缓存/错误处理/日志
- **修复思路**：所有语音分析调用通过 `AppServices` trait 方法间接访问；在 `application` 层增加编排逻辑
- **当前状态**：M2.1 / Phase 2.3.5 已处理 `crates/api-http/src/routes/transcription.rs` 的
  `asr_timing` / `forced_align` / `pause_refinement` 编排耦合，转录 word timeline
  精炼已下沉到 `AppServices::refine_transcription_word_timelines`；也已处理
  `crates/api-http/src/routes/phonetic_analysis.rs` 的 research fixture phone alignment /
  finding 生成耦合，改由 `AppServices::build_research_fixture_phonetic_analysis` 构造。
  `crates/api-http/src/routes/timelines.rs` 的 chunk partition 返回类型和 learned prosodic provider
  装配也已改为通过 application 暴露的类型/方法访问；`crates/api-http/src` 不再直接
  引用 `speech_analysis`，`api-http` 的 Cargo 直接依赖也已移除。

### `speech-analysis` 职责过重

- **文件**：`crates/speech-analysis/src/`（11 个模块）
- **问题**：一个 crate 覆盖了 ASR 后处理、chunk 检测/分区、强制对齐、pause 精炼、音素对齐、韵律学习四个不同关注点
- **影响**：模块间隐式耦合；新贡献者难以定位代码；测试运行慢
- **修复思路**：M2.0 稳定后考虑拆分为 `acoustic-analysis` + `phonetic-analysis` + `chunk-engine`

### Rust 模块边界回归风险

- **文件**：`crates/persistence-sqlite/src/lib.rs`、`crates/application/src/lib.rs`、`crates/api-http/src/lib.rs`、`crates/api-http/src/routes/`
- **问题**：Phase 2.3.5 已完成三个核心 crate 的 mechanical decomposition；后续新增功能如果继续堆回 root `lib.rs`，会重新形成导航和合并冲突风险。
- **影响**：ChunkTimeline / PhoneTimeline 等后续阶段需要跨 API、application、persistence 修改，模块边界回归会放大变更成本。
- **安全修改方式**：新增 repository 逻辑进入 `persistence-sqlite/src/<domain>.rs`；新增 use case 进入 `application/src/<use_case>.rs`；新增 HTTP handler 进入 `api-http/src/routes/<route_group>.rs`；`lib.rs` 只保留装配、re-export 和必要共享 glue。
- **当前状态**：`persistence-sqlite/src/lib.rs` 约 19 行、`application/src/lib.rs` 约 609 行、`api-http/src/lib.rs` 约 496 行；`domain/src/lib.rs` 仍约 1317 行，但暂不阻塞 Phase 2.4。

### Flutter sidecar 路径查找脆弱

- **文件**：`apps/desktop/lib/services/api_service.dart`
- **问题**：从 CWD 向上遍历找 `target/release/api-http`，开发环境和生产包路径不同
- **影响**：发布包中可能找不到 Rust 二进制
- **修复思路**：生产发布包固化 sidecar 路径（macOS bundle 内嵌）

### Python 管线缺少单元测试

- **文件**：`scripts/timeline-production/production_pipeline.py`, `scripts/forced-align/align-cli.py`
- **问题**：核心函数（音频预处理、WhisperX JSON 转换）缺少 pytest 单元测试
- **影响**：管线重构时容易引入回归
- **修复思路**：为核心转换函数添加 pytest，纳入 CI

---

## 2. 脆弱区域

### Persistence 迁移链

- **文件**：`crates/persistence-sqlite/src/migrations.rs`, `crates/persistence-sqlite/src/*.rs`
- **脆弱原因**：10 个迁移版本线性依赖，任一迁移 bug 可导致数据库损坏
- **常见故障**：迁移失败后无自动回滚；预迁移备份是手动操作
- **安全修改方式**：新增迁移前在副本数据库上验证；不修改已有迁移
- **测试覆盖**：有迁移前备份，但缺少迁移失败恢复的自动化测试

### 音频预处理管线

- **文件**：`scripts/timeline-production/production_pipeline.py`
- **脆弱原因**：依赖外部 ffmpeg（版本/编码器差异）；人声分离模型输出不稳定
- **常见故障**：ffmpeg 版本不兼容导致音频抽取失败；非英语音频人声分离质量差
- **安全修改方式**：修改管线步骤后运行 `--doctor` 验证环境；保留上一步中间产物
- **测试覆盖**：有手动验收（CNN10/NBC 新闻），无自动化回归

### Rust-Flutter 通信握手

- **文件**：`crates/api-http/src/main.rs`, `apps/desktop/lib/main.dart`
- **脆弱原因**：随机端口 + Bearer token JSON handshake 通过 stdout 传递
- **常见故障**：端口冲突、token 解析失败、sidecar 启动超时
- **安全修改方式**：修改握手协议需两端同步；加超时和重试
- **测试覆盖**：Flutter `api_service_test.dart` 覆盖客户端侧，无握手协议集成测试

---

## 3. 测试覆盖缺口

| 缺口 | 优先级 | 文件 | 风险 |
|---|---|---|---|
| `application` 层集成测试 | P1 | `crates/application/` 缺少 `tests/` 目录 | 用例编排逻辑只在 E2E 层面间接验证 |
| `api-http` 路由集成测试 | P1 | `crates/api-http/` 缺少请求-响应测试 | 路由错误映射、认证中间件未经自动化验证 |
| Python 管线单元测试 | P2 | `scripts/timeline-production/` | 见上 |
| Flutter widget 交互测试 | P2 | `apps/desktop/test/` | 播放器/字幕点击/拖放无测试 |
| 跨语言 E2E 测试 | P2 | — | 生产管线 → 导入 → 播放链无自动化验证 |
| 迁移失败恢复测试 | P2 | `crates/persistence-sqlite/` | 见脆弱区域 |
| sidecar 握手集成测试 | P2 | `crates/api-http/` + `apps/desktop/` | 见脆弱区域 |

---

## 4. 依赖风险

| 依赖 | 风险 | 影响 |
|---|---|---|
| WhisperX | 上游更新可能改变输出格式 | 对齐 JSON schema 变化会破坏管线 |
| torchaudio MMS_FA | 研究模式，TorchScript 绑定脆弱 | 对齐失败只能回退到 DTW |
| fvp (mdk/FFmpeg) | 本地 fork，需自行维护 | 上游安全更新需手动合并 |
| rusqlite bundled | SQLite 随 crate 编译，更新需重新构建 | 安全补丁依赖 crate 发版 |

---

## 5. 性能关注点

| 操作 | 预估耗时 | 文件 | 改进方向 |
|---|---|---|---|
| WhisperX 全量转录（30min 音频） | 5-15 分钟 | `production_pipeline.py` | GPU 加速已启用，CPU 回退慢 |
| 数据库全量迁移（M1.0→M1.9） | ~5 秒 | `persistence-sqlite/src/migrations.rs` | 可接受；大数据量后考虑增量迁移 |
| Flutter 首次加载字幕 | ~500ms | `subtitle_controller.dart` | 大文件（>5000 句）后考虑虚拟滚动 |

---

*清单更新：2026-06-21*
*问题解决后删除对应条目，新发现问题随时追加*
