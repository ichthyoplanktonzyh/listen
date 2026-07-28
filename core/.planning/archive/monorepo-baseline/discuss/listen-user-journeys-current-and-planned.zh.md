# listen 用户旅程：现有功能与规划功能

状态：DRAFT

日期：2026-07-03

## 文档目的

这份文档从真实用户视角描述 listen 应该如何被使用。它覆盖两类能力：

- **现有 / 后端已就绪能力**：用户今天已经能触达，或后端模型已经存在但前端体验还没有完整暴露。
- **规划能力**：Phase 3.x 中已经明确方向，但还需要后续产品、架构和 UI 实现的学习闭环。

本文不是实现计划，也不是 API 说明。它回答的问题是：

> 用户打开 listen 后，会怎样一步步把真实音频变成可理解、可练习、可复习的听力能力？

## 状态说明

| 状态 | 含义 |
|---|---|
| Current | 当前用户已经能走通，虽然文案、入口或降级状态可能还需要打磨。 |
| Backend-ready | 后端/domain 地基已经存在，但用户界面还没有完整闭环。 |
| Planned | 产品方向已经写入 Phase 3.x，但还未实现。 |
| Research | 需要外部政策、算法、授权、人工 QA 或产品验证后再落地。 |

## 产品核心判断

listen 不是“播放器 + 背单词”。它的核心旅程是：

```text
打开真实音视频
  -> 获得字幕与学习能力
  -> 正常听
  -> 遇到听不懂的地方
  -> 定位词、chunk 或真实语流问题
  -> 回放真实声音
  -> 主动练习
  -> 保存 observation / review / event
  -> 回到真实输入继续听
```

用户平时应该感觉它是一个安静可靠的播放器；当用户问“我为什么没听懂？”时，它才展开成听力诊断和训练工具。

## 主要用户类型

### U1：精听用户

用户看真实英语材料，经常暂停、回放、查词、听 chunk、看诊断。核心需求是把一句话听懂，并知道哪里没听出来。

### U2：泛听用户

用户想连续听材料，不希望被功能打断。核心需求是稳定播放、字幕、进度恢复、少量难点记录和后续复盘。

### U3：词汇修复用户

用户背过很多词，但真实语速里听不出来。核心需求是区分“知道意思”和“听得出来”，并在真实例句里反复训练。

### U4：资源构建用户

用户导入或生产 `.lltimeline.json` 等高质量资源。核心需求是检查资源能带来哪些学习能力，并能人工校正、导出、复用。

### U5：未来自我教练用户

用户希望 app 告诉自己下一步该练什么：继续泛听、精听某句、复习失败词、练弱读、做 shadowing，或换更合适的材料。

## 总体用户旅程

```text
启动 app
  -> 打开媒体
  -> 获取字幕
  -> 查看当前学习能力
  -> 正常听
  -> 发现听不懂
  -> 用句子、词、chunk、听感结构定位问题
  -> 做练习或保存复习
  -> 继续听
  -> 后续通过复习、听力词典、dashboard 回访
```

## 1. 首次打开：从空 app 到可播放材料

状态：Current

### 用户意图

“我想拿一个真实视频或音频开始学习。”

### 入口

- 中央 no-media 打开媒体按钮。
- AppBar 的 `Open Media`。
- 拖放媒体文件。
- 打开 URL 或下载完成后的媒体。

### 主流程

1. 用户打开本地视频或音频。
2. app 登记媒体，恢复上次播放进度。
3. 播放器显示视频或音频状态。
4. 底部控制条进入可用状态：播放、暂停、跳转、倍速、音量。
5. app 尝试加载该媒体已有的字幕资源和 timeline 资源。
6. 如果已有学习资源，Resources 面板显示当前可用学习能力。

### 用户应该看到

```text
Media: Ready
Subtitles: Ready / Not loaded
Word sync: Ready / Unavailable
Chunk replay: Ready / Unavailable
Listening structure: Ready / Degraded / Unavailable
Phone evidence: Ready / Unavailable
```

### 降级路径

- 媒体无法播放：说明播放失败原因，保留打开媒体入口。
- 已知媒体文件丢失：保留学习数据，让用户重新定位文件。
- 后端启动失败：和媒体错误分开显示，提供 retry。
- 没有媒体：底部控制条不应显得像可操作但无反应。

### 下一步

- 导入字幕。
- 用本机 Whisper 生成字幕。
- 导入 `.lltimeline.json`。
- 或先作为普通播放器播放。

## 2. URL 与下载旅程

状态：Current

### 用户意图

“我有一个在线视频链接，想直接播放或下载后学习。”

### 入口

- AppBar 的 `Open URL`。
- 下载状态条。

### 主流程

1. 用户粘贴 URL。
2. app 尝试解析直接可播放媒体，或在配置了 `yt-dlp` 时调用下载/解析。
3. 用户选择直接播放或下载为本地文件。
4. 直接播放进入在线媒体会话。
5. 下载显示进度、支持取消。
6. 下载完成后，用户打开本地文件，回到标准本地媒体学习路径。

### 降级路径

- 没有配置 `yt-dlp`：说明需要到 Settings 配置工具路径。
- URL 不支持：说明当前工具无法解析该来源。
- 下载失败：保留错误和 retry。
- 在线播放未注册为本地媒体：提示本地字幕、资源、复习能力可能受限。

### 下一步

- 打开下载后的本地媒体。
- 导入或生成字幕。
- 进入正常听力学习。

## 3. 字幕获取旅程

状态：Current

### 用户意图

“我需要文本和媒体对齐，这样才能看、听、查、诊断。”

### 入口

- 导入 SRT/VTT 主字幕。
- 导入 SRT/VTT 副字幕。
- 本机 Whisper 生成字幕。
- 提取内嵌文本字幕。
- OpenSubtitles 搜索下载。
- 拖放字幕文件。

### 主流程 A：导入 SRT/VTT

1. 用户导入字幕文件。
2. app 解析并标准化成字幕句和 token。
3. 主字幕出现在 overlay 和 transcript。
4. 用户可以点击句子、循环句子、点击单词、使用词汇和诊断。
5. 能力摘要显示：Subtitles 可用；Word sync、Chunk replay、Listening structure、Phone evidence 视资源情况显示 unavailable 或 degraded。

### 主流程 B：本机 Whisper 生成字幕

1. 用户打开字幕生成对话框。
2. 选择语言、模型、质量和目标轨道。
3. app 创建本地转写任务。
4. 任务中心和状态反馈显示进度。
5. 完成后自动或手动加载生成字幕。
6. app 用用户语言总结生成结果：

```text
字幕已生成
Word sync: 已可用 / 需要词级 timing
Chunk replay: 已可用 / 可后续生成
Listening structure: 已可用 / 降级 / 需要 Word sync
Phone evidence: 尚未分析
```

### 主流程 C：提取内嵌字幕

1. 用户打开内嵌字幕提取。
2. app 用 ffprobe/ffmpeg 检测媒体内字幕轨道。
3. 用户选择可提取的文本字幕轨道。
4. 提取结果作为普通字幕资源进入当前媒体。

### 主流程 D：OpenSubtitles

1. 用户搜索当前媒体的在线字幕。
2. 选择结果并下载。
3. 下载字幕作为主字幕或副字幕导入。
4. 后续能力和普通 SRT/VTT 一致。

### 降级路径

- 普通字幕没有词级 timing：仍可学习，但 Word sync 和精确听感结构不可用。
- 只有副字幕：需要说明哪条字幕用于学习交互。
- 内嵌位图字幕：说明暂不支持直接文本学习。
- OpenSubtitles 缺 API key 或搜索失败：给出设置入口和 retry。

### 下一步

- 正常播放。
- 生成或导入 timeline 资源。
- 点击单词进入词汇学习。

## 4. 字幕资源与 Timeline 资源旅程

状态：Current

### 用户意图

“我想知道当前字幕资源到底能支持哪些学习能力。”

### 入口

- Subtitle Resources 页面。
- Resources 侧边栏。
- 导入/挂载 `.lltimeline.json`。
- 导出 SRT 或 `.lltimeline.json`。

### 主流程

1. 用户打开 Resources。
2. app 展示当前媒体的字幕资源。
3. 用户可以激活、归档、恢复、删除、导出字幕资源。
4. 对 active subtitle，app 先展示用户能力：

```text
Subtitles
Word sync
Chunk replay
Listening structure
Phone evidence
Production artifacts
```

5. 高级用户可以继续看 WordTimeline、ChunkTimeline、PhoneTimeline、provider、artifact 和 lifecycle。
6. 用户导入 `.lltimeline.json`。
7. app 检查媒体 fingerprint，不匹配时请求确认。
8. 资源导入后，能力摘要更新。

### 降级路径

- fingerprint mismatch：说明风险，让用户确认是否仍挂载。
- timeline 只是 candidate：提示需要 activate 才能作为当前能力来源。
- Listening structure 缺失：不要暗示必须先有 Phone evidence。
- Word sync 是 estimated：显示 degraded，而不是和 audio-backed timing 等价。

### 下一步

- 激活最佳资源。
- 运行生成/分析任务。
- 用 Word sync、Chunk replay、Listening structure 或 Phone evidence 学习。

## 5. 正常听材料旅程

状态：Current

### 用户意图

“我想像普通播放器一样听，但学习能力随时可用。”

### 主流程

1. 用户开始播放。
2. 字幕 overlay 跟随播放。
3. Transcript 可跟随当前句自动滚动。
4. 如果有 Word sync，当前词轻量高亮。
5. 如果有 ChunkTimeline，当前 chunk 可以高亮。
6. 用户不需要每句话都进入学习模式。
7. app 保持当前上下文，方便用户随时暂停、回放、查词、诊断。

### 降级路径

- 没有字幕：媒体仍可播放，学习动作提示先获取字幕。
- 没有 Word sync：句子级学习仍可用。
- 没有 Chunk replay：保留句子循环。
- 没有 Listening structure：不显示空的听感教学层。

### 下一步

- 继续听。
- 回放当前句。
- 点击没听出的词或 chunk。

## 6. 句子复听旅程

状态：Current

### 用户意图

“刚才这句话没听懂，我要再听几遍。”

### 入口

- 当前句循环。
- 上一句/下一句。
- transcript 点击句子。
- subtitle overlay 点击跳转。

### 主流程

1. 用户开启当前句循环。
2. app 在字幕句的 start/end 区间循环播放。
3. 用户可以调速、暂停、退出循环。
4. 当前字幕、transcript、词高亮和诊断保持同步。
5. 用户听懂后继续播放；仍不懂则进入词、chunk 或诊断工具。

### 降级路径

- 字幕时间粗糙：循环可能包含多余空白或裁剪，必要时说明。
- 没有字幕：句子循环不可用。
- 在线媒体 seek 不稳定：保留基础播放并说明限制。

### 下一步

- 点击没听出的词。
- 改用 chunk replay。
- 打开诊断。

## 7. Word sync 旅程

状态：Current

### 用户意图

“我想知道现在听到的是哪个词。”

### 主流程

1. app 加载 active WordTimeline 或 generated word timings。
2. 播放时当前词高亮。
3. 用户把文字位置和声音位置对应起来。
4. 用户点击词打开词汇学习。
5. Word sync 成为后续 cloze、dictation、听力词典、review 的锚点。

### 降级路径

- timing 是 estimated：Word sync 显示 degraded。
- 没有 word timings：词级高亮不可用，但句子学习可用。
- 切换字幕后资源可能 stale：提示刷新或重新挂载。

### 下一步

- 使用 chunk replay。
- 打开词汇学习。
- 导入或生成更好的 timeline。

## 8. Chunk replay 旅程

状态：Current

### 用户意图

“整句太长，我想听一个有意义的小块。”

### 入口

- 底部 chunk 控制。
- TokenLine chunk 分组。
- Resources 能力摘要。

### 主流程

1. app 加载 active ChunkTimeline 或 chunk partitions。
2. TokenLine 显示 chunk 分组。
3. 用户跳到上一/下一 chunk。
4. 用户循环当前 chunk。
5. 用户从一个 chunk 扩展到相邻 chunk，再回到整句。
6. chunk 成为未来 dictation、cloze、shadowing 的默认单位。

### 降级路径

- 没有 ChunkTimeline：说明 chunk 控制不可用，句子循环仍可用。
- chunk 基于弱 timing：显示 degraded。
- 切换字幕后 chunk stale：清空或刷新 chunk 状态。

### 下一步

- 做 chunk dictation。
- 保存 chunk 到 review。
- 未来进入 shadowing。

## 9. Listening structure 旅程

状态：Current / improving

### 用户意图

“我认识这些词，但不知道这句话实际该抓哪些声音。”

### 入口

- 字幕 overlay 的 Listening structure layer。
- Diagnosis card。
- Resources 能力摘要。
- 本机 Whisper 或 `.lltimeline` 结果摘要。

### 主流程

1. 用户打开 Listening structure。
2. app 展示 stress anchors、weak groups、compression spans、phrase boundaries、nuclei、listening hotspots。
3. 用户点击 cue 复听对应声音区域。
4. 用户对比：

```text
A: citation form
B: default connected form
C: actual delivery
```

5. 用户理解“文字上是这样，但真实听感为什么像那样”。

### 降级路径

- 只有 text prior：必须标为 predicted，不说成 actual audio。
- 没有 Word sync：说明缺少真实 timing 证据。
- 没有 energy/phone evidence：可以保留低置信解释，但要说明证据来源。
- 完全没有 Listening structure：建议生成/导入资源，或继续用句子/chunk 复听。

### 下一步

- 复听 hotspot。
- 打开诊断。
- 未来把 cue 变成 practice/review。

## 10. Phone evidence 旅程

状态：Current / specialist layer

### 用户意图

“我想看更细的 phone-level 证据：弱读、连读、省音、错配。”

### 入口

- overlay Phone evidence 模式。
- Diagnosis card。
- Audio/Phonetic Analysis Center。
- Analyze current sentence / whole track。

### 主流程

1. 用户运行或打开 audio/phonetic analysis。
2. app 显示分析任务状态。
3. 有结果时，当前句显示 phone evidence。
4. 用户把 phone evidence 当作证据层，而不是默认学习层。
5. 用户可以复听相关 phone 或 sound-pattern 区域。

### 降级路径

- provider/model 未配置：引导用户设置。
- 任务运行中：显示 generating。
- 没有 detected phones：明确说 Phone evidence 不可用，但不影响已有 Listening structure。
- raw mismatch 或低置信：不能作为教学真值默认展示。

### 下一步

- 用 evidence 理解 hotspot。
- 重新生成资源。
- 如果默认 Listening structure 足够，就关闭该层。

## 11. Word learning 旅程

状态：Current

### 用户意图

“我想知道这个词什么意思、我是否听得出来、它来自哪句话。”

### 入口

- 点击 overlay/transcript token。
- Vocabulary screen。
- Diagnosis lexical barrier。
- 未来 Listening dictionary result。

### 主流程

1. 用户点击单词。
2. Word learning 侧边栏立即打开。
3. app 加载 lexical entry、dictionary、pronunciation、language profile、source context。
4. 用户设置 `LearningStatus`：

```text
unknown_meaning
known_not_recognized
known_recognized
```

5. 用户添加自定义释义或笔记。
6. app 更新词样式并刷新诊断。
7. 来源原句作为 durable snapshot 保留，不因媒体移动或删除而丢失。

### 降级路径

- 词典离线：仍允许状态、笔记、自定义释义。
- lemma 错误：进入 correction flow。
- 来源媒体丢失：显示 source snapshot 和恢复入口。
- phrase 未确认：word 与 phrase 资产保持独立。

### 下一步

- 复听来源句。
- 确认 phrase candidate。
- 未来打开听力词典找更多真实例句。
- 未来生成 practice/review。

## 12. Vocabulary book 旅程

状态：Current

### 用户意图

“给我看我正在学的词，尤其是知道意思但听不出来的词。”

### 主流程

1. 用户打开 Vocabulary。
2. 按状态过滤或搜索。
3. 打开 lexical entry。
4. 查看释义、笔记、发音、状态、历史、来源上下文。
5. 导入/导出词汇资产。

### 降级路径

- 导入冲突：保留较新的本地状态，不盲目覆盖。
- 来源媒体丢失：保留来源句快照。
- word/phrase identity 不清：进入 phrase 或 lemma correction。

### 下一步

- 复习 `known_not_recognized`。
- 打开 source clip。
- 未来通过听力词典寻找更多真实声音例句。

## 13. Diagnosis 旅程

状态：Current / expanding

### 用户意图

“我为什么没听懂这句话？”

### 入口

- 当前句 Diagnosis side panel。
- 词汇状态变化后自动刷新。
- 未来 practice failure 后进入。

### 主流程

1. 用户打开当前句诊断。
2. app 读取 lexical entries 和最新 observations。
3. 诊断区分：

```text
词义未知
知道意思但没听出
证据不足
听感结构 / sound evidence 问题
仍无法解释的整句困难
```

4. 用户看到简短原因和下一步行动。
5. 用户可以打开词、复听 cue、运行分析、未来开始 practice。

### 降级路径

- 缺词典：词汇状态仍可用，释义解释降级。
- 缺 Word sync：不能提供精确 sound window。
- 缺 Listening structure / Phone evidence：明确说明缺哪层证据。
- 词状态不足：先引导用户标记关键词，不做过度解释。

### 下一步

- 标记词汇状态。
- 复听 chunk。
- 生成 Listening structure 或 Phone evidence。
- 未来创建 practice/review。

## 14. Settings 与工具设置旅程

状态：Current

### 用户意图

“我要把 app 设置好，让我的常用流程能跑通。”

### 主流程

1. 用户打开 Settings。
2. 设置 UI language 和 learning language。
3. 调整字幕、transcript、颜色、位置、word/chunk 样式。
4. 配置 `ffmpeg`、`ffprobe`、`yt-dlp`、transcription defaults、OpenSubtitles key、pronunciation/audio-analysis provider、model、cache。
5. Settings 只作为默认偏好和工具配置；主要学习能力应在上下文入口中被发现。

### 降级路径

- 工具路径缺失：从具体功能入口解释缺失，并链接到 Settings。
- API key/model 无效：保留错误并允许 retry。
- 内部术语：只保留在 advanced section。

### 下一步

- 回到刚才需要设置的功能。
- 重新运行字幕生成、下载、提取或 audio analysis。

## 15. Task center 与恢复旅程

状态：Current / improving

### 用户意图

“有任务在跑或失败了，我要知道发生了什么，怎么恢复。”

### 入口

- Transcription Center。
- Audio/Phonetic Analysis Center。
- Download bar。
- Global status/snackbar。
- Logs export。

### 主流程

1. 用户启动长任务。
2. inline feedback 显示进度。
3. task center 记录任务历史和操作。
4. 完成后，app 应总结用户能力结果，而不仅是 job completed：

```text
Generated subtitle loaded
Word sync ready
Listening structure ready/degraded
Phone evidence not generated yet
```

5. 用户可以打开结果、retry、或导出 logs。

### 降级路径

- 事件丢失：task center 能恢复当前状态。
- 任务失败：保留错误和 retry。
- 下载取消：late process output 不应让已关闭的下载条复活。
- free-form status string：只作为摘要，不作为核心状态。

### 下一步

- 加载完成资源。
- retry 或调整设置。
- 如果任务是可选增强，继续播放。

## 16. Practice 旅程

状态：Backend-ready / Planned UI

### 用户意图

“我想证明自己真的听出来了，而不是只是看懂字幕。”

### 规划入口

- 当前句/当前 chunk。
- Diagnosis card。
- Word learning panel。
- Listening dictionary result。
- Review queue。

### 规划主流程

1. 用户从句子、chunk、词或诊断点击 `Practice`。
2. app 创建 `PracticeItem`，包含 prompt、expected answer 和 anchors。
3. 用户进入一种练习：

```text
cloze
dictation
subtitle fade
shadowing
```

4. app 播放真实音频片段。
5. 用户提交文本、评分或录音。
6. app 创建 `PracticeAttempt`。
7. 失败的 lexical anchors 生成 `LexicalObservation`。
8. app 可选创建 `ReviewItem`。
9. app 写入 `LearningEvent`。
10. UI 显示结果：错在哪里、为什么、下一步做什么。

### 规划降级路径

- 没有 Word sync：允许句子级 dictation，但禁用精确 word cloze。
- 没有 chunk：回退到 sentence。
- 媒体缺失：保留 prompt snapshot，标记 audio unavailable。
- 练习失败：不静默修改全局 `LearningStatus`。

### 下一步

- 立即重练。
- 保存到 review。
- 打开听力词典找更多失败词/短语例句。

## 17. Review 旅程

状态：Backend-ready / Planned UI

### 用户意图

“把我真正没听出来的东西带回来，再测一次。”

### 规划入口

- Review queue。
- Vocabulary book。
- Practice result。
- Listening dictionary saved examples。

### 规划主流程

1. 用户打开 Review。
2. app 从 lexical entries、practice failures、chunks、sentences、connected-speech cases 创建复习队列。
3. 用户收到 audio-first prompt：

```text
听目标词
填 cloze
听写 chunk
跨多个 clip 辨认 phrase
评价 shadowing attempt
```

4. 用户提交答案或 rating。
5. app 记录 `ReviewAttempt`。
6. 结果可能生成新的 observation 或 practice attempt。
7. dashboard/event ledger 聚合结果。

### 规划降级路径

- 来源媒体丢失：显示 prompt snapshot，跳过音频卡或请求重新定位媒体。
- review item stale：保留 item，尽量刷新 anchors。
- 证据低置信：不把不可靠音频 case 强行排进复习。

### 下一步

- 继续复习。
- 打开来源 clip。
- 只有用户确认时才调整全局状态。

## 18. 听力词典 / Corpus recall 旅程

状态：Planned

### 用户意图

“把这个词或短语放到很多真实声音里听，训练我在不同人、不同语境中认出来。”

### 规划入口

- 字幕 token click。
- Word learning panel。
- Diagnosis result。
- Vocabulary book。
- Search box。
- Practice/review failure。

### 规划主流程

1. 用户搜索 word、phrase、chunk 或 connected-speech family。
2. app 搜索当前媒体、个人本地语料、已保存例句和可选外部 provider。
3. 结果显示 playable segments：

```text
source title
subtitle context
target highlight
word/chunk/sentence play controls
accent/source hints if available
availability state
Listening structure cues if available
```

4. 用户连续听多个真实例句。
5. 用户保存好的例句。
6. 用户从例句生成 cloze、dictation 或 review。
7. app 记录用户在不同 speaker、语速、句中位置和上下文中的识别表现。

### 规划降级路径

- 本地无结果：提供 YouGlish 外链/嵌入或词典发音作为临时参考。
- 外部结果不可播放：允许打开原网页，但不把它当作本地可练习音频。
- caption 不可信：标低置信，不生成 dictation。
- 版权/API 限制：只在允许时缓存 metadata/source snapshot，不默认系统性下载外部音视频。

### 下一步

- 做目标词练习。
- 加入 review。
- 导入更多个人媒体扩充语料库。

## 19. 可理解输入与难度旅程

状态：Planned

### 用户意图

“这段材料现在适合我吗？是太简单、刚好、挑战、还是太难？”

### 规划入口

- 媒体库。
- 当前媒体摘要。
- segment/chunk recommendation。
- Dashboard。

### 规划主流程

1. app 为 media、sentence、segment 或 chunk 计算 difficulty profile。
2. 信号包括：

```text
unknown word density
known_not_recognized density
speech rate
chunk complexity
connected-speech density
resource quality
past user performance
```

3. 用户看到 fit：

```text
too_easy
comprehensible
challenging
too_hard
```

4. 用户选择泛听或精听。
5. app 推荐下一段材料或练习类型。

### 规划降级路径

- 词汇状态不足：提示先标记关键词。
- 没有 Word sync：语速和 chunk 精度降级。
- 没有历史记录：给出保守初始估计。

### 下一步

- 开始泛听。
- 进入精听练习。
- 保存材料以后再听。

## 20. L1-aware diagnosis 旅程

状态：Planned

### 用户意图

“为什么我的中文母语听觉习惯会让我漏掉这个英语声音？”

### 规划入口

- Diagnosis card。
- Practice failure。
- Listening dictionary connected-speech family。
- Specialty practice。

### 规划主流程

1. 用户分别设置 UI language、L1、L2。
2. app 识别当前 profile 为 Mandarin -> English。
3. 当失败命中某类难点时，诊断增加短提示：

```text
weak function words
schwa/reduced vowels
final consonants
consonant clusters
t/d deletion
flapping
linking
stress-timed rhythm
compressed forms
```

4. 提示必须回到真实音频复听。
5. 用户从自己的媒体例句进入专项练习。

### 规划降级路径

- 未设置 L1：只显示基础诊断。
- 不支持的 L1/L2 profile：避免空泛刻板解释，只显示语言中立听力提示。
- 缺真实例句：先使用当前 clip 或引导用户构建语料。

### 下一步

- 练相似 clips。
- 加入 review。
- 在 dashboard 看该难点是否改善。

## 21. Shadowing 与录音对比旅程

状态：Planned

### 用户意图

“我已经能听出来了，现在想模仿真实 chunk，并和原音比较。”

### 规划入口

- Chunk replay。
- Practice mode。
- Listening structure cue。
- Review item。

### 规划主流程

1. 用户选择一个 chunk。
2. app 以 0.75x、0.9x 或 1.0x 播放 reference audio。
3. 用户录音。
4. app 保存 `RecordingAsset`。
5. app 比较时长、停顿位置和粗节奏。
6. 用户 A/B 播放：原音、自己、原音。
7. app 保存 `PracticeAttempt` 和可选 `ShadowingComparison`。

### 规划降级路径

- 麦克风权限缺失：解释并引导系统设置。
- 没有 chunk：允许 sentence-level shadowing。
- 没有复杂评分：仍提供播放、录音、时长和停顿对比。
- 媒体之后丢失：保留录音和 prompt snapshot。

### 下一步

- 重录。
- 保存最好一次。
- 把难 chunk 加入复习。

## 22. Dashboard 旅程

状态：Planned

### 用户意图

“告诉我我的听力哪里变好了，下一步该练什么。”

### 规划入口

- Dashboard screen。
- session 结束总结。
- review 完成总结。

### 规划主流程

1. app 聚合 `LearningEvent`、`PracticeAttempt`、`ReviewAttempt`、`LexicalObservation` 和 status history。
2. Dashboard 显示听力相关进度：

```text
泛听时长
精听句子数
cloze/dictation 正确率
known_not_recognized -> known_recognized 变化
反复漏听词
connected-speech family
L1-aware difficulty groups
值得回访的材料
```

3. Dashboard 推荐下一步：

```text
复习到期项目
练 weak function words
回听曾经困难的 clip
换更容易的输入
对已掌握 chunk 做 shadowing
```

### 规划降级路径

- 历史不足：显示 starter checklist。
- 老版本缺 event：聚合已有数据并说明 insight 有限。
- 媒体不可用：保留 source snapshot，推荐可恢复项目。

### 下一步

- 开始 review。
- 打开推荐 corpus examples。
- 继续当前材料。

## 23. 生产资源构建旅程

状态：Current developer workflow / Planned user-facing polish

### 用户意图

“我想为严肃学习或发布生成高质量时间轴资源。”

### 入口

- Production pipeline scripts。
- `.lltimeline.json` import/export。
- Manual WordTimeline review。
- Resource evaluation reports。

### 主流程

1. 用户准备源媒体和 transcript/subtitle。
2. 生产管线生成 WordTimeline、ChunkTimeline、PhoneTimeline、RhythmFrame、artifacts、reports。
3. 用户导入 `.lltimeline.json`。
4. app 显示能力 readiness。
5. 用户进行 Manual WordTimeline review。
6. 保存 user-adjusted candidate 并激活。
7. 导出更新后的 `.lltimeline.json`。

### 降级路径

- 消费端没有重模型：说明 production generation 与 lightweight playback 分离。
- alignment 质量差：标 degraded，进入人工校对。
- artifact mismatch：不要静默声称能力可用。

### 下一步

- 用资源学习。
- 合法前提下发布/分发资源。
- 将例句加入 corpus/review。

## 24. 当前端到端旅程：普通字幕学习

状态：Current

```text
Open local media
  -> Import SRT/VTT
  -> Play with subtitles
  -> Loop current sentence
  -> Click unknown word
  -> Read definition/pronunciation
  -> Set LearningStatus
  -> Diagnosis updates
  -> Continue listening
```

体验目标：

- 快速可靠。
- 对缺少 Word sync 或 sound evidence 保持诚实。
- 没有高级资源也有学习价值。

## 25. 当前端到端旅程：生成字幕学习

状态：Current

```text
Open local media
  -> Generate subtitles with local Whisper
  -> Generated track loads
  -> Word sync readiness appears if timings exist
  -> Listening structure readiness appears if available
  -> User replays sentence/chunk
  -> User clicks missed word
  -> Diagnosis and vocabulary update
```

体验目标：

- 用户不需要看高级 resource details 才知道生成结果能做什么。
- 完成反馈要说学习能力，而不仅是 job completed。

## 26. 当前端到端旅程：Rich Timeline Resource

状态：Current

```text
Open media
  -> Import/attach .lltimeline.json
  -> Confirm mismatch only if needed
  -> Activate best subtitle/timeline resources
  -> Play with Word sync and Chunk replay
  -> Inspect Listening structure
  -> Expand Phone evidence when useful
  -> Manual review timing if needed
  -> Export updated resource
```

体验目标：

- capability-first。
- advanced details 可用但不是普通用户前置知识。
- degraded states 可见且可行动。

## 27. 规划端到端旅程：听力词典闭环

状态：Planned

```text
用户漏听 "would have"
  -> Diagnosis 判断为 known phrase not recognized
  -> 打开听力词典
  -> 听当前 clip 和多个真实例句
  -> 跨例句做 cloze
  -> 保存两个好例句到 review
  -> 第二天用 audio-first prompt 复习
  -> 在不同 speaker/context 中识别更稳定
```

体验目标：

- 这不是普通 pronunciation dictionary。
- 它是 real-speech recognition and generalization tool。

## 28. 规划端到端旅程：完整学习闭环

状态：Planned

```text
Real input
  -> Comprehension failure
  -> Diagnosis
  -> Practice
  -> Observation / ReviewItem / LearningEvent
  -> Review
  -> Dashboard recommendation
  -> Return to real input
```

体验目标：

- 闭环从真实音频开始，也回到真实音频。
- 练习失败变成 evidence，不变成挫败感，也不静默改全局状态。
- review 复现当时没听出来的真实声音上下文。

## 待确认产品问题

1. Phase 3.x 第一条 polished user-facing slice 应该先做 Practice UI、听力词典、Review queue，还是 Difficulty/Input fit？
2. 听力词典 MVP 是先做本地个人语料，还是同时做 YouGlish 外链/嵌入实验？
3. no-media / missing-resource 时，哪些控制应该隐藏，哪些应该保留但解释原因？
4. plain SRT/VTT 的 Listening structure 最小诚实状态应该是 unavailable、predicted-only，还是 word timing 生成后才可用？
5. 生产资源构建有多少应该变成普通用户流程，多少继续留在 developer/advanced 工具？

## 规划输入来源

- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-CURRENT-FEATURE-INVENTORY.md`
- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-STEP0-UI-AUDIT.md`
- `.planning/phases/2.22-user-facing-workflow-semantics/2.22-FEATURE-SEMANTICS-MODEL.md`
- `.planning/phases/3.0-english-listening-learning-loop/3.0-CONTEXT.md`
- `.planning/phases/3.0-english-listening-learning-loop/3.0-PLAN.md`
- `.planning/phases/3.0.1-learning-loop-architecture-foundation/3.0.1-ARCHITECTURE.md`
- `.planning/codebase/ARCHITECTURE.md`
- `.planning/codebase/DATA-MODEL.md`
