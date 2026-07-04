# 跨平台听力理解播放器 PRD

## 1. 文档信息

- 文档用途：定义产品目标、MVP 范围、核心体验和架构边界
- 当前阶段：Milestone 2 active；Phase 2.21 audible-structure architecture 与
  Phase 2.22 user-facing workflow semantics 并行收敛
- 当前发布：LLPlayerNext 0.7.0 macOS Apple Silicon 单用户版本
- 后续平台：Windows、Linux、Android、iOS
- 参考产品与代码库：LLPlayer
- 需求明细与验收映射：`.planning/REQUIREMENTS.md`
- 实施阶段与交付计划：`.planning/ROADMAP.md`
- 产品定义更新：2026-06-18 14:50:26 CST，将项目拆分为“本地重装生产引擎”
  与“轻量消费端”两条协同路线
- 产品定义更新：2026-06-22，确立多语言听力学习方向（首批 English + Chinese，
  架构对主流 top-15 学习语言封顶有效），以听力能力为核心；详见 §4.4、§15.5
  与 `docs/decisions/0012-multilingual-learning-abstraction.md`
- 产品定义更新：2026-06-28，Phase 2.18 完成非兼容式代码架构重构；学习资产权威模型收敛为
  `LexicalEntry + LexicalUnit + LearningStatus`，旧 `WordProfile` / `WordObservation` 资源、
  旧 API/UI adapter 与旧 SQLite/LLTimeline 兼容路径不再作为 active path 维护。
- 产品定义更新：2026-06-29，真实语流分析的产品中心从 phone-level ribbon 调整为
  rhythm-first listening frame：默认先解释重音节奏、弱读音团、压缩区、停顿和听感锚点；
  phone-level 输出保留为证据层和长期模型质量工作。
- 产品定义更新：2026-07-01，新增 Phase 2.22 user-facing workflow semantics：
  当前所有用户功能，包括媒体播放、URL/下载、字幕获取、资源管理、Word sync、Chunk replay、
  Listening structure、Phone evidence、词汇、诊断、设置、任务中心和 practice/review backend
  readiness，都必须被组织成清晰、可发现、可降级、可验证的用户工作流；“功能完成”不再只等于
  模型/API/局部 UI 完成，也必须包含入口、状态、下一步行动和端到端验证。
- 产品定义更新：2026-07-04，Phase 3.x 学习闭环产品形态确立：精听/泛听为一级心智模型，
  复习/听力词典/dashboard 为资产消费层与回访动线；功能按场景分、不按设备分，各端功能
  全量，生产端（重模型精炼）是唯一 PC-only 能力；闭环是推荐路径不是强制流程，所有功能
  可独立使用；泛听默认零打扰。执行序列 Phase 3.1 ~ 3.10 见
  `.planning/phases/3.0-english-listening-learning-loop/3.0-PHASE-BREAKDOWN.md`。
- 产品定义更新：2026-07-04，明确“本地优先”不等于“仅限本地”：本地媒体、学习资产
  与实时播放路径仍是默认基础，但消费端后续会接入 YouTube 等在线内容来源，并与本地
  内容进入统一学习工作台。同日插入 Phase 3.35，参考每日英语听力的内容层级与播放学习
  组织，先统一桌面 UI、信息架构和视觉系统，再承接 3.4 之后的新功能 surface。

## 2. 产品愿景

构建一套面向多语言听力学习内容生产与消费的本地优先系统。当前以英语为主线，汉语为
第一种真实扩展验收语言；架构对主流 top-15 学习语言封顶有效，不承诺世界所有语言。

产品以**听力能力**为核心：真正可交流的语言能力来自学习者对真实声音流的稳定理解，
文字、词典、语法和翻译是解释层与校准层。系统因此建模
`audio -> listening units -> meaning candidates -> lexical/text explanation`，
而不是把声音当作文字的附属说明。多语言能力通过 language profile / capability matrix /
provider 进入系统，缺失能力干净降级。详见 §4.4。

从 2026-06-18 起，项目明确具有两个身份：

1. **本地重装生产引擎**：面向项目开发者本人，在本机使用最强可用的
   ASR、强制对齐、VAD、人声分离、说话人切换、规则处理和人工校对能力，
   为 CNN10、NBC Nightly News 等新闻类材料生产高精度词级/音素级时间轴、
   ChunkTimeline 和可发布学习视频资源。
2. **轻量消费端 LLPlayerNext**：面向分发版和最终学习使用，既能稳定读取生产端
   产出的标准时间轴 JSON，也能用 bundled whisper.cpp + Rust 轻量分析形成完整的
   本地基础生态：词级高亮、chunk、Listening structure、字幕学习、词汇状态和诊断
   均可用，只是时间与声学精度低于生产端。消费端不内置最重的 FA/CTC 模型，也不以
   最高精度生成时间轴为目标。

用户播放视频或音频时，播放器不仅显示字幕，还会根据用户对每个单词的实际掌握情况进行区分，帮助用户回答：

> 我为什么没有听懂这句话？

这个问题被拆成两条互补路径：

1. **单词问题**：不知道词义、词形、搭配或上下文含义，由词汇状态、词典、观察记录和练习闭环承接。
2. **声音识别问题**：认识这些词但在真实音频中没有听出来，由 rhythm-first listening frame
   承接。系统应优先展示真实听感中的重音锚点、弱读音团、压缩区、停顿和期望/真实错配；
   phone-level expected/observed 对齐作为可展开证据层，而不是默认主视图。

Phase 2.22 进一步要求：这些能力必须以用户任务路径呈现，而不是要求用户理解内部资源名。
典型路径应是：

```text
打开媒体
  -> 本机 Whisper 生成字幕或导入字幕
  -> 自动呈现字幕能力、Word sync、chunk replay、listening structure、phone evidence 的可用性
  -> 用户按当前句进行听感分析、词汇诊断和练习
```

资源 id、provider、JSON 字段和 evidence 细节仍可在高级面板中查看，但不应成为普通使用路径的前置知识。

Milestone 1 MVP 聚焦可靠的听力播放基础设施、基础诊断闭环和最常用的
LLPlayer 桌面学习体验：

1. 稳定播放本地视频与音频。
2. 准确加载、显示并同步字幕。
3. 将字幕拆分为可交互单词。
4. 让用户标记每个词的听力掌握状态。
5. 提供查词、词典音标和当前句诊断。
6. 支持跳转、单句循环和隐藏字幕复听。
7. 同时显示主、副文本字幕，并将主字幕用于学习交互。
8. 支持拖放、内嵌文本字幕学习化、字幕外观设置和可选 `yt-dlp` 在线播放。

Milestone 1 已完成轻量消费端的播放器和学习基础。后续主线转为：

1. 先把本地生产引擎做成可以生成、评估、校对和导出精准时间轴资源的工具链。
2. 再让轻量消费端稳定消费这些资源，并保持无资源时的普通字幕学习能力。
3. 最后基于生产出的 CNN10、NBC 等学习视频和 `.lltimeline.json` 资源，支持发布到
   B 站、YouTube 等平台或随媒体文件分发给消费端。

产品仍暂不追求多人账号、云同步、复杂复习调度、订阅支付或远程服务化生产。

## 3. 背景与现状

### 3.1 LLPlayer 提供的参考价值

LLPlayer 已经实现并验证了大量语言学习播放器所需行为，包括：

- 本地视频和音频播放。
- 在线内容播放。
- 外部字幕和内嵌字幕加载。
- 字幕时间轴与播放位置同步。
- 字幕侧栏、当前句高亮和自动滚动。
- 点击字幕跳转。
- 字幕单词点击、查词和翻译。
- Whisper 转写、OCR、字幕搜索和导出。

这些功能为新项目提供了明确的行为基准、边界案例和测试参考。

### 3.2 为什么不直接继续扩展当前实现

当前 LLPlayer 使用 C#、WPF、Flyleaf、DirectX 和多项 Windows 专用能力，无法直接满足 PC 跨平台和后续移动端目标。

新项目将采用以下策略：

- 将 LLPlayer 作为需求参考、行为参考和测试样例来源。
- 不直接移植 WPF UI 或 Flyleaf 播放内核。
- 不逐行翻译现有代码。
- 优先提取稳定的领域模型、接口契约和行为测试。
- 新的跨平台实现与原 Windows 实现保持清晰边界。

如复制或改造 LLPlayer 源代码，必须遵守其 GPL-3.0-or-later 许可证要求。

## 4. 产品定位

### 4.0 双身份边界

本项目后续所有功能必须先判断属于哪条路线：

| 路线 | 目标 | 可接受依赖 | 输出 |
|---|---|---|---|
| 本地重装生产引擎 | 生成尽可能准确、可评估、可人工修正的时间轴资源 | Python、GPU、Whisper Large-v3、WhisperX、MFA/BFA、Demucs/UVR、pyannote 等研究或重模型依赖 | `.lltimeline.json`、评估报告、校对后的 ChunkTimeline、发布用学习视频 |
| 轻量消费端 | 自成基础学习生态，并可消费生产资源升级质量 | Rust/Flutter/native runtime、whisper.cpp、SQLite、轻量 DSP/本地资源 | 播放、高亮、chunk、Listening structure、词汇状态、诊断 |

消费端的普通 ASR 不是只供占位的降级能力：whisper.cpp 一旦产出词级时间，所有依赖
WordTimeline 的基础功能都必须可用。RMS energy、F0/pitch 等无重模型 DSP 属于 Rust 本地
服务职责。消费端不得为了追求生产级精度而引入大型 Python/PyTorch/MFA/WhisperX 运行时；
生产端/sidecar 使用这些重能力提供更精确的可替换资源。

### 4.1 核心价值

用户没有听懂一句话时，常见原因包括：

- 不认识关键词，不知道词义。
- 认识单词，但在音频中没有识别出来。
- 单词单独能听出，但在句子中因语速、弱读、连读等因素没有识别出来。
- 每个词都认识且能听出，但仍因语法、句式、背景知识或注意力问题没有理解整句。

MVP 首先通过用户主动维护的词汇听力状态，区分：

- 词义理解障碍。
- 声音识别障碍。
- 暂时无法通过词汇状态解释的整句理解障碍。

词典音标用于帮助用户建立拼写与标准发音的联系。真实语流分析、词级强制对齐、
音素级时间轴和 chunk 精修不属于 Milestone 1 MVP；它们从 Milestone 2 起进入
“生产引擎优先、消费端读取资源”的路线。

真实语流分析的默认产品中心不是逐个 phone 的识别结果，而是解释用户实际听到的声音组织。
英语场景下，系统应先建立重音节奏框架，再在局部弱读、连读、压缩或错配区域展开
phone-level 证据。当前 phone recognizer 的 PER 可能偏高，因此 raw phone label 不得作为
默认教学真值；稳定教学标签来自 expected pronunciation，真实音频提供 timing、confidence
和 evidence。

### 4.2 目标用户

首期只有一个明确用户：项目开发者本人。

典型使用材料包括：

- CNN10、NBC 等英语新闻。
- 访谈、播客和演讲。
- 影视或其他真实英语视频。
- 本地视频、音频和字幕文件。

### 4.3 产品原则

- **播放可靠性优先**：播放器基础能力是全部学习功能的前提。
- **诊断优先**：所有学习功能应服务于解释为什么没有听懂。
- **用户判断优先**：词汇状态由用户主动维护，系统只提供辅助线索。
- **词汇资产优先**：词汇状态、状态历史与来源原句快照是最重要的持久化资产，
  不因媒体或字幕文件丢失、移动或删除而消失。
- **本地优先**：媒体和学习数据默认在本地处理与存储。
- **来源开放**：本地优先描述默认数据所有权与处理路径，不把产品限制为 local-only；
  本地文件、URL、YouTube 等在线来源应在统一内容模型和学习工作台中干净共存。
- **前后端契约稳定**：不同 UI 和平台通过统一领域契约共享能力。
- **实时路径本地化**：播放、跳转、时间监听和字幕当前句计算不得依赖远程 API 往返。
- **结果诚实**：数据不足时明确说明，不将推测表达为事实。

### 4.4 多语言与听力本位

产品从英语优先扩展为语言能力可插拔的听力学习底座。以下为战略级原则，具体决策见
`docs/decisions/0012-multilingual-learning-abstraction.md`。

- **听力本位**：语言能力来自对真实声音流的理解；文字、词典、语法是解释层。不同语言的
  听觉单位不同（英语偏 stress/连读、汉语偏音节/声调），架构直接建模这些差异。
- **学习语言 ≠ 界面语言**：界面语言（已有中英文）与正在学习的语言是两件事，不得混同。
- **能力矩阵优先，缺失干净降级**：每种语言声明支持哪些能力（分词、词典、发音、诊断、
  时间轴），不支持的能力显示为不可用/降级，而不是失败或假装支持。
- **唯一不变量是理解轴**：全局词汇状态（词义是否已知 × 声音是否听出）语言无关、跨语言
  复用，是最稳定的学习资产；按语言变化的是诊断**理由**，不是状态本身。
- **听力难度被母语过滤**：真正“听不懂”是（母语, 目标语）配对的函数；诊断模型为母语维度
  预留位置。
- **三类单位分离**：字幕显示单位、词汇学习对象、真实听觉单位是三个独立概念。
- **主流语言封顶，不大包大揽**：架构对主流 top-15 学习语言有效；小语种可加可不加，
  不进承诺。

非目标：本方向不承诺一次性支持世界所有语言，不要求非英语语言一开始具备与英语同等的
时间轴/音素深度，不把界面语言和学习语言混为一谈。

## 5. 平台与技术方向

### 5.1 平台目标

Milestone 1 MVP 必须支持：

- macOS Apple Silicon

Windows 与 Linux 在 MVP 后基于相同领域模型、播放器契约和 API 契约实现。

后续必须能够基于相同领域模型和 API 契约开发：

- Android
- iOS

PC 与移动端可以拥有不同 UI。产品不要求一套 UI 代码运行于所有平台。

### 5.2 系统边界

系统不是传统的纯前端加远程后端。它由三类能力组成：

```text
客户端 UI
  ├── 播放控制与视频渲染
  ├── 当前字幕同步
  ├── 可交互字幕展示
  └── 平台文件与窗口能力

平台播放器适配器
  ├── PC 播放引擎
  ├── Android 播放引擎
  └── iOS 播放引擎

共享领域核心
  ├── 字幕解析与标准化
  ├── 词汇状态与观察记录
  ├── 查词与词典缓存
  ├── 当前句听力诊断
  ├── 内容与学习数据管理
  └── SQLite 持久化
```

### 5.3 推荐技术基线

共享领域核心推荐使用 Rust：

- Rust 核心库承载领域模型与业务规则。
- 桌面阶段提供本地 HTTP API 和 WebSocket 事件。
- OpenAPI 和事件 Schema 作为前后端契约。
- 移动端可通过相同语义契约使用本地 API，或通过 FFI/UniFFI 嵌入 Rust 核心。
- SQLite 用于本地持久化。

Milestone 1 已完成技术验证并选定：

- 桌面 UI：Flutter。
- 桌面播放器：`media_kit/libmpv`。
- 可选桌面工具：`ffmpeg`、`ffprobe`、`yt-dlp`，通过独立适配器调用。
- Android 播放器：Media3 ExoPlayer。
- iOS 播放器：AVPlayer。

React/Tauri 原型未通过可交互视频覆盖层要求，不作为 Milestone 1 基线。

### 5.4 API 边界

适合由共享核心提供的能力：

- 媒体内容登记与元数据。
- 字幕导入、解析、标准化和 token 化。
- 词汇状态读取与修改。
- 当前句诊断。
- 字典查询、音标查询和缓存。
- 学习数据持久化。

必须留在客户端本地播放器路径中的能力：

- 视频渲染。
- 播放、暂停、跳转和倍速。
- 当前播放位置监听。
- 音视频轨道选择。
- 单句区间循环。
- 根据播放位置切换当前字幕。

客户端不得在每次播放位置变化时调用后端 API 查询当前字幕。共享核心应一次性提供标准化字幕时间轴，客户端在本地完成高频同步。

### 5.5 生产端与消费端架构边界

后续架构分为两层：

```text
Production Engine (local, heavy)
  ├── audio preprocessing: vocal isolation / normalization / VAD
  ├── ASR: Whisper Large-v3 or stronger local model
  ├── alignment: WhisperX / MFA / future BFA
  ├── candidate timelines: DTW / WhisperX / MFA / pause-refined / user-adjusted
  ├── chunk generation: VAD gap + speaker change + punctuation + semantic rules
  ├── evaluation: weak comparison + gold benchmark
  └── export: LLTimeline JSON v1 + reports

LLPlayerNext Consumer (light)
  ├── media playback
  ├── bundled whisper.cpp -> coarse WordTimeline
  ├── Rust DSP: pause + RMS energy + F0/pitch
  ├── local baseline: word sync + chunk + RhythmFrame
  ├── import SubtitleTrack and LLTimeline JSON
  ├── karaoke word/phone highlighting
  ├── chunk playback
  ├── vocabulary and diagnosis
  └── optional local correction of imported resources
```

消费端先以 whisper.cpp + Rust 轻量算法形成完整但较低精度的学习能力；生产端生成更高
质量资源替换或增强同一契约。消费端不承担生产端的最重模型职责，但也不因缺少 sidecar
而缺失 WordTimeline 下游功能。

## 6. 核心用户流程

### 6.0 生产并发布新闻学习内容

1. 用户导入一条 CNN10、NBC Nightly News 或类似新闻视频。
2. 生产端抽取音频，并可选分离纯净人声、归一化响度、运行 VAD。
3. 生产端使用 Whisper Large-v3 或更强 ASR 生成带标点 transcript。
4. 生产端使用 WhisperX、MFA 或后续 BFA 将 transcript 与音频强制对齐。
5. 系统保存多个候选 `WordTimeline` / `PhoneTimeline`，并生成候选 `ChunkTimeline`。
6. 用户在本地播放器中预览词跳动和 chunk，手动拖拽修正词边界或合并/拆分 chunk。
7. 系统导出最终 `.lltimeline.json`、评估报告和可发布学习视频资源。
8. 用户将视频发布到 B 站/YouTube，或将媒体文件与 `.lltimeline.json` 提供给消费端。

该流程以生产质量为最高目标，可以使用重模型和人工校对。

### 6.1 打开并学习本地内容

1. 用户选择本地视频或音频。
2. 播放器打开媒体并显示基本元数据。
3. 用户加载 SRT 或 VTT 字幕。
4. 共享核心解析字幕并返回标准化字幕时间轴和 token。
5. 客户端根据播放位置高亮当前句。
6. 用户点击字幕句跳转，或启动单句循环。
7. 用户点击某个单词并查看词义、音标和当前状态。
8. 用户更新单词状态。
9. 当前字幕、字幕文稿和当前句诊断立即更新。

### 6.2 分析没有听懂的句子

1. 用户播放一句话但没有理解。
2. 用户暂停或循环当前句。
3. 用户查看按状态区分的字幕。
4. 用户标记不认识或认识但没听出的单词。
5. 系统显示当前句诊断：
   - 哪些词可能造成词义理解障碍。
   - 哪些词可能造成声音识别障碍。
   - 是否仍存在无法通过词汇状态解释的问题。
6. 用户查看词典音标并重新听当前句。

### 6.3 使用状态驱动词汇本

1. 用户在字幕中主动选择一个词汇状态。
2. 系统保存当前状态、状态变化历史和当前原句来源快照。
3. 词汇自动进入对应的动态词汇本。
4. 用户可在词汇本中搜索、筛选和查看来源原句。
5. 媒体仍可用时，用户可返回原句跳转或循环复听。
6. 媒体不可用时，词汇状态、历史与原句快照仍可完整查看和迁移。

## 7. MVP 范围

### 7.1 播放基础设施

MVP 必须支持：

- 打开并播放本地视频和音频。
- 播放、暂停、停止和跳转。
- 显示当前时间和总时长。
- 调整音量和播放速度。
- 选择可用音轨和字幕轨道。
- 精确跳转到字幕开始时间。
- 循环播放一个字幕句的时间区间。
- 快速切换上一句和下一句。
- 播放错误和不支持格式的明确提示。

### 7.2 字幕基础设施

MVP 必须支持：

- 导入 SRT 和 WebVTT 文本字幕。
- 保留原始字幕文本、换行和时间信息。
- 将字幕标准化为稳定的数据模型。
- 根据播放位置计算当前字幕句。
- 正确处理字幕时间空隙和重叠。
- 在字幕文稿中高亮并滚动到当前句。
- 点击字幕句跳转。
- 显示、隐藏和切换字幕。
- 调整字幕时间偏移。

### 7.3 可交互字幕

MVP 必须支持：

- 将英语字幕拆分为单词、空白和标点 token。
- 保持原始显示文本。
- 点击单词打开单词详情。
- 根据词汇听力状态显示不同样式。
- 在状态变化后立即更新当前可见字幕。

### 7.4 词汇听力状态

MVP 使用以下全局状态：

```text
Unclassified        尚未判断
UnknownMeaning      不认识或不知道词义
KnownNotRecognized  认识且理解，但在音频中听不出
KnownRecognized     认识且能从音频中听出
```

同时支持当前句中的一次性听力观察：

```text
RecognizedInContext     本次听出
NotRecognizedInContext  本次未听出
```

全局状态用于表示用户通常的能力；当前句观察用于记录这个词在具体语境中的表现。两者不得互相错误覆盖。

### 7.5 查词与词典音标

MVP 必须支持：

- 点击单词查看当前词形和规范化 lemma。
- 显示基础词义。
- 显示可获得的美式或英式词典音标。
- 允许切换词汇听力状态。
- 对词典结果进行本地缓存。
- 词典服务失败时不影响播放和状态修改。

单词发音播放、双音标并列和句子逐词音标层属于 MVP 后的增强能力。

### 7.6 当前句听力诊断

MVP 必须基于当前句单词状态显示：

- 不认识的词。
- 认识但听不出的词。
- 尚未判断的词。
- 可能存在的词义理解障碍。
- 可能存在的声音识别障碍。
- 当状态不足或无法解释整句问题时的明确提示。

诊断只提供可解释的线索，不提供绝对结论。

### 7.7 本地数据

MVP 必须本地保存：

- 媒体内容标识与基础元数据。
- 字幕轨道与标准化字幕句。
- 词汇状态。
- 当前句听力观察。
- 词典缓存。
- 最近播放位置和基础设置。

## 8. Milestone 1 非目标

以下内容不进入 Milestone 1 MVP：

- 真实语流音标或音素级对齐。
- 弱读、连读、省音、失爆等自动识别。
- Whisper 或其他 ASR 内置转写。
- OCR 字幕。
- 字幕自动下载。
- OpenSubtitles 搜索与下载。
- 位图字幕显示、OCR 和学习交互。
- 翻译引擎集成。
- 云同步和远程账号。
- 多用户支持。
- 完整词本、记忆曲线和每日复习队列。
- Anki 集成。
- 商业化、订阅和支付。
- Android 和 iOS 正式客户端。

移动端技术验证进入 Milestone 2，不作为 Milestone 1 发布条件。

## 9. 词汇状态与诊断规则

### 9.1 状态语义

| 状态 | 含义 | 诊断用途 |
|---|---|---|
| 尚未判断 | 用户尚未提供判断 | 不得用于确定性诊断 |
| 不认识 | 用户不知道词义或无法理解该词 | 可能造成词义理解障碍 |
| 认识但听不出 | 用户知道词义，但通常无法从音频识别 | 可能造成声音识别障碍 |
| 认识且能听出 | 用户知道词义，也通常能从音频识别 | 通常不是主要词汇障碍 |

### 9.2 诊断约束

- 诊断只基于用户状态和明确规则生成。
- 系统不能擅自将词标记为“认识且能听出”。
- 未分类词较多时，应优先提示信息不足。
- 诊断应优先突出可能承载主要语义的内容词。
- 当所有关键词均认识且能听出时，应提示检查语法、句式、语速、背景知识或注意力因素。
- 诊断结果必须能够说明依据。

## 10. 数据概念

具体数据库 Schema 在技术设计阶段确定。产品层需要以下稳定概念：

### 10.1 MediaItem

- 媒体标识
- 本地路径
- 文件指纹
- 标题
- 媒体类型
- 总时长
- 最近播放位置
- 创建与更新时间

### 10.2 SubtitleTrack

- 字幕轨道标识
- 媒体标识
- 来源类型
- 语言
- 原始文件信息
- 字幕内容指纹

### 10.3 SubtitleSentence

- 字幕句标识
- 字幕轨道标识
- 顺序索引
- 开始时间
- 结束时间
- 原始文本
- 标准化文本
- token 列表

### 10.4 LexicalEntry

- 学习资产标识
- 语言
- `LexicalUnit`：粒度、归一策略、归一 key 和展示词形
- 学习资产类型：word / phrase / char / morpheme 等
- 全局学习状态：unknown meaning / known not recognized / known recognized
- 用户编辑的词义与音标
- 创建与更新时间

唯一性概念为 `Language + granularity + normalization + normalized_key`。

### 10.5 LexicalObservation

- 观察记录标识
- 学习资产标识
- 字幕句标识
- 原始词形
- 本次是否听出
- 创建时间

### 10.6 DictionaryEntry

- 查询词
- 语言
- lemma
- 词义
- 美式音标
- 英式音标
- 数据来源
- 缓存时间

### 10.7 SentenceDiagnosis

- 不认识的词
- 认识但听不出的词
- 尚未判断的词
- 诊断提示
- 诊断依据

该结果默认动态计算，不要求永久保存。

### 10.8 LLTimeline JSON

生产端和消费端之间的数据交换格式。它应以 OpenAI/WhisperX 的 segment/word 结构为
兼容骨架，并增加 LLPlayerNext 所需元数据：

- `schema`: 例如 `llplayer.timeline.v1`。
- `metadata`: 媒体指纹、生成时间、ASR/aligner/VAD/chunk 算法版本、人声分离配置、
  是否人工校对、校对者、许可证和发布信息。
- `segments`: transcript/cue 级文本和时间范围。
- `words`: 词级时间轴，包含 `type`、speaker、confidence、source、provider/version。
- `phonemes`: 可挂在 word 下或作为独立 phone timeline，用于未来音素级高亮。
- `chunks`: 基于 word/phone timeline 生成或人工修正后的学习 chunk。
- `sound_analysis`: 可选真实语流分析视图，优先包含 rhythm frame（stress anchors、
  weak groups、compression spans、phrase boundaries、listening hotspots），并可附带
  learning phones、connected-speech markers 和 phone evidence。
- `artifacts`: 可选记录 whisper/WhisperX/MFA 原始输出、评估报告和校验摘要。

`word.type` 至少应支持：

```text
word | silence | breath | noise | music | speaker_change
```

其中 silence、breath、speaker_change 对 chunk 划分具有一等证据价值。

### 10.9 多语言学习概念（方向）

随多语言方向引入以下概念（战略级，细节见 ADR 0012 与 Phase 2.6 文档）：

- **LanguageLearningProfile**：一种语言声明的能力矩阵（分词、词汇单位、听觉单位、发音、
  韵律、形态、诊断规则、时间轴能力、降级行为）。
- **LexicalUnit**：词汇学习对象，泛化自英语 lemma。身份由两条正交轴决定——粒度
  （字/词/短语/词素）× 归一形态（表层/lemma/citation/词根）；`NormalizedKey` 为归一器
  不透明输出。Phase 2.18 后，active path 以 §10.4 的
  `Language + granularity + normalization + normalized_key` 为权威身份，不再保留旧
  `WordProfile` 兼容路径。
- **ListeningUnit**：真实声音流中需辨认的听觉单位（如 sound pattern、chunk、音节、
  声调音节）。它是现有 Word/Chunk/Phone 时间轴资源之上的视图，不是新的持久存储。
  听力观察可锚定到 ListeningUnit（如声调最小对立），不只锚定 LexicalUnit。
- **RhythmFrame**：句级真实听感视图，组织 stress anchors、weak groups、
  compression spans、phrase boundaries 和 listening hotspots。它是回答“这句话实际应该怎么听”
  的默认声音分析层；phone evidence 是其下的可展开证据。

## 11. API 与事件概念

详细接口要求见 `.planning/REQUIREMENTS.md`。MVP 需要覆盖以下领域能力：

```text
Media
  register local media
  read/update playback progress

Subtitles
  import subtitle file
  get normalized track
  get sentences and tokens

Learning assets
  get lexical entries in batch
  update global learning status
  create lexical observation

Dictionary
  lookup word
  read cached entry

Diagnosis
  diagnose sentence
```

MVP 必须覆盖的领域变化事件：

```text
word-profile.changed
```

可按客户端同步需求增加：

```text
word-observation.created
dictionary-entry.updated
```

当前句诊断是派生结果，默认在当前句或相关词汇状态变化后按需重新计算，不要求独立持久化或推送事件。

播放位置事件属于客户端播放器内部事件，不属于后端 WebSocket 事件。

## 12. 成功标准

### 12.1 功能成功标准

用户能够在 macOS Apple Silicon 上完成同一个核心流程：

1. 打开本地视频或音频。
2. 加载 SRT 或 VTT 字幕。
3. 播放并看到准确同步的当前字幕。
4. 点击字幕跳转并循环当前句。
5. 点击单词查看词义和词典音标。
6. 标记不认识、认识但听不出或认识且能听出。
7. 看到字幕状态样式立即变化。
8. 看到当前句诊断。
9. 关闭并重启应用后，状态和播放进度仍然存在。
10. 同时显示主、副文本字幕并独立调整偏移。
11. 通过拖放打开本地媒体与字幕。
12. 将支持的内嵌文本字幕转换为学习字幕。
13. 在安装 `yt-dlp` 时打开合法、受支持的在线视频 URL。
14. 导入生产端产出的 `.lltimeline.json` 后，消费端可按精准词级时间轴高亮并播放 chunk。
15. 生产端可为一个新闻视频导出含 metadata、word timeline、chunk timeline 和评估摘要的资源文件。

### 12.2 质量成功标准

- 在正常本地媒体播放期间没有明显卡顿或音画同步退化。
- 字幕同步、点击跳转和单句循环能够用于日常听力训练。
- 包含至少 2,000 条字幕句的文稿能够流畅滚动和同步。
- 数据库写入不会阻塞播放路径。
- 后端 API 具有版本化契约和自动化契约测试。
- 共享核心不依赖具体桌面 UI 框架。
- 后续移动端无需重新定义核心领域模型和业务规则。

## 13. LLPlayer 行为参考清单

新项目应优先参考和验证 LLPlayer 中以下行为：

| 能力 | LLPlayer 参考位置 | 新项目处理方式 |
|---|---|---|
| 字幕时间轴与当前句 | `FlyleafLib/MediaPlayer/SubtitlesManager.cs` | 提取行为和边界测试，重新实现 |
| 字幕侧栏与当前句滚动 | `LLPlayer/ViewModels/SubtitlesSidebarVM.cs`、`LLPlayer/Views/SubtitlesSidebar.xaml` | 参考交互，重新实现 UI |
| 字幕逐词拆分与点击 | `LLPlayer/Controls/SelectableSubtitleText.xaml.cs` | 提取 token 行为，移出 UI 控件 |
| 查词弹窗 | `LLPlayer/Controls/WordPopup.xaml.cs` | 参考流程，定义 Dictionary API |
| 点击字幕跳转 | `LLPlayer/ViewModels/SubtitlesSidebarVM.cs` | 纳入 Playback Adapter 契约 |
| 播放时间与字幕同步 | `FlyleafLib/MediaPlayer/Player.Screamers.cs` | 作为客户端本地实时路径重新实现 |
| 字幕测试 | `FlyleafLibTests/MediaPlayer/SubtitlesManagerTest.cs` | 转化为新时间轴引擎测试样例 |

## 14. 风险与待决策事项

### 14.1 最高优先级技术风险

- 桌面播放器方案是否能在 macOS Apple Silicon 上稳定渲染并提供准确位置事件。
- 播放器契约是否保留未来 Windows 与 Linux 实现所需的能力边界。
- 单句区间循环和字幕跳转的准确度是否足够用于训练。
- 客户端 UI 与播放器视频表面组合是否稳定。
- 不同平台媒体解码、轨道选择和硬件加速行为是否一致。

这些风险必须在大规模开发前通过技术原型验证。

### 14.2 产品与数据风险

- 全局词汇状态和当前句观察可能让用户混淆，需要验证交互。
- 媒体或字幕删除级联清除来源记录会损坏最重要的词汇学习资产。
- lemma 归一化错误可能导致状态错误传播，必须允许修正。
- 词典数据来源存在许可、质量、离线能力和稳定性问题。
- 文件移动、字幕变化和重复导入可能造成数据重复，需要稳定身份策略。

### 14.3 架构风险

- 将时间敏感播放控制错误地放入 HTTP API 会造成同步和交互问题。
- 桌面侧车服务架构不能直接照搬到移动端，核心业务必须同时保持可嵌入能力。
- 前后端契约过早包含 UI 细节会限制后续客户端设计。

## 15. Milestone 状态与后续方向

### 15.1 Milestone 1：macOS MVP 0.2.0

状态：已完成。

Milestone 1 包含 roadmap 内部阶段 M0-M6 与 M8。交付物为可独立运行的
macOS Apple Silicon 单用户 MVP、共享 Rust 核心、Flutter 桌面客户端和
版本化契约。完成报告见 `docs/release/milestone-1.md`。

### 15.2 Milestone 1.5：词汇学习资产强化

状态：已完成，随 0.3.0 发布。

Milestone 1.5 将可变状态词汇表确立为产品的核心持久化资产：

1. 以用户选择作为全局词汇状态的权威来源。
2. 按状态提供动态词汇本，状态变化后自动移动，不复制词汇数据。
3. 用户确认状态时保存原句、媒体标题与时间范围快照。
4. 保存状态变化历史，并让当前句观察采用最新有效值。
5. 媒体或字幕不可用时保留词汇状态、历史和来源快照。
6. 媒体仍可用时支持从词汇来源返回原句复听。
7. 词汇学习资产可独立备份、导出与恢复，不依赖原始媒体文件。

完成定义：

> 即使所有原始媒体与字幕文件均不可用，用户仍能完整查看、搜索、备份和
> 迁移自己的词汇状态、状态历史与来源原句快照。

### 15.3 Milestone 2 候选范围

Milestone 2 的主线不再是“先做移动端或普通 ASR 增强”，而是围绕生产端/消费端资源闭环：

1. 定义并实现 `LLTimeline JSON v1` 导入/导出。
2. 建立本地重装生产引擎管线：预处理、Whisper Large-v3/WhisperX/MFA 候选、
   timeline evaluation、人工校对、ChunkTimeline 生成。
3. 让轻量消费端稳定读取 `.lltimeline.json`，驱动词级高亮和 chunk 播放。
4. 建立 TIMIT/Buckeye 小样本与自建新闻 gold set 的 benchmark。
5. 在生产出真实新闻学习视频后，再评估 Windows/Linux、移动端和在线内容增强优先级。

### 15.4 Milestone 1.6：桌面学习体验与词汇初始化强化

状态：已完成，随 0.4.0 发布。交付响应式字幕预设、中英文桌面界面、已有
TXT/CSV 词表初始化、统一词汇学习面板、用户释义与笔记，以及为未来离线或
在线词典保留的多 Provider 聚合边界。当前仍只启用 Free Dictionary API。

### 15.5 Milestone 2：多语言学习基础方向

2026-06-22 确立。产品从英语优先扩展为语言能力可插拔的听力学习底座，首批真实验收语言
为英语 + 汉语。

- Phase 2.5.5 已用真实二语习得研究校验抽象，并用日语、阿拉伯语做类型学证伪，锁定
  “理解轴为唯一不变量、能力矩阵 + provider、母语过滤诊断、开放 taxonomy、听觉单位为
  视图” 等决策（见 ADR 0012）。
- Phase 2.6 在已校验抽象上实现英语 + 汉语：语言感知分词、LexicalUnit、去除 `language=en`
  硬编码、汉语词典/拼音 provider 与最小学习面板。
- 架构对主流 top-15 学习语言封顶有效；小语种可加可不加。

完成定义（方向）：

> 同一套 UI 能打开英语和汉语字幕，按各自语言查询词汇状态、查词与诊断；新增主流语言
> 主要是 provider + profile 工作，不需改动既有语言代码。

### 15.6 Phase 3.0：英语听力学习闭环方向

2026-06-28 确立。Phase 3.0 不是继续堆学习功能菜单，而是在 Phase 2 真实声音流资源与
Phase 2.18 新学习资产架构之上，把英语作为第一门语言做成完整学习闭环：

```text
真实输入
  -> 可理解度判断
  -> 听力障碍诊断
  -> 主动验证练习
  -> 复习巩固
  -> 进度反馈
  -> 回到真实输入
```

核心原则：

- 真正语言能力来自听力突破，听力突破来自大量可理解输入。
- 精听与泛听是两种不同体验：泛听积累输入量，精听解释并修复障碍。
- 词汇学习应围绕真实音频识别，而不是只围绕释义记忆。
- Cloze、听写、字幕渐隐和 chunk replay 是把被动诊断转为主动验证的优先路径。
- Anki / SRS 是复习互操作与补充，不是 LLPlayerNext 权威学习资产模型。
- L1 与 L2 理论进入诊断层，首个真实目标是 Mandarin L1 -> English L2。
- Shadowing 先从 chunk-level 可调速跟读和录音 A-B 对比开始，不先承诺复杂发音评分。
- Dashboard 应解释听力障碍变化和下一步练习，而不是做泛泛打卡统计。
- 进入具体功能扩张前，先通过 Phase 3.0.1 把 Practice / Review / LearningEvent /
  Corpus / Difficulty / LearnerProfile 等学习行为架构立为一等边界。
- 精听 / 泛听是一级心智模型：精听是“发现卡点 -> 诊断 -> 主动验证 -> 处理完毕”，
  泛听是“低摩擦捕获 -> 事后整理”；复习、听力词典、dashboard 是两类场景沉淀出的
  资产消费层与回访动线，不是第三类输入场景。
- 功能按场景分，不按设备分：精听/泛听/复习/词典/整理在所有端全量；生产端
  （重模型精炼）是唯一 PC-only 能力。
- 可组合，不强制流程：闭环是推荐路径；每个功能有独立入口、独立价值，可单独使用。
- 泛听默认零打扰：猎词单等增强必须显式开启并有打扰预算。
- 不课程化、不游戏化：教练只建议不指派；无打卡、无徽章。
- UI 先于继续扩张收口：Phase 3.35 在泛听 Inbox 与 audio-first review 之间统一信息架构、
  视觉令牌和听力工作台；参考每日英语听力的成熟层级，但不复制其品牌、订阅 feed 或界面。

后续工作参考：

- `.planning/phases/3.0-english-listening-learning-loop/3.0-CONTEXT.md`
- `.planning/phases/3.0-english-listening-learning-loop/3.0-PLAN.md`
- `.planning/phases/3.0-english-listening-learning-loop/3.0-PHASE-BREAKDOWN.md`
- `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-ARCHITECTURE.md`
- `.planning/discuss/listen-learning-activity-path.zh.md`
