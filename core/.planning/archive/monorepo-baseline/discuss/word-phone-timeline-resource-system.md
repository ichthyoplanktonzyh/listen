# Word And Phone Timeline Resource System

## Background

LLPlayerNext 的词级高亮和 chunk 划分都依赖同一个基础事实：
每一个可识别词在整段音频中的物理时间区间。当前 Whisper DTW、
local pause refinement、torchaudio MMS_FA sidecar 都是在尝试改进这个
事实的估计方式。

近期真实视频测试暴露了两个相反的现象：

- Whisper DTW 有时会让词级高亮跑在声音前面。
- MMS_FA 研究模式在快语速片段里有时会让词级高亮跟不上声音。

这说明继续只靠肉眼观察会让问题归因变得不可靠。我们需要把词级和
音素级时间轴变成可评估、可比较、可复用、可人工修正的资源。

## Core Goal

核心目标不是“使用某个 forced alignment 工具”，而是建立稳定的
音频时间轴资源：

```text
word_id / sentence_id / token_index
text
start_ms
end_ms
confidence
source / provider / version / config
```

其中 `start_ms` 和 `end_ms` 应尽量表示：

```text
这个可识别词的可听见声学实现，在整段音频中从哪里开始，到哪里结束。
```

这区别于：

- ASR 模型何时输出这个词；
- Whisper 注意力大概看向哪里；
- 句级字幕 cue 大概覆盖哪里；
- 人为估算的词内均分位置。

未来音素级高亮的目标类似，只是单位从 word 变为 phone/phoneme。

## Product Uses

### Word Highlighting

播放器位置落入某个词的 `[start_ms, end_ms]` 时，高亮该词。时间轴
偏早会造成字幕抢跑，偏晚会造成“话已经说完但高亮还没追上”。

### Chunk Partitioning

chunk 划分依赖相邻词之间的真实间隔：

```text
gap_ms = next_word.start_ms - current_word.end_ms
```

时间戳误差会直接导致真实停顿被吞掉，或者虚假停顿被放大。

### Human Correction

算法生成的时间轴不应被视为绝对真理。自然语音存在连读、弱读、吞音、
重叠说话、爆破音释放延迟等模糊边界。人类应能修正时间轴，并将修正后
的结果保存为更高优先级的可复用资源。

## Current System Facts

- ASR 生成的字幕 track 已经持久化为 `SubtitleTrack`。
- 词级时间戳已经持久化在 `word_timings` 表中，按 sentence 保存 JSON。
- HTTP API 已有 `GET/POST /v1/subtitles/{track_id}/word-timings`。
- SRT 导出目前只导出句级 cue，不包含词级时间戳。
- chunk partition 目前按需从 `SubtitleTrack + WordTiming` 计算，不是持久资源。
- ASR job 目前没有 delete/archive；同输入 fingerprint 的 completed job 会被复用，
  阻碍算法改良后的重新生成和 A/B 对比。

## Desired Resource Model

### Transcript Track

句级字幕文本和句级 cue。它回答：

```text
这段媒体说了什么？句子大概在哪？
```

ASR 生成的 SRT、导入的 SRT/VTT、人工编辑后的字幕都属于这一层。

### Word Timeline

词级时间轴资源。它回答：

```text
每个可识别词在音频里的 start/end 是多少？
```

同一个 transcript track 可以拥有多个 word timeline：

```text
SubtitleTrack
  ├─ whisper-dtw-v2 timeline
  ├─ dtw-pause-v1 timeline
  ├─ mms-fa-v1 timeline
  ├─ mfa-research-v1 timeline
  └─ user-adjusted timeline
```

推荐 metadata：

```text
timeline_id
track_id
media_id
algorithm_id
algorithm_version
config_hash
parent_timeline_id
created_at_ms
created_by: algorithm | user
status: candidate | active | archived
metrics_json
words[]
```

### Phone Timeline

音素级时间轴资源。它回答：

```text
每个 phone/phoneme 在音频里的 start/end 是多少？
```

phone timeline 可以从 word timeline 派生，也可以由 MFA 或其他 phone-level
aligner 直接生成。它应保留词/音素映射关系，支持未来音素级高亮。

### Chunk Timeline

chunk 划分结果也应成为资源。它回答：

```text
基于某个 word/phone timeline，这句话应该如何分块学习？
```

推荐 metadata：

```text
chunk_timeline_id
track_id
word_timeline_id
algorithm_id
algorithm_version
config_hash
parent_chunk_timeline_id
created_by: algorithm | user
status: candidate | active | archived
chunks[]
diagnostics_json
```

## Evaluation Philosophy

MMS_FA、MFA、Whisper DTW、VAD、pause refinement、未来 Rust/ONNX aligner
都只是生成候选时间轴的手段。系统必须能客观比较它们。

### Gold Evaluation

最好建立小型人工标注集：

```text
media clip
transcript
manual word boundaries
optional manual phone boundaries
```

指标：

- word start MAE / median absolute error
- word end MAE / median absolute error
- onset accuracy at 25/50/100/200 ms
- offset accuracy at 25/50/100/200 ms
- lead/lag bias
- coverage
- monotonicity violations
- duration outliers
- sentence-end lag
- chunk boundary precision/recall against human chunk references

### Weak Evaluation

没有人工 gold 时，也应输出弱指标：

- FA-DTW 偏移分布；
- 首词/尾词相对 sentence cue 的偏移；
- 尾词结束到句尾的 lag；
- 词时长异常；
- overlap/gap 异常；
- provider mix；
- chunk 数量变化；
- chunk boundary 位移；
- 可疑词列表。

## Research Baselines

MFA 应作为英语场景的重要质量标尺。已有研究显示，在 TIMIT/Buckeye 等
人工标注数据集上，MFA 在 word alignment 上优于 MMS 和 WhisperX。

Relevant references:

- Montreal Forced Aligner user guide:
  https://montreal-forced-aligner.readthedocs.io/en/v3.1.0/user_guide/
- MFA Interspeech 2017 paper:
  https://www.isca-archive.org/interspeech_2017/mcauliffe17_interspeech.pdf
- Interspeech 2024 comparison of MFA, MMS, and WhisperX:
  https://www.isca-archive.org/interspeech_2024/rousso24_interspeech.html
- Torchaudio CTC forced alignment tutorial:
  https://docs.pytorch.org/audio/main/tutorials/ctc_forced_alignment_api_tutorial.html
- WhisperX paper:
  https://www.isca-archive.org/interspeech_2023/bain23_interspeech.pdf

## Recommended Direction

Recommended role split:

```text
MFA = research-quality reference and strong candidate
MMS_FA / CTC = current lightweight experiment path
Human correction = highest-trust reusable resource
Rust/ONNX/native aligner = productization target after validation
```

Do not treat any aligner as automatically correct. Promote an algorithm to the
default product path only after it wins on LLPlayerNext's own evaluation clips
and does not regress user-visible highlighting or chunk quality.
