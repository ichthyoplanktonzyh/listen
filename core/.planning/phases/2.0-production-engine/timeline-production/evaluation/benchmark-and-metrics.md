# Benchmark And Metrics

更新时间：2026-06-18 15:11:06 CST

本文件记录时间轴质量评估方案。当前先定义方向，具体脚本和报告格式随 Phase 4
推进补充。

## Metric Families

- Word boundary error：start/end 的 MAE、P95、bias。
- Coverage：成功对齐的词占比、缺失词、越界词。
- Monotonicity：overlap、逆序、异常 gap。
- Tail lag：语速快时句尾高亮是否落后。
- Chunk quality：chunk boundary 与 gold/manual boundary 的偏移。

## Benchmark Sets

- TIMIT：小规模专家对齐样本，用于基础边界误差。
- Buckeye：自然语流样本，用于真实语速、连读、弱读。
- News gold set：自建 CNN10/NBC Nightly News 小样本，代表目标生产场景。

## Evaluation Principle

弱评估用于快速比较候选；gold benchmark 用于确认真实准确率。人工修正后的
published timeline 可以反过来成为后续新闻样本的 gold reference。

