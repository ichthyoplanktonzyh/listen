# 真实语流分析与 Speech-to-IPA

确实存在“直接听音频并输出音素/IPA”的模型与训练路线。这个方向通常被称为：

- **Phone Recognition / Phoneme Recognition**
- **Automatic Phonetic Transcription**
- **Speech-to-IPA**
- **Allophone Recognition**

它不同于普通 ASR：

```text
普通 ASR：音频 → 文字
真实语流模型：音频 → 实际听到的音素序列
```

例如：

```text
字幕文字：Did you want to go?
标准发音：/dɪd ju wɑnt tu ɡoʊ/
实际语流：/dɪdʒə wɑnə ɡoʊ/
```

理想模型应直接输出后者。

## 现有方案

### Allosaurus

[Allosaurus](https://github.com/xinjli/allosaurus) 是较早的通用 Phone Recognizer。

- 输入音频，直接输出 IPA phone
- 支持大量语言
- 能识别音频中实际出现的声音，而不是读取文字词典
- 可以针对特定语言继续微调

问题：

- GPL-3.0，不适合直接内置到当前尚未开源授权的产品
- 模型相对较老
- 输出容易产生插入、删除和不稳定音素
- 不负责将音素可靠关联回字幕单词

适合做早期基线实验，不适合作为最终默认 Provider。

### Wav2Vec2Phoneme

[Wav2Vec2Phoneme](https://huggingface.co/docs/transformers/en/model_doc/wav2vec2_phoneme) 使用 CTC 将音频直接解码为音素序列。

优点：

- 训练流程成熟
- 可以微调
- CTC 帧天然适合恢复音素时间位置
- 可在 Apple Silicon 本地运行
- 容易限制为美式英语音素集合

它非常适合我们自行训练第一版美式英语真实语流模型。

### MultIPA / Wav2IPA

[MultIPA](https://github.com/ctaguchi/multipa) 研究的是直接将语音转写为 IPA。

其衍生项目 [Wav2IPA](https://github.com/ginic/multipa) 更值得关注，因为其目标就是：

> 为美式英语方言和自然语流生成高质量自动音标转写。

它已经提供基于 Buckeye Corpus 微调的 Wav2Vec2 模型。这与我们的使用目标非常接近，可以作为首个真实原型。

### ZIPA

[ZIPA](https://aclanthology.org/2025.acl-long.961/) 是 2025 年发布的较新 Phone Recognition 模型族。

- 直接输出 IPA
- 有 64M 和 300M 模型
- 64M 版本适合本地部署研究
- 相比旧式 Allosaurus，音素识别能力和效率更好
- 支持社会语音和跨语言变化评估

但它主要使用大量 G2P 生成的数据训练。它可能擅长输出规范化音素，却不一定可靠保留真实弱读和省音。

### PhoneticXeus

[PhoneticXeus](https://github.com/changelinglab/PhoneticXeus) 是目前非常新的多语言 IPA Phone Recognition 项目，计划在 Interspeech 2026 发布。

它可以作为未来实验对象，但目前太新，不适合直接成为正式依赖。

## 最大的问题：训练标签

训练模型本身并不是最困难的部分。真正困难的是：

> 训练数据中的音标究竟是根据文字自动生成的标准发音，还是人工听取真实音频标注的实际发音？

大量 Speech-to-IPA 模型使用如下数据：

```text
音频 + 正字文本
→ 使用 G2P 将文字转换为标准 IPA
→ 用标准 IPA 训练模型
```

这类模型即使输入真实语流，也容易把：

```text
wanna
```

重新规范化为：

```text
want to
```

它无法可靠学习真正发生的弱读、闪音和省音。

要实现我们的目标，需要使用包含 **人工修正实际音素标注** 的自然语流数据。

## 最适合的数据集

### Buckeye Corpus

Buckeye 是目前最贴合我们目标的训练资产。

- 自然美式英语对话
- 约 38 小时、30 万词
- 具有文本、实际音素和时间对齐
- 自动对齐后经过人工听辨修正
- 包含大量弱读、省音、同化和闪音现象

例如可以学习：

```text
the → /ðə/、/ə/
and → /ən/、/n/
want to → /wɑnə/
t/d → 删除或闪音
```

不过 Buckeye 数据许可需要在商业或分发前仔细确认。它更适合作为研究和验证集，未必能直接随产品分发模型。

### 不太适合的数据

- **TIMIT**：有精细音素标注，但主要是朗读语音，真实语流变化有限
- **G2P 生成数据**：规模大，但只表达规范发音
- **普通 ASR 数据集**：通常只有文字，没有实际音素标签

## 推荐模型路线

我不建议训练一个模型直接输出“发生了连读、弱读、省音”这些语言学标签。

更可靠的方式是分成两步：

```text
音频
→ 实际音素序列与时间
→ 与标准/候选发音比较
→ 推断发生了哪些语流变化
```

例如：

```text
标准候选：want to → W AA N T | T UW
模型输出：             W AA N AX
差异分析：
- /t/ 删除
- to 弱化为 /ə/
- 两词发生缩约
```

这样模型负责“听到了什么”，确定性的分析器负责“这代表什么现象”。结果更容易解释和测试。

## 推荐架构

新增独立于 ASR 的 Provider：

```text
PhoneticTranscriptionProvider
- transcribePhones(audioRange)
- capabilities
- phoneSet
- dialect
- modelRevision
```

输出：

```text
PhoneticTranscription
- phones[]
- startMs
- endMs
- confidence
- phoneSet
- provider
```

然后由另一个服务比较：

```text
PronunciationAnalysisService
- canonical pronunciation
- rule-generated variants
- detected phone sequence
- alignment result
- connected-speech findings
```

最终每条发现都包含：

```text
类型：reduction / deletion / assimilation / flapping
规则候选：want to → wanna
音频证据：W AA N AX
置信度：0.82
关联词汇：want + to
时间范围：12.30s - 12.74s
```

## 最现实的实验方案

建议先做一个研究性 Spike，而不是立即进入正式 Milestone：

1. 选取 50 至 100 条美式新闻和自然对话句子。
2. 分别运行：
   - Allosaurus
   - Wav2IPA Buckeye 模型
   - ZIPA 64M
3. 比较它们对弱读、闪音、`t/d` 删除和缩约的保留能力。
4. 将输出音素与字幕词汇进行动态规划对齐。
5. 验证是否可以稳定回答：
   - 哪个词正在播放
   - 实际检测到哪些音素
   - 与标准发音差异在哪里
6. 根据结果决定微调 Wav2Vec2、ZIPA，还是自行训练美式英语模型。

## 我的判断

训练一个面向我们产品的模型是可行的，而且可能成为 LLPlayerNext 最有差异化价值的功能。

但目标应分阶段：

- **近期可实现**：真实音频 → 宽式音素序列、词级/音素级时间轴
- **中期可实现**：检测常见弱读、省音、闪音和缩约
- **长期研究项**：稳定输出狭式 IPA、复杂同化和音素细节

下一步最值得做的是：

> 使用 Wav2IPA、ZIPA 和 Allosaurus 对同一批真实美式英语材料进行基准测试，确定现有模型是否足够；若不足，再基于 Buckeye 风格数据微调专用模型。

### Sources

- [Allosaurus](https://github.com/xinjli/allosaurus)
- [Wav2Vec2Phoneme](https://huggingface.co/docs/transformers/en/model_doc/wav2vec2_phoneme)
- [Wav2IPA](https://github.com/ginic/multipa)
- [ZIPA paper](https://aclanthology.org/2025.acl-long.961/)
- [PhoneticXeus](https://github.com/changelinglab/PhoneticXeus)
- [Buckeye Corpus](https://buckeyecorpus.osu.edu/)
- [MFA](https://montreal-forced-aligner.readthedocs.io/en/stable/user_guide/index.html)
