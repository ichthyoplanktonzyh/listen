# 四技能扩展讨论稿评审 —— LLM 语义能力边界与两层复述设计

> 日期：2026-07-11
> 状态：DISCUSSION（评审结论 + owner 方向裁决）
> 上游输入：`.planning/discuss/four-skills-speaking-reading-writing-expansion.zh.md`
> 范围：对四技能扩展讨论稿的批判性评审结论、LLM API 引入的架构边界裁决、
> "说"通道两层复述的产品设计。本文不构成已排期 PLAN，不修改冻结 phase。

---

## 1. 背景

四技能扩展讨论稿（2026-07-11）提出了从听力主线向 speaking / reading / writing
扩展的产品方向。本文是对该稿的第二轮评审讨论记录，形成三个结论：

1. 对原稿的评审意见：方向与证据观正确，但存在未声明的语义评判依赖和 P0 范围过大问题。
2. owner 裁决：接受引入 LLM API 作为语义能力来源，视为四通道发展的必要集成。
3. owner 提出并经讨论细化的"说"通道两层复述设计（L1 意义复述 → L2 表达复述）。

## 2. 对原稿的评审结论

### 2.1 肯定项

- **§6 证据边界矩阵是全稿最有价值的部分**，与 ADR 0015 的
  evidence / projection / override 分层同构，且符合二语习得中
  imitation 与 constructed production 的真实区别。应先于任何功能落地定稿。
- **读听差异诊断（原稿 §4.2）是项目真正的差异化点**：直接消费现有
  meaning fit / sound fit 双维模型与 transcript，边际成本低，归因逻辑有
  Clinton-Lisell 元分析支撑（阅读与听力理解可分离）。全稿性价比最高。
- **3.8 拆 A/B 两个 slice 的建议务实**。3.8-PLAN v2 已明确"不承诺发音评分、
  attempt 不进 content-fit 折算"，边界干净；3.8B（复述/接话）独立成 slice 是对的。
- 任务重复文献（Suzuki 双刃剑、Lambert/Kormos/Minn）支持"立即重说一次 + 延迟重说"
  而非机械连读，原稿用得克制。

### 2.2 批评项

1. **P0 隐藏了未声明的语义评判依赖。** "信息点覆盖 4/6"、"交际意图完成"、
   dictogloss 的"区分内容遗漏/表达差异/语法问题"都不是字符串 diff，而是语义判断：
   人工定义信息点是生产管线成本，自动判定就是 LLM。原稿把 AI feedback provider
   放在 P2，但 P0 的评价机制已隐式依赖同类能力。→ 本轮已裁决：正面引入 LLM
   （见 §3），不再回避。
2. **P0 一次排三个 Studio，违背项目单切片纪律。** 当前 3.3/3.4/3.35 手工 QA 挂起、
   3.5 Slice 9 未完、3.7–3.10 未开工，听力主线尚未完成一轮真实验证。四通道扩张
   应收敛为一个楔子（评审推荐 Reading Studio v1：零新算法依赖、复用最多现有资产）。
3. **说/写通道缺前置 spike。** 按 3.4.3 模板，应先用真实录音 fixture 验证
   "本地与 LLM 各自能诚实测量什么"，把证据语义定下来再谈 Studio。
4. **引用需逐条核实。** 原稿 §10 的 Yanguas 链接指向 SCMC 任务类型研究，
   dictogloss 产生 language-related episodes 的经典出处更接近 Swain & Lapkin 一系。
   原稿为 LLM 参与产出，引用错配是典型失效模式，落 PLAN 前必须核实。
5. **唯一应"现在"吸收的工程动作**：3.7 猎词资产落 modality-neutral shape
   （target modalities seam），开工时是几行 schema 的事，之后补是一次迁移。

## 3. 裁决：引入 LLM API 作为语义能力 provider

### 3.1 立场

owner 裁决：引入 LLM API 做语义相关内容，是项目顺着听说读写发展所必须集成的能力。
评审确认这不违反既有约束——AGENT.md 禁止的是消费端捆绑重型**本地运行时**
（PyTorch/WhisperX 等），API 调用不在其列；STATE.md 亦已有"本地优先不等于仅限本地"
的定位。用户录音的 ASR 走既有 whisper.cpp sidecar 路径。

### 3.2 边界条件（架构约束，非可选项）

这些条件由项目既有原则推出，引入 LLM 不豁免任何一条：

1. **Provider trait 进入 application 层**。与 3.9 L1-aware diagnosis provider、
   writing feedback provider 同一模式；Flutter 端与 route handler 不直接攒 prompt
   调 API。需要一个 ADR 定清楚：
   - 什么数据离开设备（录音转写、字幕原文、用户文本）；
   - 用户知情与开关；
   - 离线 / 无 API key 时的降级路径（功能隐藏或退化为用户自评）；
   - 判定结果的落库形态。
2. **LLM 判定是一种证据类，不是真理。** 在被人工校验前按 `heuristic_proxy` 对待
   （或为其新设证据类）。落库必须带快照：模型 ID、prompt 版本、结构化判定输出。
   换模型不回写历史证据，审计可回溯。
3. **判定结果可被用户 override**，与 3.4.1 user override 分层一致：LLM 说
   "信息点 3 未覆盖"，用户可标"其实我说到了"，两者分别保留。
4. **LLM 输出结构化、可核对的断言，不输出综合分。** 沿用原稿"不给不可解释的
   口语分数"原则：输出"信息点清单逐条 covered / not + 对应用户话语片段引用"，
   而不是"口语 7.2 分"。
5. **LLM 判定质量先过 spike 校验再获得写证据资格**（见 §5）。

## 4. "说"通道两层复述设计

### 4.1 owner 提案

针对"说"的练习分两个层级：

- **第一层**：用户用母语（L1，普通话）说出当前所听内容的意思；
- **第二层**：用正在学习的语言（L2，英语）进行表述；
- 由 LLM 判定两层的内容覆盖与表达情况。

### 4.2 评审细化：这是一个诊断二维，与读听差异诊断同构

| 表现 | 归因 |
|---|---|
| L1 说得清 + L2 说得出 | 理解与产出都通了 |
| L1 说得清 + L2 说不出 | 典型 receptive–productive gap，纯产出障碍，可定位到具体表达 |
| L1 也说不清 | 障碍在理解层，练说是徒劳的，应回到精听 / 词义 |

没有第一层，L2 复述失败无法归因（没听懂 vs 说不出两个混杂变量）。第一层把它们
拆开。测量学依据：L1 自由回忆（free recall）是阅读/听力研究测理解的标准做法，
正是为剥离 L2 产出能力干扰；CEFR Companion Volume 的 mediation 类别
（跨语言转述内容）可承接产品叙事。

### 4.3 三个必须钉死的点

1. **第一层产生 listening 证据，不是 speaking 证据。**
   用 L1 讲清片段意思验证的是意义提取。若 L1 复述成功被写成 speaking evidence，
   3.4.1 的证据诚实体系即被污染。归属：第一层 → listening（meaning 维度）证据；
   第二层 → speaking 证据。此条写入证据矩阵。
2. **第一层是诊断工具，不是每次练习的固定前置步骤。**
   固定"先母语后英语"流程会训练心译习惯（先脑内组织 L1 再翻译），恰是口语流利度
   的头号障碍；L1 使用的研究共识约为"审慎使用有益，习惯化有害"。产品流程：
   默认直接进第二层；第二层失败或用户不确定时，才提供"先用中文说说你听懂了什么"
   作为归因手段。第一层是 X 光，不是每餐必吃的药。
3. **跨语言语义评判先过小规模校验再写证据。**
   LLM 判"中文复述是否覆盖英文原片信息点"是跨语言语义比较，判定质量未验证前
   不得写 capability 证据（见 §5 spike）。

### 4.4 证据矩阵补充条目

在原稿 §6 矩阵基础上追加：

| 行为 | 通道 | 建议证据语义 |
|---|---|---|
| L1 复述覆盖片段信息点 | listening | 意义提取证据（meaning 维度）；不写 speaking |
| L2 复述覆盖信息点且用目标表达 | speaking | 较强生产证据 |
| L1 说得清但 L2 说不出 | speaking | receptive–productive gap 诊断信号，不是失败惩罚 |
| LLM 判定（未经人工校验期） | 任意 | `heuristic_proxy` 级；带模型/prompt 快照；用户可 override |

## 5. LLM-judge spike（前置校验，3.4.3 模板)

在任何 Speaking Studio slice 开工前：

1. 录制十余条真实两层复述 fixture（刻意包含好 / 中 / 差样本，L1 与 L2 各覆盖）；
2. 定义 LLM provider 的输出契约草案：信息点结构、covered/not、用户话语片段引用、
   置信表达；
3. LLM 判定 → owner 人工核对一致率，在 fixture 集上调稳 prompt 与 schema；
4. 通过：LLM 判定获得写证据资格（证据类与快照规则按 §3.2）；
   不通过：记录能力边界，评价机制降级为"客观事实 + 用户自评"。

spike 本身不建生产 schema、不接 UI，与 3.4.3 同纪律。

## 6. 行动顺序（建议）

1. **现在**：
   - 将原稿 §6 + 本文 §4.4 合并定稿为权威 evidence matrix（ADR 或 3.4.x 共享上下文附录）；
   - 起草 LLM provider 边界 ADR（§3.2 五条件）；
   - 3.7 开工时落 modality-neutral 猎词资产 shape。
2. **3.10 收口 + 听力主线真实 QA 之后**：
   - 执行 §5 LLM-judge spike；
   - 只立一个 Studio phase 作为楔子（评审推荐 Reading Studio v1，
     Speaking Studio 在 spike 通过后有可信地基）。
3. **持续约束**：
   - P0 功能的评价机制在 LLM 判定获得资格前，一律"客观事实 + 用户自评"；
   - 原稿 §10 引用在任何 PLAN 引用前逐条核实。

## 7. 未决问题

- LLM 证据类命名：复用 `heuristic_proxy` 还是新设（如 `llm_judgment`）？
  待 evidence matrix 定稿时裁决。
- LLM provider 的成本 / 缓存 / 限流策略（按 attempt 调用的频次控制）。
- 第一层 L1 复述的 ASR 路径（whisper.cpp 中文效果需实测确认）。
- Reading Studio v1 与 Speaking Studio v1 的先后，最终由 owner 在 3.10 收口后排期。
