# 发音规则与连续语流参考

有可以参考的实现与技术，但需要先明确一个结论：

> 目前没有一个成熟开源项目，可以仅根据字幕文本，准确输出“真实说话者发生的全部弱读、连读和省音”。

现有技术主要分成三层：

1. 生成标准或上下文相关发音
2. 根据语言规则推测可能的语流变化
3. 结合真实音频确认实际发音

我们可以组合成熟组件，而不应该从零发明整个体系。

## 最值得参考的项目

### 1. Montreal Forced Aligner

[MFA](https://montreal-forced-aligner.readthedocs.io/en/stable/user_guide/index.html) 是最值得参考的整体技术底座。

它具备：

- 美式英语发音词典
- G2P 生词发音生成
- 一个词的多个发音变体
- 每个发音变体的概率
- 词级和音素级强制对齐
- 基于前后音素的 triphone 声学模型

它的概率词典可以表达：

```text
the → /di/
the → /də/
the → /ði/
the → /ðə/
the → /ə/
```

并为不同形式保存概率。MFA 文档明确展示了 `/ðə/` 等弱读形式在连续语流中更常见。

MFA 对我们最大的价值不是直接嵌入客户端，而是：

- 参考其发音词典和领域模型
- 使用它验证规则分析结果
- 后续作为可选的精确对齐 Provider

缺点是运行时较重，不适合作为首版默认内置组件。

### 2. Misaki / Misaki-RS

[Misaki](https://github.com/hexgrad/misaki) 是面向英语的上下文 G2P 引擎，支持美式英语。

它相比 CMUdict 的优势是：

- 按完整句子处理
- 使用词性判断多音词
- 保留 token 与音素关联
- 支持美式和英式发音
- 可以处理词典外单词

例如能够根据词性区分名词和动词读音不同的单词。

项目已有 [Misaki-RS](https://github.com/MicheleYin/misaki-rs) Rust 移植版本，与我们的 Rust 核心架构非常契合。不过需要先审查准确率、许可证和维护质量。

适合作为首个 `PronunciationProvider` 原型。

### 3. Festival Postlexical Rules

[Festival](https://github.com/festvox/festival) 是一个较老但设计成熟的 TTS 系统。它的重要参考价值在于 **postlexical rules**：

```text
文字
→ 词典标准发音
→ 句子级后词汇规则
→ 连续语流发音
```

这些规则用于处理：

- 相邻单词边界
- 音素删除
- 音素替换
- `r` 等连接行为
- 发音上下文变化

这正是我们需要的 `SpeechRuleAnalyzer` 设计模式。

Festival 本身不适合直接成为现代客户端依赖，但其“标准发音和后词汇规则分离”的思想非常值得采用。

### 4. eSpeak NG / Phonemizer

[eSpeak NG](https://github.com/espeak-ng/espeak-ng) 和 [Phonemizer](https://github.com/bootphon/phonemizer) 可以将完整句子转换为 IPA，并支持超过 100 种语言和口音。

优势：

- 体积较小
- 能输出 IPA
- 支持完整句子
- 未来扩展其他语言方便

不足：

- 输出主要服务于 TTS，不等于真实语流分析
- 发音自然度和教学准确性需要验证
- eSpeak NG 本体为 GPL，需要仔细处理许可证和分发方式

它适合作为未来多语言兜底 Provider，不建议作为美式英语首选结果。

### 5. Buckeye Corpus

[Buckeye Corpus](https://buckeyecorpus.osu.edu/) 是非常有价值的美式英语研究资产。

它包含：

- 美国俄亥俄州母语者的自然对话
- 约 30 万词
- 正字文本
- 实际音素转写
- 词和音素时间对齐
- 大量自然弱化、省音和发音变化

它适合用于：

- 建立规则测试集
- 统计哪些弱读形式最常出现
- 验证规则提示是否合理
- 后续训练或评估真实语流检测

但其使用许可需要单独确认，不应直接打包进产品。

## 推荐的规则体系

首版不要追求自动“检测”，而应该实现一个可解释的候选规则引擎。

### 高可靠度规则

这些规则非常适合首版：

| 类型 | 示例 |
|---|---|
| 功能词弱读 | `to /tuː/ → /tə/` |
| 冠词弱读 | `the /ðiː/ → /ðə/` |
| 助动词弱读 | `can /kæn/ → /kən/` |
| 代词弱读 | `him /hɪm/ → /ɪm/` |
| 常见缩约 | `want to → wanna` |
| 美式闪音候选 | `get it` 中 `/t/ → /ɾ/` |
| `nt` 简化候选 | `twenty` |
| 相同辅音连接 | `big game` |
| 辅音到元音连接 | `pick it up` |
| `/t/`、`/d/` 省音候选 | `next day` |
| 同化候选 | `did you → /dɪdʒu/` |

### 必须带条件和置信度

规则输出不应只有结果，而应保存：

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

`status` 建议区分：

- `possible_by_rule`
- `likely_by_context`
- `supported_by_alignment`
- `detected_in_audio`
- `user_confirmed`

这样产品不会把语言教学规律错误包装成对真实音频的确定判断。

## 推荐架构

```text
PronunciationProvider
├── AmericanEnglishProvider
│   ├── MFA/CMU pronunciation lexicon
│   ├── Misaki-RS G2P
│   └── user pronunciation overrides
└── FutureLanguageProvider

SpeechRuleAnalyzer
├── weak_form_rules
├── linking_rules
├── contraction_rules
├── flapping_rules
├── assimilation_rules
└── deletion_rules

AlignmentProvider
├── estimated timing
├── ASR word timing
└── MFA/other forced alignment
```

内部音素建议使用统一、语言无关的数据结构，但每个 Provider 声明自己的音素体系：

```text
phoneme_set: arpabet | ipa | mfa | provider_specific
dialect: en-US
```

美式英语首版可以以 **ARPAbet 作为内部规范、IPA 作为显示格式**。ARPAbet 与 CMUdict、许多美国英语声学工具的兼容性更好。

## 我建议的实施路线

### 第一阶段：完全不依赖音频

- 接入美式英语发音词典
- 验证 Misaki-RS
- 输出词级和整句 IPA
- 实现约 15 至 25 条高价值语流规则
- 显示“可能发生的发音变化”
- 用户可点击查看规则解释

这部分实现风险低，但产品价值已经很明显。

### 第二阶段：对齐验证

- 接入 MFA 作为实验性 `AlignmentProvider`
- 对齐词和音素
- 在多个候选发音中选择最符合音频的形式
- 将规则结果升级为“声学对齐支持”

### 第三阶段：真实语流检测

- 使用 Buckeye 等自然语流数据评估
- 检测真实闪音、弱读、省音和同化
- 为结果提供置信度
- 将结果用于“认识但听不出”的诊断

因此，下一阶段最合理的技术组合是：

> **Misaki-RS 或 MFA 美式词典负责基础发音，独立规则引擎负责候选语流解释，MFA 后续负责使用真实音频验证候选。**

这条路线既优先满足美式英语，也能通过 Provider、dialect 和 phoneme-set 边界保留未来扩展性。

### Sources

- [MFA probabilistic lexicons](https://montreal-forced-aligner.readthedocs.io/en/stable/user_guide/implementations/lexicon_probabilities.html)
- [MFA pronunciation dictionary format](https://montreal-forced-aligner.readthedocs.io/en/v3.3.4/user_guide/dictionary.html)
- [Misaki G2P](https://github.com/hexgrad/misaki)
- [Misaki-RS](https://github.com/MicheleYin/misaki-rs)
- [Buckeye Corpus](https://buckeyecorpus.osu.edu/)
- [Phonemizer](https://github.com/bootphon/phonemizer)
- [Festival](https://github.com/festvox/festival)
