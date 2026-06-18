# Gold Dataset Strategy

更新时间：2026-06-18 19:47:03 CST

Phase 4 的评估路线先使用已有高质量 benchmark，不直接进入 CNN10/NBC gold set。
原因很简单：CNN10/NBC 当前没有可信的词级标准答案；如果先用它们评估，只会把
肉眼观察换成另一种主观判断。

## Dataset Order

### 1. TIMIT：第一优先级

用途：

- 验证 word boundary MAE / P95 / onset accuracy / offset accuracy。
- 验证 phone timeline 导入和 phone-level 指标。
- 作为 pipeline 回归测试的最小硬 gold。

理由：

- 自带 word、phone、orthographic transcription 边界。
- 16kHz 单声道音频，和我们生产管线的标准音频格式一致。
- 标注经过人工校验，适合做第一批客观准确率 benchmark。

限制：

- 它是朗读语音，不代表 CNN10/NBC 的快节奏新闻播报和真实剪辑。
- 受 LDC 授权限制，原始语料不得进入 Git、测试包或分发产物。

落地方式：

- 使用本地已授权 TIMIT 目录。
- 通过 `scripts/benchmark-datasets.py timit-to-lltimeline` 转成
  `.lltimeline.json`。
- 原始 `.WAV/.WRD/.PHN/.TXT` 只留在本地；仓库只保留 smoke fixture 和转换器。

### 2. Buckeye：第二优先级

用途：

- 验证自然语流、弱读、连读、停顿、填充词下的 word/phone 边界表现。
- 更贴近“快语速跟不上”和真实语流 chunk 切分问题。

理由：

- 它是自然会话美式英语，且包含手工校正的 phone/word 级语料形态。
- 近年的 forced alignment 研究常用 TIMIT + Buckeye 组合评估。

限制：

- 授权需要单独注册/确认。
- 原始格式比 TIMIT 更复杂，需要单独 parser 和清洗规则。
- 可下载版本可能存在格式和转写问题，不能假设它开箱即完全干净。

### 3. LibriSpeech Alignments：辅助压力测试

用途：

- 大规模回归、吞吐、资源格式压力测试。
- 观察长音频和 audiobook 风格材料上的 drift。

理由：

- 数据规模大，生态成熟，容易获得 MFA 生成的 word/phone alignment。

限制：

- 它通常是自动 MFA alignment，不是最高级人工 gold。
- 适合作为 weak benchmark 或规模测试，不应替代 TIMIT/Buckeye 的准确率判断。

### 4. CNN10/NBC 自建 gold set：后续领域校准

用途：

- 只在 TIMIT/Buckeye 已证明 pipeline 指标可解释后使用。
- 用来校准目标内容类型：新闻播报、剪辑停顿、背景音乐、多人切换。

落地方式：

- 先选 3-5 个 30-60 秒片段。
- 用当前最佳 pipeline 生成候选。
- 人工校正 word/chunk 边界后，保存为 `user-adjusted` / `published` timeline。
- 这批 published timeline 反过来成为新闻域 gold。

## Immediate Phase 4 Tasks

1. 完成 TIMIT `.WRD/.PHN/.TXT` → `LLTimeline JSON v1` 转换器。
2. 用 TIMIT 小样本跑 WhisperX / MMS_FA / MFA 候选，输出统一 evaluation report。
3. 增加 Buckeye parser 设计文档，确认授权和格式样本后再实现。
4. 暂缓 CNN10/NBC gold set，只保留后续领域校准位置。

## Licensing Boundary

- Restricted corpora stay outside Git.
- Generated reports may enter Git only when they do not contain copyrighted audio,
  restricted transcripts beyond tiny test fixtures, or redistributable corpus data.
- Local benchmark outputs should live under
  `~/Library/Caches/LLPlayerNext/research/benchmarks/` unless explicitly exported.
