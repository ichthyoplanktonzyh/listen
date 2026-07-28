# SenseGroup & Chunk UX 统一方案

日期：2026-07-14

---

## 一、背景

当前 LLPlayerNext 中有两套独立的分组机制（ADR 0016）：

| | Chunk（韵律语块） | SenseGroup（语义分组） |
|---|---|---|
| **含义** | 说话者"实际怎么说的"——按声学边界分 | 句子"在说什么"——按语义理解单位分 |
| **数据来源** | `ChunkTimeline` | `SenseGroupAnalysis` |
| **算法依赖** | `chunk_partition.rs` | `sense_group_partition.rs` |
| **前置条件** | WordTimeline（几乎总是有） | spaCy 语法能力（可选安装） |

从用户视角看，它们回答同一个问题：**"这句话应该按什么单位来理解？"**——只是答案来源不同。用户不应该为数据层的分离付出 UX 代价。

---

## 二、发现的问题

### 问题 1：SenseGroup 设置后前端无显示（误以为坏）

用户打开"语义分组"后，前端无任何视觉变化。原因：

**`run_track_syntax_analysis` 从未将 SenseGroup 写入 SQLite。**

完整的断链追踪：

```
run_track_syntax_analysis()                    ← syntax.rs
  └─ synthetics_consumers.consume()            ← 计算 sense_groups ✅
      ├─ write_track_cache()                   ← 写入 JSON 缓存 ✅
      └─ ❌ 缺少: generate_syntax_aware_sense_group_analysis()
                                                  ← 未写入 SQLite ❌

SpeechEnhancementWorkflowController             ← Flutter
  └─ _loadSenseGroups()
      └─ GET /v1/.../sense-group-analyses      ← 读 SQLite → 空
```

`SyntacticConsumerBatch.sentences[].sense_groups` 在语法分析时已算出，但只存入了 JSON 缓存文件，没有作为 `SenseGroupAnalysis` 写入 `sense_group_analyses` 表。Flutter 侧 `_loadSenseGroups()` 读的是 SQLite，因此永远返回空。

3.9.3 QA 只覆盖了 batch 响应中 sense_groups 非空，未覆盖 SQLite 持久化。

### 问题 2：SenseGroup 无时间戳

`SenseGroupSpan` 的 domain 模型只有 `start_token_index` / `end_token_index`，**没有 `start_ms` / `end_ms`**。

```rust
// sense_group_partition.rs:34-42
pub struct SenseGroupSpan {
    pub start_token_index: u32,
    pub end_token_index: u32,
    pub sources: Vec<SenseGroupSource>,
    pub confidence: f32,
    pub label: Option<String>,
    pub head_token_index: Option<u32>,
    // ❌ 无时间戳
}
```

对比 `DisplayChunk`：

```rust
// chunk_partition.rs:163-171
pub struct DisplayChunk {
    pub index: u32,
    pub token_start: u32,
    pub token_end: u32,
    pub text: String,
    pub start_ms: u64,    // ✅
    pub end_ms: u64,      // ✅
    pub boundary_after: Option<DisplayChunkBoundary>,
}
```

系统中有 `WordTimeline`（词级时间戳库），从 TokenIndex → WordTiming 是可做的，只是没人做。

### 问题 3：SenseGroup 在 UI 中地位不对等

| 维度 | Chunk | SenseGroup |
|---|---|---|
| 时间戳 | ✅ 精确 start_ms/end_ms | ❌ 无 |
| 播放跟随 | ✅ 高亮当前 chunk | ❌ 无法跟随 |
| 点击跳转 | ✅ 可点击跳到对应时间 | ❌ 不可交互 |
| UI 风格 | 实线胶囊 + 多级高亮 | 虚线胶囊 + "临时标记" tooltip |
| UI 无数据时 | 按钮 disabled（有提示） | ❌ 静默回退，无反馈 |
| 配置项 | 5 个子设置 | 只有 1 个下拉选项 |
| 精听练习 | chunk dictation 题型 | 无消费入口 |

### 问题 4：Chunk 算法实际是声学多模态

发现用户对 Chunk 的理解有偏差——它不是纯文本规则，而是使用了多层声学证据：

| 证据类型 | 说明 |
|---|---|
| `AcousticGap` | ASR/forced alignment 报告的单词间实际音频间隙 |
| `PreBoundaryLengthening` | 检测边界前词发音时长是否显著长于基线 |
| `FilledPauseHesitation` | 检测 um/uh 等填充停顿 |
| `LearnedProsodicModel` | 嵌入式 ML 模型输出边界概率 |
| `Punctuation` | 文本级回退 |
| `LengthLimit` | 词数硬限制 |

---

## 三、建议方案

### 3.1 原则

- **ADR 0016 保持不变**：数据层各自独立（ChunkTimeline vs SenseGroupAnalysis）
- **展示层统一**：两种分组获得对等的 UI 能力和交互
- **用户不感知数据层的差异**

### 3.2 具体措施

#### 3.2.1 修复 SenseGroup 持久化（后端 bug 修）

在 `run_track_syntax_analysis` 末尾、`write_track_cache` 之后，调用 `generate_syntax_aware_sense_group_analysis()` 将 SenseGroup 写入 SQLite。

文件：`crates/api-http/src/routes/syntax.rs` @ L259-261

```rust
// 写入 JSON 缓存（已有）
if analyzed_sentence_count > 0 {
    write_track_cache(&cache_path, &cached).await;
}
// ↓ 新增：将 sense groups 持久化到 SQLite
if status == TrackSyntaxStatus::Ready || status == TrackSyntaxStatus::Partial {
    // 从 batch 中提取 SyntacticAnalysis，调用 generate_syntax_aware_sense_group_analysis
}
```

#### 3.2.2 SenseGroup 回退生成（无语法能力时也可用）

`generate_sense_group_analysis()` 已有纯文本规则回退路径（`partition_sentence` 无 syntax 参数）。可考虑在 `loadSpeechEnhancements` 或字幕加载时自动触发一次 fallback 生成，确保用户即使没装语法能力也能看到基础的语义分组。

#### 3.2.3 补 SenseGroup 时间戳

在 `sense_group_from_span()`（`crates/application/src/sense_groups.rs`）中，通过 `WordTimeline` 的 `WordTiming` 映射 TokenIndex → 时间戳：

```rust
// 新增字段到 SenseGroup domain 模型
start_ms: Option<u64>,
end_ms: Option<u64>,
```

SenseGroup 的 Flutter 模型（`word_chunk.dart`）同步添加时间字段。

有了时间戳后：
- 语义分组胶囊可**随播放高亮当前组**
- 可**点击跳转**到对应时间
- `compare` 模式中两侧都有时间信息

#### 3.2.4 无数据时提供明确反馈

设置页面中，当前不可用但有价值的能力应给出引导。举例：

- 下拉菜单中 `semantic` 选项旁标注状态：`语义分组（需先安装语法能力）` 或 `语义分组 · 可用`
- 选择不可用的 `semantic` 时，显示引导文字："语义分组需要安装语法分析能力，是否前往设置安装？"
- 可附带一键跳转到 Syntax Capability 安装页的链接

#### 3.2.5 UI 对等

**视觉对等**：
- `semantic` 纯模式下，虚线边框 → 实线边框（去掉 "provisional" 视觉降级）
- `compare` 模式下，语义分组保持虚线/差异标记（该模式的价值就是展示差异）

**交互对等**：
- 语义分组获得当前组高亮跟随（当 SenseGroup 有了时间戳后）
- 语义分组可获得点击跳转

**配置对等**：
- 如果语义分组有了时间戳，可以复用现有的 chunk 高亮设置
- 或新增 SenseGroup 专属高亮设置

#### 3.2.6 模式重设计（广义）

4 个模式的用户视角统一：

| 模式 | 理解角度 | 用户看到的 |
|---|---|---|
| `off` | — | 不分组，逐词显示 |
| `prosodic` | 韵律角度 | "说话者是怎么说的"——实线胶囊，按停顿/韵律分组 |
| `semantic` | 语义角度 | "这句话在说什么"——实线胶囊，按理解单位分组 |
| `compare` | 差异角度 | "哪里容易听错"——韵律为底+语义边界差异标记 |

---

## 四、实施优先级

| 优先级 | 事项 | 影响 |
|---|---|---|
| P0 | 修复语法分析 → SenseGroup SQLite 持久化 | 语义分组完全不可用 |
| P0 | 无数据 UI 反馈（不静默回退） | 用户困惑 |
| P1 | SenseGroup 补时间戳 | 获得播放跟随+点击跳转 |
| P2 | SenseGroup 文本规则回退生成 | 无语法能力时也可用 |
| P2 | UI 对等（视觉+交互+配置） | 体验一致性 |

---

## 五、代码定位

### 后端

| 文件 | 说明 |
|---|---|
| `crates/api-http/src/routes/syntax.rs` | `run_track_syntax_analysis` — 语法分析入口，需补 SQLite 持久化 |
| `crates/application/src/sense_groups.rs` | `generate_syntax_aware_sense_group_analysis()` — 已存在但未被语法分析路由调用 |
| `crates/application/src/sense_groups.rs` | `sense_group_from_span()` — 生成 SenseGroup，需补时间戳 |
| `crates/speech-analysis/src/sense_group_partition.rs` | `SenseGroupSpan` — 纯文本，无时间维度 |
| `crates/domain/src/sense_group.rs` | `SenseGroup` domain 模型，无时间字段 |

### Flutter

| 文件 | 说明 |
|---|---|
| `apps/desktop/lib/models/timeline/word_chunk.dart` | `SenseGroup` Flutter 模型，无时间字段 |
| `apps/desktop/lib/widgets/subtitle/token_line.dart` | 渲染两种分组的 TokenLine |
| `apps/desktop/lib/widgets/settings/settings_dialog.dart` | grouping mode 下拉设置 |
| `apps/desktop/lib/controllers/speech_enhancement_workflow_controller.dart` | `_loadSenseGroups()` — 读 SQLite 但永远空 |
| `apps/desktop/lib/localization.dart` | 分组相关文案 |
