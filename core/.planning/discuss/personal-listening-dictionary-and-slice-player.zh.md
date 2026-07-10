# 个人听力词典与切片播放器 —— 产品讨论

> 日期：2026-07-10
> 状态：REVIEWED — 评审结论见 §9；落地为 Phase 3.5.7 + Phase 3.6 v2 修订
> 参与：owner + agent 讨论；评审：owner + supervisor agent（2026-07-10）

---

## 1. 当前系统状态

### Phase 位置

主线 Phase 3.x 英语听力学习闭环：
- **Phase 3.5.5** ✅ 已收口（9 组 UX 修复，已冻结）
- **Phase 3.5.6** 🟡 ACTIVE — 精听浮动练习小窗基本收口
- **Phase 3.6** 📋 PLANNED — 听力词典 MVP
- **Phase 3.7+** 后续推进

### 当前领域模型（已有的）

- `LexicalEntry` — 词条（Word/Phrase），带 `occurrences` 列表和 `LexicalCapabilityProfile`
- `LexicalOccurrence` — 词条在字幕中的出现记录（`start_ms`/`end_ms`/`media_fingerprint` 快照）
- `LexicalCapabilityProfile` — 4 通道画像（reading/listening/speaking/writing），含 `sense_id` 预留缝（当前为 `None`）
- `LexicalSenseId` — 已定义为 `string_id!` 类型，但无 `LexicalSense` 结构体
- `LearningObservation` — 通道化证据，含 `sense_id` 预留缝
- `LexicalUnit` — 跨语言身份（粒度 × 归一化）

详见：
- [domain/learning.rs](../../crates/domain/src/learning.rs)
- [domain/capability.rs](../../crates/domain/src/capability.rs)
- [domain/lexical_unit.rs](../../crates/domain/src/lexical_unit.rs)

### 当前播放机制（有问题）

来源原句的播放走 `playback_actions_coordinator.playOccurrence()`：

1. 检查 `media_fingerprint_snapshot` — 同一媒体直接 seek 到时间点
2. 不同媒体 → 找到/加载整个视频文件 → seek → 设 sourceLoop
3. **结果**：劫持主播放器，用户的学习上下文丢失

详见 [playback_actions_coordinator.dart](../../apps/desktop/lib/controllers/playback_actions_coordinator.dart#L190-L249)

涉及入口（5 个）：
- WordLearningPanel（侧面板内）
- WordLearningPanel（词汇本弹窗）
- 词汇本全屏页
- 词汇详情视图
- 学习资产页

---

## 2. 讨论触发点

1. **来源原句**（3.5.5）和 **听力词典**（3.6）共享一个核心功能：播放一个词在其他语境中的出现音频/视频
2. 当前实现是"跳全片 + 循环"，用户感知上是"我被拽到了另一个视频的第 3 分 15 秒"
3. 这违反了"用户的学习上下文不受干扰"的产品直觉

---

## 3. 切片播放器

### 核心结论

来源原句/听力词典例句应该是一个**自包含的切片**（slice/clip），不是跳到全片的一个位置。

### 交互设计

- **独立的迷你播放器**，与主播放器完全脱离
- 切片播放器打开时，**自动暂停主播放器**（用户注意力只在单点）
- **默认音频模式**，可展开查看视频画面
- 关闭后主播放器恢复原状，用户的学习上下文不被破坏
- 切片播放器可复用 3.5.6 浮动小窗的容器框架，但**语义上完全不同**：
  - 精听浮窗 = 练习流程容器（cloze/听写/提交）
  - 切片播放器 = 纯播放消费（例句回听/词典播放）

### 入口统一

所有"播放这个词的一个语境"的场景都应走同一个切片播放器组件：

| 入口 | 路径 |
|------|------|
| WordLearningPanel 来源原句列表 | 点击 occurrence → 弹出切片播放器 |
| 词汇本详情页 | 同上 |
| 听力词典搜索结果 | 例句播放按钮 → 同上 |
| 复习卡片例句回听 | 同上（可以复用也可以保持 loopRange） |

### 技术形态

- 独立视频/音频 decoder 实例
- 跨媒体时复用现有文件定位/指纹验证逻辑（`playOccurrence` 已有）
- 不修改 `LexicalOccurrence` 的数据模型（切片数据已完备）

---

## 4. 个人听力词典模型

### 从扁平到词典组织

**当前（扁平）：**
```
LexicalEntry "run"
  └── occurrences: ["I run every morning",
                    "He runs a business",
                    "She went for a run"]       ← 全混在一起
  └── capability: 4通道（无义项区分）
```

**目标（按词典组织）：**
```
LearningObject "run"
  ├── kind: word
  ├── senses:
  │   ├── sense 1: "跑 (verb)"
  │   │     ├── capability: {reading: ✓, listening: △, speaking: ?, writing: ?}
  │   │     └── slices:
  │   │           ├── "I run every morning"
  │   │           └── "She runs fast"
  │   ├── sense 2: "经营 (verb)"
  │   │     ├── capability: {reading: ✓, listening: ✗, ...}
  │   │     └── slices:
  │   │           └── "He runs a business"
  │   └── sense 3: "跑步 (noun)"
  │         ├── capability: {reading: ✓, ...}
  │         └── slices:
  │               └── "went for a run"
```

### 义项模型（新增）

```rust
pub struct LexicalSense {
    pub id: LexicalSenseId,
    pub lexical_entry_id: LexicalEntryId,
    pub definition: String,
    pub part_of_speech: String,
    pub gloss: Option<String>,
    pub source: SenseSource,
    pub confidence: f32,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

pub enum SenseSource {
    DictionaryProvider,  // 从词典 API 导入
    UserDefined,         // 用户手动创建
    Heuristic,           // 自动推测
}
```

### 模型变更量评估

| 变更 | 改动量 |
|------|--------|
| 新建 `LexicalSense` 结构体 | 新增文件 |
| `LexicalOccurrence` + `sense_id: Option<LexicalSenseId>` | 加字段 |
| `LexicalCapabilityProfile.sense_id` 从 None → Some(id) | 使用预留缝 |
| `LearningObservation.sense_id` 从 None → Some(id) | 使用预留缝 |

### 多模态扩展

不只是 word，未来可扩展：

| 类型 | 当前状态 |
|------|---------|
| Word | ✅ 已有 |
| Phrase | ✅ 已有 |
| Collocation | ❌ 需加 |
| Construction | ⏸ spike 待启动 |
| Morpheme/字 | ❌ 未来 |

### 义项消歧（Sense Disambiguation）

这是该模型最大的实操难点——系统如何判断 "run a business" 属于"经营"义项？

分阶段走：
1. **初期**：用户手动指定。用户决定当前句归哪个义项，系统不做自动消歧
2. **中期**：接入词典 API（牛津/剑桥等）自动拉取义项列表，用户做选择
3. **远期**：利用大量 occurrence 上下文做无监督消歧或 LLM WSD

---

## 5. 个人语料图谱

### 核心洞察

用户每一次使用、每一次注意力的投入，都在**建立一本自己的活词典**。从知识图谱角度来说，这是**用户的个人语料图谱（Personal Corpus Graph）**：

```
用户看视频 → 听到 "He runs a business"
           → 点击 "run"
           → 标记 listening: not_acquired
           → 记录来源切片
           → 这条知识边产生了：
               run ──[义项: 经营]──→ [切片: "He runs a business"]
               run ──[搭配]───────→ business
               run ──[时间]───────→ 2026-07-10 学习的
```

### 注意即建图

**每一次交互都为图谱贡献一条边：**

| 操作 | 图谱贡献 |
|------|---------|
| 点击字幕词汇 | 创建/激活节点 |
| 打开词汇面板 | 记录词→句的 attention |
| 标记 not_acquired | 义项级能力断言 |
| 记录来源原句 | 义项→切片边 |
| "测一下"练习 | 产生 evidence，更新通道 |
| 复习标记"听出了" | 强化 listening 通道 |

这和传统知识图谱不同——节点和边不是预设的，而是**从用户的听力输入中自然生长出来的**。

---

## 6. 关键设计决策

### D1. 切片播放器与精听浮窗是独立组件

| 维度 | 精听浮窗 | 切片播放器 |
|------|---------|-----------|
| 用途 | 练习流程（cloze/听写/提交/切句） | 纯播放消费（例句回听） |
| 状态 | 有 session/draft/attempt | 无状态，仅播放 |
| 生命周期 | 启动 → 练习 → 关闭 | 弹出 → 播放 → 关闭 |

两者可以共享浮窗容器框架，但语义和数据流完全独立。

### D2. 切片播放器播放时暂停主播放器

用户注意力只在一个焦点上，切片播放器浮起时自动暂停主播放器。

### D3. 切片播放器默认音频模式，可展开视频

大多数场景只"听"就够了。视频 decoder 开销较高，默认轻量音频模式，需要画面时才启动视频 decoder。

### D4. 义项消歧初期不走自动

用户手动指派义项。等词典 API 接入后再升级。

### D5. 切片播放器的语义是"义项→切片边"的消费端

切片本身 = `LexicalOccurrence`（加 `sense_id`）。不需要新增资源类型。

---

## 7. 未解决的问题 / 待讨论点

1. **LexicalEntry 更名为 LearningObject？** 当前术语偏向"词条"，但模型要覆盖 phrase/collocation/construction，语义上 "LearningObject" 更准确。改名有迁移成本。
2. **词典内容层（definition/part_of_speech/gloss）谁来提供？** 初期用户自己写？还是先不做，等词典 API 接入一起落地？
3. **切片播放器的 B 组用户（loopRange 场景如复习、精听回放、音素证据）是否也要迁移？** 它们在当前媒体语境中，问题比 A 组轻，但原则上也是"劫持模式"。是否统一？
4. **Slice 这个命名是否引入？** 还是沿用 `LexicalOccurrence`（加 `sense_id`），UI 层称为"切片"？
5. **本讨论的落地归属：** 切片播放器放在 3.5.6 浮窗框架后做，还是作为 3.6 听力词典的前置条件？还是独立 phase？

---

## 8. 参考文档

- [Phase 3.6 PLAN — Listening Dictionary MVP](../phases/3.6-listening-dictionary-mvp/3.6-PLAN.md)
- [Phase 3.5.5 — 词汇来源原句记录方案](../phases/3.5.5-intensive-listening-ux-fix/词汇来源原句记录方案.md)
- [Phase 3.4.3 Closeout — Construction Modeling Spike](../phases/3.4.3-construction-modeling-spike/3.4.3-CLOSEOUT.md)
- [Phase 3.4.1 PLAN — Learning Capability Model v2](../phases/3.4.1-learning-capability-model-v2/3.4.1-PLAN.md)
- [Phase 3.5.6 CONTEXT — Intensive Practice Floating Window](../phases/3.5.6-intensive-practice-window/3.5.6-CONTEXT.md)
- [playback_actions_coordinator.dart — playOccurrence](../../apps/desktop/lib/controllers/playback_actions_coordinator.dart#L190-L249)
- [STATE.md](../STATE.md)

## 9. 评审结论（2026-07-10，供后续引用）

对 §7 未解决问题的裁决：

1. **不改名。** `LexicalEntry` 保留；"学习对象"是 UI/读端投影概念，不是领域超类型。
   粒度扩展（collocation 等）走 `LexicalUnit` granularity 轴加常量；construction 按
   ADR 0020 保持独立身份，词典页以独立卡片类型接入，不并入词条模型。
2. **义项内容层：用户文件夹为身份权威。** 义项是用户创建的整理单元；词典 API 义项清单
   只作为"建议新建文件夹"与"对齐注释"，永远不成为身份——与 projection/override 分层同构。
   由此消解词典换版本/义项清单不兼容问题。草案 `LexicalSense` 的 `confidence: f32` 与裸
   `DictionaryProvider` 变体不采纳（溯源不足、UserDefined 下无语义、破坏 Eq）。
3. **B 组 loopRange 场景不迁移。** 语境在当前媒体内，无劫持问题；为对称性统一是无收益重构。
4. **不引入新资源类型。** 数据层沿用 `LexicalOccurrence`（义项落地时加 `sense_id`），
   UI 层称"切片"。
5. **落地归属：** 切片播放器为独立 Phase 3.5.7（纯 Flutter，零契约变更）；听力词典按
   3.6 v2 修订执行——第一刀零新后端（学习对象 → 切片，无义项），corpus index/搜索为
   第二刀；义项文件夹为 3.6.x 独立 phase。2026-07-07"sense spike 排在 3.6 前"修订为
   "排在义项切片前"。图谱视图推迟（纯读端推导、不落库，待数据密度足够再评估形态）。

评审新增的关键问题（义项 spike 的验收问题，比 §7 更根本）：

- **两级画像共存**：义项级画像出现后，词条级读端（字幕高亮、词汇本过滤）的聚合/precedence
  规则。评审倾向：高频读端永远只读词条级，义项级仅在词典详情页展开，sense 不进热路径。
- **证据的义项归属**：`LearningObservation` 按句子记录，义项存在后证据写入是否被迫消歧。
  评审倾向：证据默认写词条级，归属义项后以追加式 re-attribution 表达（兼容 3.4.4
  append-only 语义），不回改历史。
- **核心洞察的边界**：大多数切片永远不会被归入义项——义项必须是可选文件夹，无义项词条
  渲染为"词头 → 切片列表"，不得让未归类切片显得残缺、逼用户做分类作业。

切片播放器补充决策（D1–D5 之外）：

- **D6 焦点策略**：任一浮起播放源独占音频；切片窗打开暂停主播放器（含精听浮窗 range loop
  发声），关闭后不自动恢复播放、主播放器位置不变。
- **D7 技术前提**：第二解码实例可行性由 3.5.7 Slice 0 spike 先证实，spike 阻断即停并由
  owner 裁决降级方案。
