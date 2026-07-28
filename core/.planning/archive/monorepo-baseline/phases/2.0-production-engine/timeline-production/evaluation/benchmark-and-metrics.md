# Benchmark And Metrics

更新时间：2026-06-18 19:47:03 CST

本文件记录时间轴质量评估方案。Phase 4 的第一批可执行能力已经落到
`scripts/evaluate-word-timelines.py`，先覆盖弱评估和小型 gold fixture。

## Metric Families

- Word boundary error：start/end 的 MAE、P95、bias。
- Coverage：成功对齐的词占比、缺失词、越界词。
- Monotonicity：overlap、逆序、异常 gap。
- Tail lag：语速快时句尾高亮是否落后。
- Chunk quality：chunk boundary 与 gold/manual boundary 的偏移。

## Report V1

`evaluate-word-timelines.py compare` 比较两个独立 word timeline JSON。
`evaluate-word-timelines.py compare-lltimeline` 直接从同一个 `.lltimeline.json`
内选择 baseline/candidate/gold timeline 比较。

当前 JSON report 字段：

- `baseline` / `candidate`：timeline id、algorithm、version、status、word count。
- `weak_metrics`：matched word count、baseline/candidate coverage、start/end/duration
  offset stats、tail lag、monotonicity、provider mix、confidence、suspicious words。
- `gold_metrics`：当提供 gold timeline 时输出 coverage、start/end MAE、bias 和
  25/50/100/200ms 阈值内准确率。
- `source_document`：`compare-lltimeline` 记录输入 `.lltimeline.json`、media id/title
  和参与比较的 timeline id。
- `production_report`：可选嵌入 Phase 3 `production-report.json` 的摘要。

弱评估报告的核心解释：

- `lead_lag_bias_start_ms` / `lead_lag_bias_end_ms` 为 candidate 相对 baseline 的
  平均偏移；正数表示 candidate 更晚，负数表示更早。
- `p95_abs` 用于观察大多数词边界的最坏偏移区间。
- `tail_lag_ms` 只看每句最后一个匹配词，用来捕捉快语速下句尾高亮跟不上的现象。
- `suspicious_words` 列出超过阈值的词，方便人工抽检。

## Benchmark Sets

- TIMIT：第一优先级，用于基础 word/phone 边界误差。TIMIT 原始语料不进入 Git。
- Buckeye：第二优先级，用于自然语流、连读、弱读和真实停顿。需先确认授权和格式样本。
- LibriSpeech alignments：辅助压力测试和规模回归，不作为最高级人工 gold。
- News gold set：后续自建 CNN10/NBC Nightly News 小样本，代表目标生产场景。
- 当前 smoke fixture：`testdata/lltimeline/v1-evaluation-candidates.lltimeline.json`，
  包含 DTW baseline、WhisperX candidate 和 manual gold 三条 word timeline。
- TIMIT smoke fixture：`testdata/benchmark-datasets/timit-smoke/`，只用于测试本项目
  parser，不包含真实 TIMIT 数据。

详细数据集顺序见 `gold-dataset-strategy.md`。

## Evaluation Principle

弱评估用于快速比较候选；gold benchmark 用于确认真实准确率。人工修正后的
published timeline 可以反过来成为后续新闻样本的 gold reference。
