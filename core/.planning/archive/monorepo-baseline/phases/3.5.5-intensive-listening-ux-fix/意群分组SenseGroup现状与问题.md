# 意群分组（SenseGroup）现状与问题

> Phase 3.5.5，来源于精听模块 UX 走查讨论
> 日期：2026-07-09

## 问题描述

SenseGroup（意群）功能在 UI 中不可见、无法开启、且算法基础薄弱，用户无法感知其存在和价值。

---

## 一、什么是 SenseGroup？与 ChunkTimeline 的区分

### 核心架构决策（ADR 0016）

- **文档**：[docs/decisions/0016-sense-group-semantic-prosodic-separation.md](file:///Users/shadow/LLPlayerNext/docs/decisions/0016-sense-group-semantic-prosodic-separation.md)
- **实现计划**：[3.4.2-PLAN.md](file:///Users/shadow/LLPlayerNext/.planning/phases/3.4.2-semantic-prosodic-group-separation/3.4.2-PLAN.md)
- **共享上下文**：[3.4.X-LEARNING-DOMAIN-V2-SHARED-CONTEXT.md](file:///Users/shadow/LLPlayerNext/.planning/phases/3.0-english-listening-learning-loop/3.4.X-LEARNING-DOMAIN-V2-SHARED-CONTEXT.md) §1

### 两层是独立的，不互相覆盖

| 维度 | ChunkTimeline（韵律语块） | SenseGroup（意群） |
|------|--------------------------|-------------------|
| 回答的问题 | "说话者怎么断句的？" | "这个句子按意义应该怎么分组？" |
| 依据 | 声学/韵律证据（停顿、延长、节奏） | 文本语义（标点、词数规则，未来可接入 NLP） |
| 数据 | 有时间范围 `start_ms/end_ms` | 纯 token 范围 `(sentence_id, start_token_index, end_token_index)`，无时间——通过 WordTimeline 投影获得播放范围 |
| 来源 | 说话者的发声方式 | 语言本身的语义结构 |
| 生命周期 | 独立存储、互不依赖 | 独立存储、互不依赖 |

### 为什么需要两层共存

两者经常一致但会偏离的场景：

1. **说话者把语义单位切碎**——为了强调或换气，把一个意群跨两个韵律短语说
2. **语速快时合并**——两个小语义单位被合并到一个韵律短语里
3. **犹豫/修正/插入语**——产生声学边界，但跟语义边界无关

---

## 二、现状

### 后端全栈已落地

| 层 | 文件 | 状态 |
|---|------|------|
| Domain 模型 | `crates/domain/src/sense_group.rs` | 完整定义 SenseGroup / SenseGroupAnalysis / SenseGroupSource |
| 算法 | `crates/speech-analysis/src/sense_group_partition.rs` | 规则回退 provider |
| 持久化 | schema v25 `0025_sense_group_analyses.sql` | 迁移 + lifecycle/round-trip 测试 |
| Application | `crates/application/src/sense_groups.rs` | 7 use cases |
| API | `crates/api-http/src/routes/timelines.rs` | 7 API routes |

### Flutter 端

| 组件 | 状态 |
|------|------|
| Dart DTO（SenseGroup / SenseGroupAnalysis） | 已定义：[timeline.dart](file:///Users/shadow/LLPlayerNext/apps/desktop/lib/models/timeline.dart#L537-L688) |
| ApiService 端点 | 已接入 |
| SubtitleController.senseGroupsBySentence | 已缓存，数据已加载到 store |
| 设置项 `showSenseGrouping` | 存在，默认 `false`：[settings.dart#L45](file:///Users/shadow/LLPlayerNext/apps/desktop/lib/settings.dart#L45) |
| 设置 UI 开关 | **不存在**——用户无法在界面上开启 |
| Widget 渲染 | **不存在**——任何 widget 均未消费 `showSenseGrouping` |

### 算法现状

- **Provider**: `rule-based-sense-group` v1
- **算法标识**: `punctuation_length_rule_v1`
- **策略**:
  - 强标点（`. ! ? ; :`）→ 强制切分
  - 弱标点（`, 、`）→ 达到最少词数（2 个词）时切分
  - 无标点 → 软上限 5 个词时尝试切，硬上限 8 个词强制切
  - 短语保护（如 "take care of"）不被切散
- **置信度**: 全部固定为 `0.5`（纯 heuristic_proxy）
- **无 NLP 参与**：`SenseGroupSource::DependencyParse` 和 `PhraseStructure` 虽在 domain 模型中定义，但当前 provider 从未产出

---

## 三、问题总结

1. **UI 不可见**：数据已通到 Flutter store，但没有任何 widget 渲染意群分隔，用户完全看不到
2. **无法开启**：`showSenseGrouping` 设置项存在于数据模型中（默认关），但没有对应的设置 UI 开关
3. **算法基础薄弱**：纯规则回退，无 NLP 依存句法解析，全部置信度固定 0.5，对复杂句子的分组质量有限

## 涉及文件

- `docs/decisions/0016-sense-group-semantic-prosodic-separation.md` — 架构决策
- `.planning/phases/3.4.2-semantic-prosodic-group-separation/3.4.2-PLAN.md` — 实现计划
- `crates/domain/src/sense_group.rs` — Domain 模型
- `crates/speech-analysis/src/sense_group_partition.rs` — 规则回退算法
- `crates/application/src/sense_groups.rs` — Application 层
- `crates/api-http/src/routes/timelines.rs` — API 路由（7 条）
- `crates/persistence-sqlite/migrations/0025_sense_group_analyses.sql` — schema v25
- `apps/desktop/lib/models/timeline.dart` — Dart DTO
- `apps/desktop/lib/settings.dart` — showSenseGrouping 设置项
- `apps/desktop/lib/controllers/subtitle_controller.dart` — senseGroupsBySentence 数据缓存
