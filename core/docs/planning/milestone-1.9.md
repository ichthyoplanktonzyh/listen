# Milestone 1.9：发音与词级同步基础

## Summary

发布版本 `0.7.0`。本阶段把 LLPlayerNext 从“文字字幕上的词汇状态播放器”
推进为“能够展示规范发音、解释常见语流规则，并跟随音频高亮当前词”的听力
学习工具。

首版以美式英语为默认目标，但所有公共契约必须声明语言、口音、音素体系、
Provider、版本和证据来源，不得将美式英语或某个 G2P、ASR、对齐工具硬编码到
领域模型中。

本阶段只提供规范发音和基于规则的语流变化候选。规则提示必须明确标为
“可能发生”或“上下文推测”，不得冒充从真实音频中检测出的结果。真实音频
音素识别与真实语流分析属于 Milestone 2.0。

## Product Goals

完成后，用户能够：

1. 查看当前字幕句的规范美式英语音标，并看到音标与字幕 token 的对应关系。
2. 查看每个单词的重音、规范发音和可选发音变体。
3. 在播放过程中看到当前说到的单词高亮或跳动。
4. 区分词级时间来源是 ASR 时间戳、强制对齐结果还是估算值。
5. 查看弱读、连读、缩约、闪音、省音和同化等规则候选及其解释。
6. 将发音、规则提示和词汇状态结合，判断“认识但听不出”的可能原因。
7. 在缺少 CMUdict、网络或精确词级时间时安全降级，不影响现有播放和学习流程。

## Execution Order

实施顺序固定为：

1. 工程边界检查与技术 Spike
2. 发音、音素和词级时间公共契约
3. 规范发音与整句音标
4. 词级同步与字幕播放交互
5. 规则型连续语流提示
6. 缓存、设置、诊断与桌面体验
7. 自动验收、macOS 打包与用户协同验收

在进入下一阶段前，上一阶段的领域测试、契约测试和关键桌面回归必须通过。

## Phase 0：工程检查与技术 Spike

在修改正式领域模型前完成以下验证：

- 审计当前字幕 token、短语 token range、ASR 生成轨和播放器本地时间轴，确定
  词级时间与现有结构的映射方式。
- 验证 CMUdict 数据包的许可证、格式、重音信息和常用美式英语覆盖率。
- 比较确定性 CMUdict 回退规则与 Misaki-RS 等上下文 G2P 候选的准确率、
  许可证、维护状态和集成成本。
- 验证当前 whisper.cpp Provider 是否能够稳定输出词或 token 时间戳，并记录
  其时间粒度和限制。
- 为没有词级时间的普通 SRT/VTT 设计确定性估算算法，保证时间单调、范围不越过
  字幕句，并明确标记为估算。
- 使用至少 100 条美式英语字幕句建立固定基准集，覆盖常见词、专有名词、数字、
  缩写、多音词、标点、短语和未知词。

Spike 结束时必须形成 ADR，锁定首个规范发音 Provider、内部音素体系、IPA 映射
方式和词级时间来源优先级。若上下文 G2P 候选尚不可靠，首版使用 CMUdict 加安全
回退，不阻塞本阶段。

## Core Contracts

### PronunciationProvider

建立 Provider 中立的规范发音契约：

- 稳定 Provider ID、显示名称、版本和能力声明。
- 支持的语言、口音和音素体系。
- 单词、短语和整句发音能力。
- 是否支持上下文消歧、多发音变体、重音和 token 映射。
- 结构化错误和安全回退。

首个正式 Provider 使用 CMUdict 与确定性回退。上下文 G2P Provider 只有在
Phase 0 验证通过后才进入正式注册表。

### Phoneme Model

内部新增 Provider 中立的音素结构：

```text
Phoneme
- symbol
- phoneme_set
- display_ipa
- stress
- syllable_index
- token_index
- start_ms?
- end_ms?
- confidence?
```

内部首选 ARPAbet 作为美式英语规范音素表示，UI 使用可替换映射展示 IPA。
领域模型不得假设所有语言都支持 ARPAbet、重音或一对一 IPA 映射。

### AlignmentProvider

定义词级时间对齐契约：

- 输入标准化字幕句、媒体/音频范围和可选已有 ASR 时间元数据。
- 输出每个 lexical token 的开始、结束时间、置信度、来源与 Provider provenance。
- 时间统一使用整数毫秒。
- 能力声明区分词级、音素级、是否需要音频和是否支持离线运行。

词级时间来源优先级：

1. 已验证的 ASR 原生词级时间戳。
2. 未来或可选强制对齐 Provider 的结果。
3. 根据字幕句范围、token 权重和标点停顿生成的估算时间。

任何来源都必须显式保存 `timing_source`：

```text
asr_reported | forced_aligned | estimated | user_adjusted
```

### SpeechRuleAnalyzer

建立独立、确定性、可测试的规则分析器。它接收规范 token、词性/lemma、规范音素
和上下文，不读取真实音频。

每条规则发现包含：

```text
rule_id
rule_family
affected_token_range
canonical_phonemes
suggested_phonemes
confidence
reason
evidence_source
status
```

本阶段状态只允许：

```text
possible_by_rule | likely_by_context | user_confirmed
```

`supported_by_alignment` 和 `detected_in_audio` 保留给 Milestone 2.0。

## Data And Persistence

数据库升级至 schema v8，新增或扩展：

- 规范发音缓存，按语言、口音、规范化文本、Provider ID 和版本独立存储。
- 字幕句级发音分析结果及 token 到音素的映射。
- 词级时间轴、时间来源、置信度和 Provider provenance。
- 规则型语流提示及分析器版本。
- 可选用户发音修正和用户确认的规则提示。
- 分析失效信息，确保 Provider、规则或字幕版本变化后可安全重算。

数据分层：

- 规范发音缓存、估算时间和规则分析可删除并重建，不进入词汇资产备份。
- 用户发音修正和用户确认的规则提示属于用户资产，必须进入后续版本化资产备份。
- 原有词汇状态、短语、来源句、笔记和 ASR 字幕必须无损迁移。

设置升级至 v7，保存：

- 发音显示开关。
- 默认语言与口音，首版默认 `en-US`。
- IPA/Provider 原始音素显示偏好。
- 当前词高亮样式与动画强度。
- 规则提示显示级别。
- 是否允许在空闲时预计算当前字幕轨。

## API And Events

保持 `/v1`，新增 Provider 中立接口：

- `GET /v1/pronunciation/providers`
- `GET /v1/pronunciation/lookup`
- `POST /v1/pronunciation/analyze-sentence`
- `GET /v1/subtitles/{track_id}/pronunciation`
- `POST /v1/subtitles/{track_id}/word-timings`
- `GET /v1/subtitles/{track_id}/word-timings`
- `POST /v1/subtitles/{track_id}/pronunciation-analysis`
- `GET /v1/pronunciation/rules`

分析接口应支持按句惰性生成和按轨批量生成。批量任务必须可取消、可重试，并且
不得阻塞播放。

扩展事件契约，发布：

- 发音分析进度与完成事件。
- 词级时间生成进度与完成事件。
- Provider 不可用、降级和缓存失效事件。

高频当前词切换继续完全在 Flutter 客户端根据已加载的本地词级时间轴执行，
不得依赖 HTTP 高频轮询。

## Desktop Experience

### 字幕与播放

- 当前字幕句可切换显示整句 IPA。
- IPA 与字幕 token 保持可解释映射；点击 IPA 或单词时可定位到对应项。
- 播放时当前词使用高亮或轻量跳动效果，动画不得引起字幕整体重新布局。
- 词级同步关闭时，现有句级字幕行为保持不变。
- 估算时间、ASR 时间和精确对齐结果使用不同但不干扰观看的质量标识。
- 双字幕场景默认只对主学习字幕执行词级同步，副字幕保持普通显示。

### 学习面板

- 展示单词规范发音、重音、可选发音变体和来源 Provider。
- 展示整句规范音标和 token 映射。
- 展示规则型连续语流候选、影响范围、建议发音、原因和置信度。
- 明确显示“这是规则预测，并非真实音频检测”。
- 从“认识但听不出”的单词可直接查看相关发音和规则提示。

### 设置与诊断

- 支持中英文界面文案。
- 用户可控制 IPA、当前词动画和规则提示的显示密度。
- 诊断页面展示 Provider、版本、缓存状态、词级时间来源和降级原因。
- 任何分析失败只影响对应增强功能，不影响播放器、字幕或词汇状态。

## Rule Scope

首版实现约 15 至 25 条高价值美式英语规则，至少覆盖：

- 功能词弱读：`to`、`the`、`can`、`and`、代词和常见助动词。
- 常见缩约与口语形式：如 `want to`、`going to`。
- 辅音到元音连接、相同辅音连接。
- 美式闪音候选。
- `/t/`、`/d/` 省音候选。
- 常见同化候选，如 `did you`。
- 常见多词发音边界和标点停顿。

规则必须有稳定 ID、说明、示例、适用条件、反例和固定测试。低可靠规则不得仅凭
文本显示为高置信结果。

## Verification

新增 `scripts/verify-m19.sh`，并回归全部已有自动验收。

自动测试至少覆盖：

- schema v1-v7 到 v8 迁移和旧数据保留。
- 设置旧版本到 v7 迁移。
- CMUdict 常用词、不规则词、专有名词、缩写、数字和未知词回退。
- 多发音变体、重音、ARPAbet 到 IPA 映射和 token 映射。
- Provider 注册顺序、部分失败、版本失效和缓存隔离。
- ASR 词级时间、估算时间、时间单调性和字幕句边界。
- 快速跳转、倍速、循环和拖动进度条时当前词切换正确。
- 规则分析器的适用条件、反例、置信度和稳定 ID。
- 双字幕、长字幕、短语横线、词汇状态样式与当前词动画不冲突。
- 10,000 个字幕句批量分析时播放器和 UI 不出现可见阻塞。
- macOS Apple Silicon 打包与独立启动。

## Collaborative Acceptance

用户人工验收项目：

1. 打开普通 SRT/VTT，当前词能随播放位置高亮，并明确标记时间为估算。
2. 打开带词级时间的 ASR 字幕，当前词同步精度明显优于估算结果。
3. 跳转、循环、暂停、倍速和拖动进度条后，当前词状态立即恢复正确。
4. 当前句能够显示完整规范 IPA，且单词与音标映射清晰。
5. 常见单词显示美式发音、重音和来源；未知词能够安全回退。
6. 弱读、连读、缩约、闪音、省音和同化候选具有明确解释。
7. 所有规则提示均清楚说明不是从真实音频中检测出的结论。
8. 当前词动画不会改变视频大小、字幕位置或字幕整体布局。
9. 关闭发音和词级同步增强后，播放器行为与上一版本一致。
10. 重启应用后设置保持，缓存可复用，旧学习资产完整。

## Completion Gate

Milestone 1.9 只有在以下条件全部满足后才算完成：

- Phase 0 ADR 完成并记录首个 Provider 与词级时间策略。
- 所有自动测试与历史回归通过。
- macOS Apple Silicon 安装包构建并通过 smoke test。
- 用户完成协同人工验收并明确确认功能无误。
- 更新 README、Changelog、roadmap、requirements、API 契约和验证报告。
- 创建收口提交与 `v0.7.0` Git 标签。

## Explicit Boundaries

- 不声称检测到了真实音频中的弱读、连读、省音、同化或闪音。
- 不实现真实音频到音素序列的模型。
- 不实现音素级实时跳动。
- 不训练或分发新的真实语流模型。
- 不实现用户口语录音、发音评分或跟读打分。
- 不要求 MFA 等重型对齐工具成为默认内置依赖。
- 不实施 Windows、Linux、移动端或云端发音分析。

