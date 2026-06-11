# Milestone 2.0：真实语流分析

## Summary

发布版本 `0.8.0`。本阶段在 Milestone 1.9 已建立的规范发音、token 映射、词级
时间轴和规则提示之上，引入真实音频音素识别能力，尝试回答：

> 说话者在这段音频中实际上发出了哪些音素，它们与规范发音有什么差异？

本阶段的目标不是让模型直接输出“发生了连读或弱读”这样的不可解释标签，而是
先得到带时间和置信度的实际音素序列，再将其与规范发音和规则候选对齐，由
确定性的分析服务生成可解释发现。

真实语流分析属于高风险研究能力。Milestone 2.0 必须先通过候选模型基准测试。
如果没有候选 Provider 达到最低质量门槛，则不得把结果标记为
`detected_in_audio`，也不得为了按期发布而伪装成可靠检测。

## Product Goals

完成后，用户能够：

1. 对当前字幕句或整条学习字幕启动本地真实语流分析。
2. 查看真实音频中检测到的宽式音素序列、时间位置和置信度。
3. 对比规范发音、规则候选与音频检测结果。
4. 查看高置信度弱读、省音、闪音、同化、缩约等发现及其音频证据。
5. 随播放位置查看当前词和当前检测音素。
6. 明确区分“规范发音”“规则预测”“对齐支持”和“音频检测”。
7. 在模型不可用、结果低置信或分析失败时继续正常使用播放器与 M1.9 能力。

## Execution Order

实施顺序固定为：

1. 研究基准、许可证审查与发布决策门
2. Provider、模型、任务和音素时间轴公共契约
3. 本地音频范围分析与结果持久化
4. 实际音素到字幕 token、规范音素的对齐
5. 可解释真实语流发现
6. 桌面分析体验与音素级播放交互
7. 自动验收、真实材料评估、打包与用户协同验收

Phase 0 未通过前，不得将任何候选模型集成为默认正式 Provider。

## Phase 0：研究与质量门槛

### 固定评估集

建立版本化评估集，至少包含：

- 50 至 100 条美式新闻、访谈和自然对话句子。
- 常速、快速语流、不同说话者和不同录音质量。
- 弱读、闪音、`t/d` 省音、缩约、同化、词边界连接等目标现象。
- 人工核对的字幕、词范围和尽可能可靠的实际音素参考。
- 明确的许可证和不可随应用分发的数据说明。

Buckeye Corpus 可用于研究和验证，但在确认许可前不得随应用、测试包或模型发布。

### 候选 Provider

至少评估：

- Wav2IPA/Buckeye 方向的美式英语模型。
- ZIPA 小型模型。
- Wav2Vec2Phoneme 或等价可本地部署模型。
- Allosaurus 仅作为研究基线；其 GPL-3.0 约束使其不得默认打包进当前产品。

评估维度：

- Phone Error Rate 或等价音素识别指标。
- 实际弱读、省音和闪音是否被保留，而非被规范化回标准发音。
- 音素时间戳稳定性。
- 音素到字幕词的关联覆盖率。
- 高置信规则发现的人工精确率。
- Apple Silicon 推理速度、内存、模型体积和功耗。
- 许可证、模型数据来源和分发权利。

### 发布门槛

选中的正式 Provider 至少满足：

- 分析结果时间单调且位于请求音频范围内的比例不低于 95%。
- 音素能够关联回字幕 token 的覆盖率不低于 85%。
- 在固定评估集上，高置信语流发现人工精确率不低于 75%。
- 对无法可靠判断的结果能够降级为低置信或未知，而不是强行给出结论。
- 模型许可证、训练数据来源和应用分发方式已记录并可接受。
- 在目标 Apple Silicon 设备上的分析速度和资源占用达到 ADR 中锁定的门槛。

若候选模型未达到高置信发现门槛，可以继续提供研究报告或原始实验工具，但
Milestone 2.0 不得以“真实语流分析完成”收口。

Phase 0 输出：

- 候选模型基准报告。
- 模型与许可证 ADR。
- 选定 Provider，或明确的“无可发布 Provider”结论。
- 固定评估集与可重复运行的评估脚本。

## Core Contracts

### PhoneticTranscriptionProvider

新增独立于普通 ASR 的真实音素转写契约：

```text
PhoneticTranscriptionProvider
- provider_id
- capabilities
- supported_languages
- supported_dialects
- phone_sets
- compatible_models
- transcribe_audio_range
- cancel
- diagnostics
```

公共契约不得暴露 PyTorch、Transformers、Core ML、GGML 或某个候选模型的类型。

### Runtime And Model

复用 M1.7 的 Provider、Runtime、Model、Profile 思路，但真实语流模型与 ASR
模型使用独立能力声明和模型目录。

每个模型记录：

- 稳定 ID、revision、checksum、大小和下载来源。
- 支持语言、口音和音素体系。
- 时间戳能力、预期输入格式和上下文范围。
- 许可证、训练数据 provenance 和分发限制。
- 经过应用验证或用户自定义状态。

模型不进入默认安装包。安装必须由用户明确确认，支持下载取消、checksum 校验、
删除和自定义模型注册。

### Phonetic Analysis Job

新增持久化分析任务：

```text
queued -> extracting -> recognizing_phones -> aligning -> analyzing -> completed
```

另含：

```text
cancelled | failed | interrupted
```

任务支持两种范围：

- 当前字幕句或用户选择范围的按需分析。
- 整条字幕轨的后台批量分析。

默认只运行一个高负载音素分析任务。播放不得被阻塞。取消、失败或重启后必须终止
子进程并清理临时文件，不发布半成品正式分析结果。

### Detected Phone Timeline

输出结构至少包含：

```text
DetectedPhone
- symbol
- phone_set
- start_ms
- end_ms
- confidence
- provider_id
- model_revision
```

所有时间使用媒体绝对整数毫秒。原始 Provider 音素体系必须保留，显示层可以映射
为 IPA，但映射不得覆盖原始结果。

### PronunciationAnalysisService

确定性分析服务负责：

1. 读取 M1.9 规范音素与规则候选。
2. 读取真实音频检测音素。
3. 使用可测试的动态规划或等价算法完成序列对齐。
4. 将音素范围关联回字幕 token。
5. 生成带证据、置信度和差异类型的发现。

发现结构：

```text
finding_type
affected_token_range
canonical_phones
detected_phones
aligned_phone_range
audio_start_ms
audio_end_ms
confidence
evidence
status
```

本阶段允许新增状态：

```text
supported_by_alignment | detected_in_audio
```

只有达到已校准置信度门槛的结果才能使用 `detected_in_audio`。低置信结果必须显示
为“不确定”或仅展示原始音素，不生成确定性教学结论。

## Data And Persistence

数据库升级至 schema v9，新增：

- 已安装、下载中和自定义真实语流模型记录。
- 持久化 `PhoneticAnalysisJob` 与任务配置快照。
- 检测音素时间轴及 Provider/model provenance。
- 规范音素与检测音素的对齐结果。
- 真实语流发现、置信度、证据和分析器版本。
- 用户确认、驳回或忽略某条发现的反馈。

持久化策略：

- 原始媒体或模型缺失后，已完成结果仍可查看。
- Provider、模型 revision、字幕版本、音频轨或设置变化时创建新分析版本，不覆盖
  旧结果。
- 自动生成结果可删除和重建，不进入词汇资产备份。
- 用户对发现的确认、驳回和笔记属于用户资产，必须进入后续版本化备份。
- 真实语流分析不得自动修改全局词汇状态或上下文观察。

设置升级至 v8，保存：

- 默认真实语流 Provider 与模型档位。
- 默认按需或批量分析偏好。
- 仅显示高置信发现或显示实验结果。
- 音素级播放高亮开关。
- 临时文件与缓存保留策略。

## API And Events

保持 `/v1`，新增：

- `GET /v1/phonetic-analysis/providers`
- `GET /v1/phonetic-analysis/models`
- `POST /v1/phonetic-analysis/models/install`
- `POST /v1/phonetic-analysis/models/register-custom`
- `POST /v1/phonetic-analysis/models/{id}/cancel-install`
- `DELETE /v1/phonetic-analysis/models/{id}`
- `GET /v1/phonetic-analysis/jobs`
- `POST /v1/phonetic-analysis/jobs`
- `GET /v1/phonetic-analysis/jobs/{id}`
- `POST /v1/phonetic-analysis/jobs/{id}/cancel`
- `POST /v1/phonetic-analysis/jobs/{id}/retry`
- `GET /v1/subtitles/{track_id}/phonetic-analyses`
- `GET /v1/phonetic-analysis/{id}/findings`
- `PUT /v1/phonetic-analysis/findings/{id}/feedback`

扩展 SSE 事件：

- 模型下载和校验进度。
- 任务阶段、进度、取消、失败和完成。
- 分析版本失效和降级原因。

词级和音素级播放高亮继续由客户端本地时间轴驱动，不通过 API 高频轮询。

## Desktop Experience

### 分析入口与任务中心

- 当前字幕句菜单增加“分析真实发音”。
- 字幕轨菜单增加“分析整条字幕”。
- 无模型时进入模型管理器，并明确展示模型大小、许可、实验状态和资源需求。
- 任务中心展示音频提取、音素识别、对齐、分析和完成状态。
- 支持取消、重试、查看诊断和使用另一模型重新分析。

### 三层结果展示

学习面板必须清晰分层：

1. **规范发音**：来自词典或 G2P。
2. **规则预测**：仅根据文本和上下文推测。
3. **音频检测**：来自真实音频模型，并显示置信度和证据。

不得只用颜色暗示来源差异。每层必须有文字标签、Provider/model provenance 和
置信说明。

### 播放交互

- 在已有当前词高亮基础上，可选显示当前检测音素。
- 点击检测音素或发现可循环对应音频范围。
- 用户可以对发现标记“符合听感”“不准确”或“忽略”。
- 分析失败、低置信或模型缺失时自动回退到 M1.9 规范发音和规则提示。
- 音素高亮不得改变视频尺寸、字幕位置或字幕整体布局。

### 学习诊断

- “认识但听不出”单词可关联高置信真实语流发现，作为可解释诊断线索。
- 诊断只展示证据，不自动改变用户词汇状态。
- 对模型不确定、字幕可能错误或词音对齐失败的情况给出明确提示。

## Verification

新增 `scripts/verify-m20.sh`，并回归全部历史自动验收。

自动测试至少覆盖：

- schema v1-v8 到 v9 和设置旧版本到 v8 的迁移。
- fake Provider 的成功、部分结果、取消、失败、重试、中断和幂等行为。
- 模型下载中断、checksum 错误、不兼容模型、许可证缺失和空间不足。
- 检测音素时间单调性、范围约束、音素体系保留和 IPA 显示映射。
- 规范音素与检测音素的插入、删除、替换和合并对齐。
- 弱读、省音、闪音、同化、缩约发现的证据与置信度。
- 低置信结果不得错误升级为 `detected_in_audio`。
- 字幕或模型 revision 变化时创建新分析版本，不覆盖旧结果。
- 原始媒体或模型删除后，已完成结果仍可查看。
- 快速跳转、循环、倍速和拖动后音素高亮正确。
- 后台批量分析期间播放和字幕交互保持可用。
- macOS Apple Silicon 打包、运行时发现和签名检查。

真实模型验证必须运行 Phase 0 固定评估集，并生成可重复的质量报告。

## Collaborative Acceptance

用户人工验收项目：

1. 对当前字幕句启动分析并查看真实检测音素、时间和置信度。
2. 对整条字幕启动后台分析，播放期间任务不会阻塞播放器。
3. 学习面板能够明确区分规范发音、规则预测和音频检测。
4. 点击检测音素或发现能够循环正确音频范围。
5. 当前词和当前音素随播放位置正确变化。
6. 对真实包含弱读、闪音、省音、缩约或同化的材料，系统能够展示可解释证据。
7. 对不确定材料，系统不会给出过度确定的结论。
8. 用户确认或驳回发现后，反馈能够持久保存。
9. 删除模型或移动媒体后，已有分析结果仍可查看并明确显示不可重算原因。
10. 禁用真实语流分析后，M1.9 规范发音、规则提示和播放器功能保持正常。

## Completion Gate

Milestone 2.0 只有在以下条件全部满足后才算完成：

- Phase 0 候选模型基准、许可证审查和 ADR 完成。
- 正式 Provider 达到发布门槛；否则本里程碑保持未完成。
- 所有自动测试、历史回归和真实评估集验证通过。
- macOS Apple Silicon 安装包构建并通过 smoke test。
- 用户完成协同人工验收并明确确认功能无误。
- 更新 README、Changelog、roadmap、requirements、API 契约、模型说明和验证报告。
- 创建收口提交与 `v0.8.0` Git 标签。

## Explicit Boundaries

- 不承诺稳定输出狭式 IPA 或所有细粒度异音。
- 不将低置信模型结果包装为确定事实。
- 不自动修改用户词汇状态、听懂观察或学习资产。
- 不实现实时麦克风分析、跟读评分或发音纠错。
- 不在许可证不明确时分发模型或训练数据。
- 不要求训练自有模型；只有候选模型未达门槛且另行批准后才进入训练计划。
- 不实施 Windows、Linux、移动端或云端真实语流分析。

