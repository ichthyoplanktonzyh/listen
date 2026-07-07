# 学习领域模型 v2 精化评审与裁决

> 日期：2026-07-07  
> 复核对象：Phase 3.4.1 落地后的能力画像模型（ADR 0015）+ Phase 3.4.2 已提交的 SenseGroup 领域契约（ADR 0016）  
> 性质：模型层面的第二轮批判性评审。第一轮见
> `vocabulary-status-and-sense-group-modeling-review.zh.md`；本文承接其分层框架，
> 评审已实现的模型还有哪些优化空间，并记录取舍裁决。

---

## 一、总判断

本轮建模在**分类学**上是干净的：学习对象 / 能力画像 / 观测证据 / 素材标注四分层站得住，
`unassessed` 三态、projection/override 分槽、SenseGroup 与 ChunkTimeline 双层分离均与
研究共识一致。剩余优化空间几乎全部集中在**度量学**——程度、置信、时效、粒度：

- 习得被建成了开关（acquired 一旦写入永久有效），而真实词汇习得是带遗忘的连续过程
  （Nation 成分化知识框架；VKS 五级量表；HLR/FSRS 将"会"建模为随时间衰减的回忆概率）。
- 这类维度的共同特点：**字段本身便宜，事后补全是迁移**。因此本文的裁决大多是
  "现在钉字段/分层，算法留给有证据的时候"。

## 二、复杂度分层原则

针对"细化会不会让系统太复杂、太机械"的正当疑虑，确立以下原则（对后续 3.4.x/3.5+ 有约束力）：

| 层 | 细化成本 | 纪律 |
|---|---|---|
| 证据层（记录事实） | 便宜且不可逆（没记的字段永远补不回来；记了不用可随时忽略） | 允许丰富，字段自动采集，用户零感知 |
| 决策层（投影算法、诊断规则） | 昂贵（每个分支都要验证） | 长期保持简单；三态读模型 + 少量规则 |
| 交互层（用户所见所操作） | 致命（机械感的真正来源） | 用户只见"认识/不认识"一次点击；四通道格子是暴露上限；**永远不许出现标注表单** |

反直觉但重要：**粗粒度模型才更机械**。二值状态机的行为是"错一次就翻转"；
带置信度与时效的证据才支撑"最近几次快语速下都没抓住，要不要练练"这类有上下文的判断。

## 三、字段裁决标准（razor）

> 每个新增字段必须同时有：(a) 一个自动填充它的写入方；(b) 一个会因它改变具体决策的消费方。
> 两者缺一，只预留身份位（nullable 字段 / id seam），不建任何机制。

同时警惕泛化诱惑：四个能力通道就硬编码四个，不做可插拔 capability registry。

## 四、优化空间与裁决

### 4.1 投影缺 confidence 与证据时效 —— 采纳（钉 seam 字段）

`CapabilityProjection` 只有 conclusion + algorithm_version + 时间戳，第一轮评审文档
§3.3 提出的"置信度"在实现中丢失。3.5 难度分诊要算 meaning fit / sound fit，
输入只有三态则输出只能是阶梯函数。

**裁决**：给 `CapabilityProjection` 增加 `confidence: Option<f32>` 与
`evidence_as_of_ms: Option<u64>`（投影所依据的证据窗口截止时间），serde 缺省不序列化，
旧 JSON 与旧资产包不受影响。effective assessment 三态读模型保留给 UI 和诊断；
连续值留给排序、分诊、复习调度。Override 保持二值（用户声明本来就是离散的）。
在真正的证据投影算法上线前，两个字段保持 `None`。

### 4.2 证据层通道化 + 投影写入者互斥 —— 采纳（独立 slice，3.5 前置）

`observation → projection` 这根箭头目前不存在：没有任何证据投影算法，observation 仍是
(entry, sentence) 最新覆盖式二值记录。隐蔽风险：projection 槽正在被手工路径
（升级确认、compat sync）当作"手工状态"使用，用得越久，将来真算法上线时合并语义越难定义。

**裁决**：在 3.5 启动前安排独立证据层 slice，落地两件事：

1. Observation 追加式 + 通道化：capability、task_type、assistance_level、
   **surface_form**（见 4.3）、latency；共享上下文 §5.3 轮廓直接可用。
2. 投影写入者互斥规则（已入共享上下文不变量）：一个 (对象, capability) 的 projection
   同一时刻只有一个权威算法来源；algorithm_version 变更即整体重算；
   手工确认路径要么改写为 observation，要么显式声明为高优先来源。

### 4.3 lemma 粒度对听力是"阅读偏置" —— 采纳（证据记 surface form，资产身份不动）

能力画像挂在 lemma 上（"went" 归并 "go"）。对阅读大体成立；对听力不成立——两者语音形式
毫无相似性，听得出 "go" 对听出 "went" 几乎没有预测力（听力词汇量测量普遍主张
flemma/词形粒度）。对听力优先产品，这比多义词问题更早发作：词形归并直接影响
"能不能听出来"这个主诊断轴。

**裁决**：mastery target 身份保持 lemma（否则词汇本爆炸）；listening 证据必须记录
surface form / 语音形式；投影算法可按词形分别给出听力结论、向 lemma 聚合时取保守值。
落点：4.2 的证据 slice。

### 4.4 listening acquired 的条件语义 —— 采纳（一句领域约定）

"能听出这个词"在孤立慢速朗读、有字幕辅助、自然连读语速下是不同能力，产品核心价值是最后一档。

**裁决**（已入共享上下文不变量）：**listening 的 acquired 结论默认指
"无辅助、自然连贯语流"条件；更弱条件下的成功只是证据，不直接支持 acquired 结论。**
不定义此约定，不同投影算法会各自解释，画像失去可比性。

### 4.5 SenseGroup 用户修正应为 overlay —— 采纳（3.4.2 Slice 3 前钉入 ADR 0016）

能力画像侧已确立"系统产物可重建 / 用户资产独立分槽"（不变量 13），但标注层未沿用：
`SenseGroupSource::User` 混在 provider analysis 内。推演：用户手工修正 3 个句子的意群边界，
之后接入更好的 provider 重新生成 analysis，修正要么丢失、要么钉死在旧 analysis 上。

**裁决**：把同一不变量推广为通用模式——自动分析 = 可重建 projection 层；用户修正 =
独立存储的 per-sentence overlay；读侧合并。3.4.2 尚无编辑 UI（无写入方），按 razor
**不建 overlay 机制**，但 ADR 0016 与 schema v23 设计必须不排除它：
用户修正不得以改写 provider analysis 行内数据的方式实现。

### 4.6 Sense 身份 spike —— 采纳（排在 3.4.3 之后、3.6 之前）

`sense_id` seam 预留正确，但回避了所有困难问题：身份锚点（词典义项 / 用户自建 / 聚类）、
entry 级画像在 sense 出现后如何分裂、多词典源义项对齐。**3.6 是 listening dictionary MVP，
义项一进来这些问题全部现场爆炸。**第一轮评审对 Construction 的六个身份拷问可逐条平移到 sense。

**裁决**：3.6 启动前安排 sense 身份 spike（与 3.4.3 Construction spike 同性质）。

### 4.7 混淆词对（minimal pairs） —— 砍掉

听错常是"听成另一个词"（walk/work；邻域激活模型），词对关系确实是听力特有领域对象。
但在证据真的显示用户大量听错成特定词之前，这是投机性设计。

**裁决**：不进 backlog 排期。若未来听写/选择题证据自然出现 `heard_as` 模式，再从证据层衍生。

### 4.8 小项裁决

| 事项 | 裁决 |
|---|---|
| 投影缺证据引用（可解释性："为什么系统认为我听不出"） | 随 4.2 证据 slice 加 `derived_from` 或证据窗口引用，不单独立项 |
| 导入合并用墙钟时间戳仲裁（跨设备时钟偏差） | 砍掉；单用户桌面产品够用，多设备同步立项时再议 |
| Override 无衰老机制（陈年"已掌握"永久压制新证据） | 只保留 ADR 0015 已有的一句"系统可建议用户复核 override"，不设计结构 |
| 无 learner 维度（单用户假设遍布身份设计） | **显式接受**为产品简化，记录于此，避免成为未审视的默认 |
| "词义知识"内嵌于各通道（无通道中立 meaning 维度） | 接受现状；reading 作为 text-mediated meaning 代理已在 ADR 0015 写明；长期解法在 sense 层（4.6） |

## 五、随评审发现的实现级问题

1. **导入来源标注失真**（本分支修复）：外部词表导入与 legacy status 兼容同步共用
   `sync_capability_from_legacy_status`，一律写 `source: EvidenceProjection`，
   而 `CapabilityProjectionSource::Import` 从未使用，稀释不变量 14 的 provenance 语义。
   修复：函数增加 source 参数；导入路径用 `Import`；兼容同步用
   `LegacyLearningStatusMigration`（与一次性迁移共享来源语义，以 algorithm_version
   `legacy-status-compat-v1` / `legacy-learning-status-migration-v1` 区分）。
   `EvidenceProjection` 保留给真证据路径（升级确认）。历史已写入的错误标签不回溯迁移。
2. **诊断 N+1 profile 查询**：`diagnose_sentence` 对句中每个 entry 单独查 profile。
   本地 SQLite 可用；挂账为批量接口优化，随 3.5 诊断改造顺手做。
3. **资产导入不写 capability history**：`import_capability_profile` 绕过 history 表，
   审计链在导入场景有缺口。挂账，随下次 persistence 触碰顺手补。
4. **compat sync 非原子**：逐通道读-改-写、各自开事务。单用户桌面风险低，记录在案。

## 六、执行排期

| 优先 | 事项 | 时机 | 状态 |
|---|---|---|---|
| 高 | ADR 0016 增补用户修正 overlay 决策（4.5） | 3.4.2 Slice 3 之前 | 本次完成 |
| 高 | 投影 seam 字段 confidence / evidence_as_of_ms（4.1） | 立即，增量字段 | 本次完成 |
| 高 | 导入来源标注修复（5.1） | 立即 | 本次完成 |
| 高 | 证据通道化 + surface form + 写入者规则（4.2/4.3/4.8-1） | 独立 slice，3.5 前置 | 待排期 |
| 中 | listening acquired 条件语义入共享上下文（4.4） | 立即 | 本次完成 |
| 中 | Sense 身份 spike（4.6） | 3.4.3 后、3.6 前 | 待排期 |
| — | 混淆词对、时钟仲裁 | 砍掉 | 已裁决 |
| 低 | 诊断批量接口、导入 history、非原子 sync | 随相邻工作顺手 | 挂账 |
