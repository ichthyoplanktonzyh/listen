# LLPlayerNext — 项目活记忆

> 最后更新：2026-06-18 16:30 CST
> 更新原因：文档系统重构，引入 `.planning/` 体系

## 当前位置

- **里程碑**：Milestone 2 — 本地重装生产引擎
- **Phase**：Phase 3 — 生产管线 V1（WhisperX）
- **分支**：`feature/forced-alignment-research`
- **版本**：0.7.0

## 项目双路线

自 2026-06-18 起，项目拆分为两条协同路线：

| 路线 | 目标 | 当前状态 |
|---|---|---|
| 本地重装生产引擎 | 生成精准 WordTimeline / ChunkTimeline / LLTimeline JSON | 🔥 活跃开发中 |
| 轻量消费端 LLPlayerNext | 稳定读取 `.lltimeline.json` 并播放学习 | ✅ Milestone 1 完成 |

## 当前 Phase 状态

### Phase 1: LLTimeline JSON v1 核心契约 ✅
- Schema `llplayer.timeline.v1` 已定义
- metadata / segments / words / phonemes / chunks / artifacts 结构完整
- 导入导出 round-trip 测试通过

### Phase 2: 时间轴资源生命周期 ✅
- 版本化 WordTimeline 资源 CRUD
- activate / publish / archive 状态机
- `lltimeline-resource.py` 管理工具

### Phase 3: 生产管线 V1 🔥 进行中
- WhisperX ASR + 强制对齐集成
- `produce-whisperx` 端到端命令可用
- 音频预处理（16kHz mono WAV 提取）
- 可选人声分离（Demucs）
- WhisperX JSON → LLTimeline v1 转换

### Phase 4: 客观评估体系 ⏳ 下一步
- 弱评估：DTW vs WhisperX vs MFA 比较
- Gold benchmark：TIMIT/Buckeye + 新闻自建样本
- 生产质量指标记录

### Phase 5: 人工校对 UI ⏳ 后续
### Phase 6: 消费端集成 ⏳ 后续

### 强制对齐研究 🔥 并行进行
- torchaudio MMS_FA sidecar（`scripts/forced-align/align-cli.py`）
- 研究模式，通过 Rust transcription coordinator 调用
- 失败时回退到 Whisper DTW 时间戳

## 最近重要决策

1. **2026-06-18 14:50** — 产品重构：从单一消费端拆分为生产引擎 + 消费端两条路线
2. **2026-06-18** — 引入 GSD 文档体系，建立 `.planning/` 目录
3. **强制对齐策略**：MMS_FA 作为研究选项，WhisperX 作为主要生产路径

## 当前阻塞项

无。

## 下一步工作

1. 完善 WhisperX 生产管线（错误恢复、进度报告）
2. 建立客观评估体系（`evaluate-word-timelines.py` 基础已有）
3. 创建少量 CNN10 新闻 gold set 样本用于基准测试
4. 消费端 `.lltimeline.json` 导入与词级高亮绑定

## 指标

- 已完成里程碑：M1.0, M1.5, M1.6, M1.7, M1.8, M1.9
- 活跃分支领先 main：76 commits
- 生产管线每天可处理的新闻视频：1-2 条（当前为手工触发）
