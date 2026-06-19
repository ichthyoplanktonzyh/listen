# LLPlayerNext — 项目活记忆

> 最后更新：2026-06-19 16:10 CST
> 更新原因：Phase 2.1 application 编排下沉完成，Phase 2.2 保持待启动

## 当前位置

- **里程碑**：Milestone 2 — 本地重装生产引擎
- **Phase**：Phase 2.1 — 对齐管线加固（阶段性结束，准备进入 2.2）
- **分支**：`feature/forced-alignment-research`
- **版本**：0.7.0

## 项目双路线

自 2026-06-18 起，项目拆分为两条协同路线：

| 路线 | 目标 | 当前状态 |
|---|---|---|
| 本地重装生产引擎 | 生成精准 WordTimeline / ChunkTimeline / LLTimeline JSON | ✅ 阶段性收口，转长期研究 |
| 轻量消费端 LLPlayerNext | 稳定读取 `.lltimeline.json` 并播放学习 | ⏳ Phase 2.2 待启动 |

## 当前 Phase 状态

### Phase 1: LLTimeline JSON v1 核心契约 ✅
- Schema `llplayer.timeline.v1` 已定义
- metadata / segments / words / phonemes / chunks / artifacts 结构完整
- 导入导出 round-trip 测试通过

### Phase 2: 时间轴资源生命周期 ✅
- 版本化 WordTimeline 资源 CRUD
- activate / publish / archive 状态机
- `lltimeline-resource.py` 管理工具

### Phase 3: 生产管线 V1 ✅
- WhisperX ASR + 强制对齐集成
- `produce-whisperx` 端到端命令可用
- 音频预处理（16kHz mono WAV 提取）
- 可选人声分离（Demucs）
- WhisperX JSON → LLTimeline v1 转换
- `production-report.json` 记录覆盖率、overlap/gap、provider 和人工复核准备状态

### Phase 4: 客观评估体系 ✅ 暂时收口
- TIMIT 已接入为高质量 gold resource。
- `compare-lltimeline` 可比较同一 `.lltimeline.json` 内的 baseline/candidate/gold
  word timeline，并输出 P95、tail lag、coverage、overlap/gap 等指标。
- 已完成 MMS_FA、完整 WhisperX CLI、WhisperX+MMS_FA、MFA `align-one` 的首轮
  TIMIT TEST 100 对比。
- 结论：MFA `english_us_arpa + align-one` 是当前高质量 transcript 条件下最强的
  已观测词边界对齐器；MMS_FA 保留为轻量 fallback；Qwen3/BFA 等路线进入长期研究。

### Phase 2.1: 对齐管线加固 ✅ 阶段性结束
- P0 word_index 占位契约已完成。
- P1 tokenizer/evaluation guardrail 已完成。
- application `WordTimelinePipeline` 编排下沉已完成，api-http 转录流程不再直接调用
  `speech_analysis::{asr_timing, forced_align, pause_refinement}`。
- phonetic research fixture 的 phone alignment / finding 构造已下沉到 application。
- `crates/api-http/src` 已移除对 `speech_analysis` 的直接引用。
- production pipeline 已支持可插拔 post-aligner：
  `none|auto|mfa|mms-fa`。
- `auto` / `mfa` 按 MFA -> MMS_FA -> WhisperX 原始时间轴降级。
- P3 evaluate stats 去重已完成。
- persistence/application 巨型文件拆分、monotonicity 消融转为独立后续架构债，
  不阻塞 Phase 2.2。

### Phase 2.2: App Timeline Resource UI Alignment ⏳ 待启动
- 目标：让 app 端能导入、展示、选择、激活和消费 `.lltimeline.json` 里的
  WordTimeline 资源。
- 当前生产端资源策略：
  `WhisperX -> optional post-aligner auto|mfa|mms-fa|none -> LLTimeline JSON`。
- `auto` / `mfa` 按 MFA -> MMS_FA -> WhisperX 原始时间轴降级。
- 下一步先做资源可见性和 active timeline 切换，再进入人工校正与 chunk 生成。

### Phase 2.3: 人工校对 UI ⏳ 后续
### Phase 2.4: ChunkTimeline 生成与消费 ⏳ 后续

### 强制对齐研究 🧭 长期推进
- torchaudio MMS_FA sidecar（`scripts/forced-align/align-cli.py`）。
- MFA research sidecar（`scripts/forced-align/mfa-align-cli.py`）。
- Qwen3-ForcedAligner、BFA/easytranscriber/CTC 暂列 deferred research。
- 研究结果必须通过统一 LLTimeline schema、tokenizer 和 benchmark 体系后再晋级主线。

## 最近重要决策

1. **2026-06-18 14:50** — 产品重构：从单一消费端拆分为生产引擎 + 消费端两条路线
2. **2026-06-18** — 引入 GSD 文档体系，建立 `.planning/` 目录
3. **生产端策略**：WhisperX 负责高质量 transcript/VAD，后处理 aligner 可选
   MFA/MMS_FA/未来候选，最终统一输出可复用 `.lltimeline.json`
4. **降级策略**：生产端 `auto` 路线按 MFA -> MMS_FA -> WhisperX 原始时间轴降级；
   app 端不得依赖重型 runtime

## 当前阻塞项

无。

## 下一步工作

1. 启动 Phase 2.2：审计 app 端 `.lltimeline.json` import/export、WordTimeline summary、activate
   和播放器高亮绑定。
2. 设计并实现 Timeline Resource Summary UI。
3. 支持 WordTimeline 候选列表和 active timeline 切换。
4. 验证播放器词级高亮使用 active WordTimeline，且无资源时旧路径正常降级。

## 指标

- 已完成里程碑：M1.0, M1.5, M1.6, M1.7, M1.8, M1.9
- 活跃分支领先 main：持续增长，以 git log 为准
- 生产管线每天可处理的新闻视频：1-2 条（当前为手工触发）
