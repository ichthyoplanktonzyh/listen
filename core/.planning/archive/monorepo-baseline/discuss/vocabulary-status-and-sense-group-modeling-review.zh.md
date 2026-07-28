# 词汇状态与意群建模复核及修正建议

> 日期：2026-07-06  
> 复核对象：`vocabulary-status-and-sense-group-modeling.zh.md`  
> 目的：在不修改原讨论稿的前提下，记录结合当前代码模型得到的补充发现、概念修正与后续建模建议

---

## 一、总体判断

原讨论稿找到了当前学习领域模型中最关键的问题：现有 `LearningStatus` 将词义知识、听力识别和上下文表现压缩到一条线性状态链中，无法表达学习者在不同语言通道上的能力差异。

以下方向可以保留：

1. 阅读、听力、口语、写作应作为并列能力维度，而不是单向升级阶梯。
2. 状态只表达当前能力结论，熟练程度和判断依据应由练习、复习和观测证据承载。
3. 具体句子与抽象句式/构式是两类不同对象。
4. 句内语义加工单位和词汇型多词单位不应继续统称为同一种 chunk。
5. 领域模型应保持语言无关，语言差异由分析器、规则和证据参数承载。

但原方案仍有几个重要概念混合：

- “尚未评估”与“已确认不会”都被表示为 `unknown`。
- 词条形式与具体词义尚未区分。
- 句内语义组块与音频中的韵律组块被当作替代关系。
- 上下文相关的 SenseGroup 被当作可长期掌握的全局学习资产。
- Collocation 被当作粒度，而不是多词表达的词汇属性。
- SentencePattern 的技术接入难度被低估，其身份和归并问题尚未解决。

因此，建议将本次调整理解为一次“学习对象、能力状态、观测证据、素材标注”的重新分层，而不只是枚举扩展和全局重命名。

---

## 二、修正一：每个能力通道不能只有 unknown / known

### 2.1 两种“未知”具有不同业务语义

对于某个词的听力能力，下面两种情况不能合并：

1. 系统没有任何证据，尚未判断学习者是否能听懂。
2. 学习者或练习结果已经明确表明暂时听不懂。

当前代码通过 `LexicalEntry.status: Option<LearningStatus>` 实际保留了这种差异：

- `None`：尚未分类，诊断结果为信息不足。
- `Some(UnknownMeaning)`：已经确认存在词义障碍。

若新模型把四个通道都初始化为 `false`，系统会错误地把“没有数据”解释为“阅读、听力、口语、写作都不会”。

### 2.2 推荐的最小领域状态

每个通道至少应具有以下三种系统状态：

```text
unassessed     尚未评估
not_acquired   已有结论：尚未掌握
acquired       已有结论：已经掌握
```

这不意味着 UI 必须让用户在三项中选择。UI 仍可提供简单的“认识 / 不认识”操作；`unassessed` 是系统在没有证据时的自然状态。

可以定义：

```text
LexicalCapabilityProfile {
  reading:  CapabilityAssessment
  listening: CapabilityAssessment
  speaking: CapabilityAssessment
  writing:  CapabilityAssessment
}
```

“完全不认识”仍然不是独立能力通道，但它应表示为四个通道均已被判断为 `not_acquired`，而不是四个通道均没有数据。

---

## 三、修正二：状态、证据和用户覆盖必须分离

### 3.1 当前证据模型尚不足以支撑四通道画像

原讨论稿认为 `LexicalObservation`、`PracticeAttempt`、`ReviewAttempt` 已能承载能力深度。这个方向正确，但现有 `LexicalObservation` 只有：

```text
recognized_in_context
not_recognized_in_context
```

其身份目前由 `(lexical_entry_id, sentence_id)` 确定，同一句中的新结果会替代旧结果。它没有明确记录：

- 阅读、听力、口语或写作通道；
- 识别、回忆、拼写、跟读或自由表达等任务类型；
- 是否有字幕、首字母、释义、选项等辅助；
- 反应时间、正确程度和作答置信度；
- 同一上下文中的多次历史表现。

因此，四通道改造不仅是将 `LearningStatus` 改成结构体，也需要同步扩展证据语义。

### 3.2 推荐的证据轮廓

```text
LearningObservation {
  learning_object_id
  capability
  task_type
  result
  assistance_level
  context_ref
  occurred_at
}
```

其中：

- `capability` 表示 reading / listening / speaking / writing 等目标能力。
- `task_type` 表示 recognition / recall / dictation / pronunciation / free_use 等具体任务。
- `assistance_level` 区分无提示、上下文提示、字幕提示、选项提示等条件。
- `context_ref` 关联句子、媒体片段或练习项目。

是否采用完全追加式事件记录，可以在持久化设计阶段决定；但至少不能让一次最新结果承担完整学习历史。

### 3.3 能力画像应是投影，不应吞掉证据

建议把三种信息分开：

1. **Observed evidence**：真实练习和诊断结果。
2. **Inferred assessment**：系统基于证据推导的当前能力结论及置信度。
3. **User override**：用户明确声明的状态。

有效状态可以按策略合并，例如用户覆盖优先，但覆盖不删除历史证据。这样将来调整推断算法时仍可重新计算画像。

---

## 四、修正三：词汇能力最终需要词义粒度

### 4.1 词形相同不代表知识状态相同

当前 `LexicalEntry` 主要以语言、粒度和 normalized form 标识词汇对象。这适合当前以 lemma 为中心的词汇本，但无法精确表达多义词：

```text
bank = 银行
bank = 河岸
```

学习者可能认识其中一个词义，却不认识另一个。如果能力状态只挂在 `bank` 词条上，诊断会把局部掌握误判为整体掌握。

类似问题还包括：

- 同一词形的不同词性；
- 熟悉核心义但不熟悉引申义；
- 知道单词本义但不知道特定搭配中的意义。

### 4.2 推荐的长期对象关系

```text
LexicalExpression
  └── LexicalSense
        └── LearnerCapabilityProfile
```

- `LexicalExpression` 表示 word 或 multiword expression 的语言形式。
- `LexicalSense` 表示该形式的具体意义或用法。
- 能力画像原则上关联具体 sense。

考虑到词义消歧和词典数据会显著增加复杂度，第一阶段仍可暂时将能力画像挂在现有 `LexicalEntry` 上，但新模型和迁移格式应预留可选 `sense_id`，避免以后再次进行破坏性迁移。

---

## 五、修正四：SenseGroup 不应替换现有声学 Chunk

### 5.1 两种组块回答不同问题

原讨论稿指出语义切分与声学切分不等价，这个判断正确。但由此得出“用 SenseGroup 替换现有 ChunkTimeline”的结论并不合适。

两者分别回答：

| 对象 | 核心问题 | 主要依据 |
|---|---|---|
| 语义/加工组 | 这句话应如何组合成可理解的意义单位？ | 句法、语义、上下文 |
| 韵律/音频组 | 说话者实际上如何组织并发出这段语流？ | 停顿、重音、延长、音高、语速 |

它们经常对齐，但可能出现：

- 一个语义组被说话者拆成两个韵律组；
- 两个较小语义组在快速语流中合成一个韵律组；
- 修正、犹豫、插入语造成声学边界但不构成语义边界；
- 为强调而产生与默认句法结构不同的韵律边界。

### 5.2 推荐保留双层模型

```text
SenseGroupAnalysis
  └── SenseGroupOccurrence       句子内 token span

ProsodicGroupTimeline
  └── ProsodicGroupOccurrence    音频中的 time span

SenseGroupProsodicAlignment      两层之间的对齐关系
```

其中：

- SenseGroup 以句子和 token 范围为主身份，不要求自身拥有原生时间轴。
- ProsodicGroup 保留现有 `ChunkTimeline` 的时间、置信度、边界来源、candidate / active / archived 生命周期。
- SenseGroup 可通过 WordTimeline 投影出播放区间。
- 对齐关系允许一对一、一对多和多对一。

这既保留当前声学分析成果，也允许新增基于 UD、规则或 LLM 的语义层。

### 5.3 命名建议

`SenseGroup` 可以继续作为产品层中文“意群”的候选名称，但领域内最好避免仅凭名称假设它是纯语义、纯句法或纯韵律对象。

更稳定的命名组合可以是：

```text
SenseGroup / SemanticGroup       语义加工层
ProsodicGroup                    韵律实现层
```

原有 `ChunkTimeline` 可先保持兼容名称，在新模型稳定后再决定是否迁移为 `ProsodicGroupTimeline`，不建议在算法变更前进行全局机械重命名。

---

## 六、修正五：SenseGroup 通常不是全局学习资产

### 6.1 上下文加工单位与可复用知识对象不同

例如句子中的 `the green apple` 可以构成一个语义加工单位，但它通常不是需要跨语境记忆的固定语言资产。换成 `the red apple` 后，学习者也不应重新建立一条独立的长期能力状态。

因此，SenseGroup 更适合被建模为：

- 某个句子的结构化标注；
- 播放、跟读、复述的区间；
- 意群切分或实时理解练习的目标；
- 某次学习表现的上下文载体。

它不一定适合拥有全局的 `listening: known` 或 `speaking: known`。

### 6.2 可复用的多词知识应进入其他对象

如果一个多词片段值得在不同句子间复用和记忆，它通常属于：

- collocation；
- idiom；
- phrasal verb；
- formulaic expression；
- sentence pattern / construction。

SenseGroup 本身可以产生练习记录，但被评估的长期能力可能是：

- 该多词表达的词汇能力；
- 该构式的识别与产出能力；
- 学习者对语流进行实时分组的综合技能。

因此，应从原讨论稿“学习对象与状态模型总览”中移除 SenseGroup 的固定二值能力画像，至少不要默认所有 SenseGroup 都是持久学习资产。

---

## 七、修正六：Collocation 是词汇属性，不是粒度

### 7.1 Word / Phrase 与 Collocation 不在同一分类轴

当前代码中的 `LexicalEntryKind` 是 `LexicalUnit.granularity` 的投影：

```text
word
phrase
```

而 `heavy rain`、`red apple`、`kick the bucket` 都是多词表达，区别在于固定性、组合性和惯用程度，不在于粒度。

如果直接增加：

```text
word | phrase | collocation
```

就会把粒度和词汇属性混到同一个枚举中，并且无法回答 collocation 是否也是 phrase。

### 7.2 推荐分成两个轴

```text
granularity:
  word | multiword

lexical_class:
  free_combination
  collocation
  idiom
  phrasal_verb
  formulaic_expression
  other
```

`lexical_class` 可以是可选分类，并允许将来支持多个标签。第一阶段也可以只把 `Phrase` 更明确地解释为 `MultiwordExpression`，暂不要求自动完成细分类。

---

## 八、修正七：SentencePattern 的能力模型不宜过早压平通道

### 8.1 句式知识和句式在线处理需要区分

抽象构式本身可以被视为通道中立的知识对象，但学习者对它的实际识别仍可能依赖输入方式。例如：

- 阅读时能识别 `the more X, the more Y`；
- 听力中因语速、弱读或工作记忆压力未能实时完成句法分析；
- 写作中会套用某个模板，但口语中无法及时调用；
- 能模仿产出，却不能明确识别或解释结构。

因此，“不存在读得出但听不出一个句式”不应作为领域不变量。

### 8.2 推荐保留抽象画像，同时给证据标注通道

第一阶段可以继续使用简单画像：

```text
ConstructionCapability {
  recognition: CapabilityAssessment
  production: CapabilityAssessment
}
```

但所有练习证据应记录 modality：

```text
recognition observation:
  modality = reading | listening

production observation:
  modality = speaking | writing
```

这样产品早期可以显示简洁的“认识 / 会用”，后续如发现明显的通道差异，可以从已有证据投影出更细画像，而不必重做数据采集。

---

## 九、修正八：SentencePattern 不是业务上最简单的变更

SentencePattern 在技术接入上是增量对象，不必迁移现有数据；但其业务身份比 CRUD 本身困难得多。

需要先回答：

1. 两个形式不同的句式何时属于同一个 Construction？
2. 时态、语态、否定和疑问变体是否归并？
3. 槽位如何表达词性、语义角色和可选成分？
4. 一个具体句子命中多个嵌套构式时如何记录？
5. 用户收藏的是系统构式、用户自定义句模，还是两者的关联？
6. 不同语言中的构式是否存在跨语言关联，还是只在解释层映射？

推荐至少区分：

```text
SentenceExemplar       具体句子，可收藏、回听、练习
Construction           规范化的抽象构式
ConstructionOccurrence 某句对某构式的一次实例化及槽位绑定
UserSentencePattern    用户整理出的个人句模，可关联 Construction
```

这样既不会强迫用户的个人句模完全服从语言学分析，也能在系统识别到规范构式时进行复用和归并。

---

## 十、学习资源、学习资产、素材与标注需要分层

“学习资源最多到 sentence”只有在“资源”专指可建立长期 mastery 的离散学习对象时才成立。Paragraph、dialogue 和 text 仍然可以是重要的练习素材或上下文容器。

建议统一术语：

| 术语 | 含义 | 示例 |
|---|---|---|
| 学习资产 / Mastery target | 可以形成长期能力画像的对象 | 词义、多词表达、构式 |
| 学习素材 / Exemplar | 用于接触、收藏、回听和练习的内容 | 句子、对话、片段、文章 |
| 分析标注 / Annotation | 附着于素材的可重建结构 | token、SenseGroup、韵律组、构式命中 |
| 学习证据 / Observation | 用户在某任务和上下文中的表现 | 听辨失败、听写正确、自由产出成功 |

在这个分层下，Paragraph 和 dialogue 不必拥有 `known / unknown`，但仍然可以作为素材资产长期保存。

---

## 十一、建议的领域对象总览

### 11.1 词汇领域

```text
LexicalExpression
  identity: language + granularity + normalized form
  granularity: word | multiword
  lexical_class: optional classification

LexicalSense
  belongs_to: LexicalExpression
  meaning / usage identity

LexicalCapabilityProfile
  target: LexicalSense，第一阶段可暂挂 LexicalExpression
  reading / listening / speaking / writing
```

### 11.2 句子分析领域

```text
SentenceExemplar
  具体句子及来源

SenseGroupAnalysis
  针对 SentenceExemplar 的语义/加工分组方案

ProsodicGroupTimeline
  针对音频实现的韵律分组方案

SenseGroupProsodicAlignment
  两类分组之间的对齐证据
```

### 11.3 构式领域

```text
Construction
  抽象句法/语义模板

ConstructionOccurrence
  具体句子中的构式实例与槽位绑定

ConstructionCapability
  recognition / production 的当前画像
```

### 11.4 学习过程领域

```text
LearningObservation
  某对象、某能力、某任务下的真实表现

CapabilityProjection
  从历史证据推导当前能力状态

CapabilityOverride
  用户对推导结果的显式覆盖
```

---

## 十二、对实施难度和顺序的修正

### 12.1 风险重新排序

原讨论稿强调 diagnosis-core、UDPipe FFI 和 Schema 迁移。除此之外，更基础的风险是：

1. 未评估与不会之间的数据语义丢失。
2. 四通道状态与现有单通道证据无法对应。
3. 词条级状态在多义词上的误判。
4. 用语义切分覆盖声学切分，导致已有韵律信息丢失。
5. SentencePattern 缺少稳定身份，形成大量近似重复资产。
6. 导入导出时，系统推断状态与用户覆盖状态发生冲突。

### 12.2 推荐实施顺序

```text
阶段 0：领域 ADR
  明确对象身份、unassessed 语义、证据与状态的关系、兼容策略

阶段 1：证据与能力画像基础
  引入通道化 observation / projection / override
  保持旧 LearningStatus 兼容读取

阶段 2：词汇四通道迁移
  新 profile 与旧 status 双读或一次性映射
  重写 diagnosis 对 reading/listening 与上下文证据的使用

阶段 3：新增 SenseGroup 语义层
  保留现有 ChunkTimeline
  先用 provider 接口和固定测试语料验证切分质量

阶段 4：韵律组正式命名与双层对齐
  在新语义层稳定后，评估 ChunkTimeline 是否迁名为 ProsodicGroupTimeline

阶段 5：SentenceExemplar / Construction spike
  先验证身份、抽象、去重和槽位模型，再建设完整学习 UI
```

UDPipe 等具体解析器的 FFI 可提前做独立技术 spike，但不应在 SenseGroup 领域定义稳定之前成为正式架构依赖。

### 12.3 旧 LearningStatus 的迁移只能是近似映射

旧状态可以暂按以下方式迁移：

```text
null
  → 所有通道 unassessed

unknown_meaning
  → reading not_acquired
  → listening not_acquired 或 unassessed（需结合旧交互语义决定）
  → speaking/writing unassessed

known_not_recognized
  → reading acquired
  → listening not_acquired
  → speaking/writing unassessed

known_recognized
  → reading acquired
  → listening acquired
  → speaking/writing unassessed
```

其中 `unknown_meaning` 无法可靠证明学习者在听觉形式下也不知道词义，所以必须明确这是一种兼容推断，而非无损事实转换。迁移记录最好保留 `migration_source`，便于将来区分用户真实判断与系统推定值。

---

## 十三、建议形成的关键领域不变量

正式实现前，建议在 ADR 中至少写下以下不变量：

1. `unassessed` 不等于 `not_acquired`。
2. 能力状态不能替代原始学习证据。
3. 用户覆盖不能删除或改写历史证据。
4. reading / listening / speaking / writing 之间默认不存在强制单向蕴含关系。
5. SenseGroup 是句子上下文中的 occurrence，默认不是全局词汇资产。
6. 语义组与韵律组是独立分析层，允许非一一对齐。
7. Collocation 是 multiword expression 的词汇分类，不是独立粒度。
8. SentenceExemplar 与 Construction 具有不同身份和生命周期。
9. 构式的抽象 mastery 可以通道中立，但产生它的证据必须记录 modality。
10. 所有自动分析产物必须记录 provider、version、confidence，并允许重建。
11. 用户收藏、笔记、覆盖状态等人工资产不能因重新分析而丢失。
12. 旧状态迁移产生的是带来源的推定，不应伪装成用户明确陈述。

---

## 十四、结论

推荐继续推进词汇四通道能力模型，但在实现前增加两个基础概念：

- 每个通道区分 `unassessed / not_acquired / acquired`；
- 将能力画像、观测证据和用户覆盖分开。

对于意群系统，不建议直接执行 `Chunk → SenseGroup` 全局替换。更稳妥的方向是：

- 新增以 token span 为核心的 SenseGroup 语义层；
- 保留当前以时间和声学证据为核心的 ChunkTimeline；
- 将现有 Chunk 在领域意义上逐步收敛为 ProsodicGroup；
- 用对齐关系连接语义结构和实际语流。

对于 SentencePattern，应把它视为业务定义仍需 spike 的新增领域，而不是简单 CRUD。优先解决 Construction 的规范身份、槽位、变体归并和具体句子实例化，再决定完整状态和 UI。

这套修正的核心不是增加更多枚举，而是让四类东西各自回到正确的位置：

```text
学习对象决定“学什么”
能力画像描述“当前会什么”
观测证据记录“为什么这样判断”
句子与音频标注提供“在哪个上下文中学习”
```
