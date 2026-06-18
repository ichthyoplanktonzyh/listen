# Production Engine Roadmap

更新时间：2026-06-18 16:06:35 CST

## Goal

建立可评估、可复用、可人工修正的词/音素时间轴资源体系。生产端追求最准确的
word/phone/chunk timeline；轻量消费端读取已产出的资源并提供稳定学习体验。

## Guiding Decisions

- 先做资源契约，再替换算法管线。
- 旧 whisper.cpp ASR/DTW/FA 不立即删除，先作为 `WordTimeline` candidate source。
- 重模型依赖留在本地生产端，不进入普通分发版。
- 人工校正后的 timeline 是新资源，不覆盖算法候选。
- 所有可复用资源都要能导出、导入、评估和版本化。

## Phase 0: Documentation And Boundaries

状态：完成。

交付：

- `docs/timeline-production/` 文档结构。
- `LLTimeline JSON v1` 契约草案。
- 生产端/消费端边界文档。
- changelog 增量记录。

验收：

- 后续时间轴相关文档有固定目录。
- PRD、roadmap、requirements 与本目录方向一致。

## Phase 1: LLTimeline JSON v1 Core

状态：完成。

目标：把时间轴资源包变成代码里的稳定对象。

任务：

1. 新增 Rust domain contract：`LLTimelineDocument`、metadata、segments、
   word timeline refs、phone/chunk/artifact 扩展位。
2. 从现有 subtitle track 和 active/candidate `WordTimeline` 导出 `.lltimeline.json`。
3. 增加 API 导入/导出入口。
4. 增加最小 contract tests，确保 schema、metadata、segments、word timeline 可序列化。
5. 增加 fixture，为后续导入、消费端读取、benchmark 提供样本。
6. 增加开发者文件工具，用于验证、导入、导出 `.lltimeline.json`。

验收：

- 现有 ASR 生成的 active word timeline 能被导出成 `llplayer.timeline.v1`。
- v1 document 可以导入回现有 media/subtitle/word timeline persistence。
- 没有 phone/chunk 时仍是合法 v1 document。
- 旧 word timing API 不受影响。

## Phase 2: Resource Lifecycle

状态：完成。

目标：让一个视频可以拥有多个可管理 timeline 版本。

任务：

1. 区分 algorithm candidate、user-adjusted、published。
2. 支持删除/归档/激活 timeline。
3. 支持重新运行同一 pipeline 并生成新版本。
4. 导入 `.lltimeline.json` 时可创建或更新资源。
5. UI 上能查看当前 active timeline 来源和质量摘要。

验收：

- 用户可以删除或归档旧 ASR 产物。
- 同一媒体下多个候选 timeline 可共存。
- 激活某个 timeline 后，词级高亮和 chunk 划分使用该版本。
- Summary API 可直接展示 algorithm candidate、user-adjusted、published 的资源状态。
- 归档或删除 active timeline 会清空 legacy word timing 兼容缓存并安全降级。

## Phase 3: Production Pipeline V1

状态：进行中。

目标：建立个人本地重装生产管线。

任务：

1. 音频预处理：抽取音轨、标准化、人声分离/VAD。
2. 大模型 ASR：Whisper Large-v3 生成高准确长文本。
3. 强制对齐：WhisperX 生成高精度 word timeline。
4. 可选 MFA/BFA：生成 phone timeline 或更细粒度对齐候选。
5. 保存所有候选到统一 timeline resource。
6. 输出 pipeline report 和 artifacts。

验收：

- CNN10/NBC 样本可稳定跑完并产出 `.lltimeline.json`。
- 同一视频可以比较 DTW、WhisperX、MFA/BFA、人工修正版本。

当前已完成第一批切片：

- 生产端独立脚本目录 `scripts/timeline-production/`。
- `prepare-audio` 用 ffmpeg 抽取 16kHz mono PCM wav。
- `prepare-media` 生成预处理 artifact，并支持外部人声分离命令输出 vocals wav。
- `run-whisperx` 调用本地 WhisperX venv 或自定义命令，输出 WhisperX JSON。
- `from-whisperx-json` 将外部 WhisperX JSON 转换为 `LLTimeline JSON v1`。
- contract validation 覆盖 WhisperX sample -> LLTimeline 转换。

## Phase 4: Evaluation System

目标：停止靠肉眼猜，建立客观评估。

任务：

1. 弱评估：不同 timeline 之间的偏移、覆盖、overlap/gap、尾词 lag。
2. Gold benchmark：TIMIT/Buckeye 小样本 + 自建新闻 gold samples。
3. 指标：word boundary MAE/P95、coverage、monotonicity、chunk boundary delta。
4. 报告：每次 pipeline 运行生成可追踪 evaluation artifact。

验收：

- 每次算法变更都有可比报告。
- 生产端能解释“为什么这个版本更好”。

## Phase 5: Manual Correction Studio

目标：人类可以把算法产物修正为可发布资源。

任务：

1. 词级边界拖拽。
2. chunk 合并/拆分/重命名。
3. silence/breath/speaker_change 标注。
4. 保存为 `user-adjusted` timeline。
5. 导出 published `.lltimeline.json`。

验收：

- 人工修正保留 parent timeline 和审计信息。
- 发布资源可被轻量消费端直接消费。

## Phase 6: Lightweight Consumer Integration

目标：分发版稳定消费生产端资源。

任务：

1. 导入 `.lltimeline.json`。
2. 校验 schema、媒体指纹、时间单调性。
3. 使用 active word timeline 驱动词级高亮。
4. 使用 active chunk timeline 驱动 chunk 播放。
5. 缺资源时保留当前估算/句级降级路径。

验收：

- 没有重模型环境也能获得精准高亮和 chunk 播放。
- 资源版本不兼容时有明确错误或降级提示。
