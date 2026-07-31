# `vocabulary_screen.dart` 行为契约（重构前基线）

> 目的：`lib/screens/vocabulary_screen.dart`（1711 行）即将被拆成
> `LexicalRepository` + `VocabularyViewModel` + 纯 View。本文件把**当前**行为
> 逐条钉死，作为那次重构的验收规格：重构后行为不变，才算成功。
>
> 写法要求同 `listen-common-pages-audit.md`：每条**可指认**（`file:line`）。
> 基线：`origin/main` @ `04ad25d`。行号引自该提交的
> `lib/screens/vocabulary_screen.dart`。
>
> 本文件**只描述现状**，不提改造方案。看起来是 bug 的，一律进
> [Suspected defects](#suspected-defects) 一节点名，**不在正文里被悄悄写成
> 「设计如此」**。

---

## 0 · 一句话

这个屏幕同时是 View、ViewModel 和数据层：一个 `StatefulWidget` 里有 22 个可变
字段、36 处 `widget.api.*` 直呼、4 个并发时序、3 种右栏形态、2 种断点布局。

---

## 1 · 状态字段清单

| 字段 | 行 | 含义 |
| --- | --- | --- |
| `capability` | 68/71 | 四通道透镜，默认 `listening` |
| `assessment` | 69/72 | `null` = 全部；非空时才把 capability 带进查询 |
| `search` | 73 | 搜索框文本（**不经 setState** 更新，见 D11） |
| `loading` | 74 | 词表加载中；**没有对应的失败态**（见 D1） |
| `words` | 75 | 词表结果 |
| `details` | 78 | 非空 = 词条详情已打开（master → detail） |
| `gapLoading` / `gapCandidates` / `gapCandidatesError` / `gapProduction` / `gapProductionError` | 85-89 | 差距面板两个独立来源，各自降级 |
| `gapHighlightCandidates` | 94 | coach 跨通道交接时强调候选段 |
| `narrowGapOpen` | 98 | 仅窄屏：差距面板是否顶到前台 |
| `semanticCanSearch` / `semanticMode` / `semanticHits` / `semanticSearching` | 102-105 | 语义检索能力探测与结果 |
| `suggestions` / `suggestionsLoading` | 113-114 | 升级建议（词条装饰之一） |
| `pronunciationAudioUrl` / `pronunciationLoading` | 115-116 | 词典发音（装饰之二） |
| `productionHits` / `productionLoadFailed` | 117-118 | 我的产出语料（装饰之三，**区分"不可用"与"没有"**） |
| `detailRequest` | 123 | 详情请求单调序号，装饰竞态的唯一护栏 |
| `homeResults` / `homeSearching` | 127-128 | 空词表时的语料库回退检索 |
| `slicePlayer` | 131 | 页内第二解码器切片播放 |

---

## 2 · 用户可见状态与 UI 形态

### 2.1 两种外壳

| 形态 | 判据 | 行 |
| --- | --- | --- |
| 双栏（左 340pt 列表 + 右栏） | `constraints.maxWidth >= ListenBreakpoints.vocabularyTwoPane` | 1103-1104, 1206-1222 |
| 窄屏单列（"B" 形） | 否则 | 1224-1229 |

AppBar **永不变形**：标题恒为 `listeningDictionary`，动作恒为「猎词单」+ 工具菜单
（1128-1143）。只有窄屏子表面（详情或差距面板打开时）才长出 `BackButton`
（1113-1127）。双栏永远没有返回键。

### 2.2 右栏三态

| 右栏内容 | 条件 | 行 |
| --- | --- | --- |
| 差距面板（默认） | `details == null` | 1218, 1231-1239 |
| 词条详情 | `details != null` | 1218, 1241-1330 |
| 窄屏：列表 | `details == null && !narrowGapOpen` | 1226-1228 |

窄屏返回是**逐层退栈**：详情 → 差距面板 → 列表。因为 `_closeDetails`（313-316）
只清 `details`，不动 `narrowGapOpen`。

### 2.3 左栏列表区 `_listResults`（1535-1574）

按代码里的判定顺序：

| 状态 | 条件 | 渲染 | 行 |
| --- | --- | --- | --- |
| 语义·加载中 | `semanticMode && semanticSearching` | `ListenLoading` | 1537 |
| 语义·空 | `semanticMode && semanticHits.isEmpty` | `ListenEmptyState` + `semanticSearchNoHits` | 1538-1543 |
| 语义·有结果 | `semanticMode` | 命中列表，相似度保留 3 位小数直出 | 1544-1562 |
| 精确·加载中 | `loading` | `ListenLoading` | 1564 |
| 精确·空且有查询 | `words.isEmpty && search.trim().isNotEmpty` | `_homeCorpusFallback` | 1565-1567 |
| 精确·有结果（或空且无查询） | 其余 | `VocabularyBookView`（自带 `noWords` 空态） | 1568-1573 |

**没有"精确·失败"这一格**——这正是 D1。

### 2.4 语料库回退 `_homeCorpusFallback`（1621-1677）

| 状态 | 条件 | 渲染 |
| --- | --- | --- |
| 未检索 | `homeResults == null` | `noWords` 空态 + 「Search my library」按钮；`homeSearching` 时按钮禁用并显示 `ListenLoading.inline` |
| 检索无果 | `homeResults!.isEmpty` | `dictionaryNoLibraryResults`；`language == 'en'` 时附 YouGlish 外链（889-892） |
| 有结果 | 其余 | `CorpusResultTile` 列表，**只播不收**（`onCollect: null`，1673） |

### 2.5 差距面板（渲染在 `VocabularyGapPanel`）

由 `_loadGapPanel`（367-403）喂四个字段：`gapLoading` 一个开关管两个来源，两个来源
各自有 `ApiFailure?`。面板本身把「两源皆空」折成一句 `gapPaneEmpty`；任一源失败则
就地出一句降级提示 + 可展开诊断，**不会让整个工作台失败**。

窄屏的差距条（1578-1616）在两个来源都还是 `null` 时退回 `vocabGapEntry` 字样，
否则显示 `gapPaneSubtitle` 的实时计数。

### 2.6 语义开关

`semanticCanSearch` 为真才渲染 `FilterChip`（1458-1477）。它来自
`SemanticEmbeddingCapabilityView.canSearch`，即 `status == 'ready' && indexedSourceCount > 0`。
探测失败静默吞掉（417-424），开关就不存在——精确搜索不受影响。

---

## 3 · 36 处 API 调用：触发者 / 成功 / 失败

「失败」一列里 **未捕获** = 代码里没有 `try`，异常以未处理的异步错误逃逸出屏幕。

### 3.1 列表与词条骨架

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 1 | 204 | `listVocabulary` | `initState`(165)、搜索框 `onChanged`（精确模式，1448）、通道 chip（仅当 `assessment != null`，1509）、评估 chip（1708）、关闭语义模式（1473）、`_setOverride` 成功后（727）、`_confirmSuggestion` 成功后（856） | `words = values; loading = false` | **未捕获**（D1）：`loading` 永远为真 |
| 2 | 234 | `lexicalEntryDetails` | `_openEntryById`：列表行、差距面板行、猎词单条目、`initialEntryId`（179）、各写操作成功后重读 | 序号校验后 `details = value`，再并发派发三个装饰 | **未捕获**（D5）：什么都不发生，也不出提示 |
| 37 | 1282 | `learningObservationHistory` | 详情「证据与历史」展开时懒加载（回调传给 `ListeningDictionaryEntryView`） | 由词条视图渲染 | 由词条视图自行处理 |

### 3.2 词条的三个装饰（各自一条时钟，V6）

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 3 | 249 | `upgradeSuggestions` | `_loadEntrySuggestions`，随 #2 成功派发 | `suggestions`、`suggestionsLoading = false` | 捕获 → `const []`，降级成「没有建议」 |
| 4 | 265 | `lookupDictionary` | `_loadEntryPronunciation` | 取第一个非空 `audioUrl`，否则 `null` | 捕获 → `null`（改用合成发音） |
| 5 | 293 | `searchProductionCorpus` | `_loadEntryProduction` | `productionHits`，`productionLoadFailed = false` | 捕获 → `[]` **且** `productionLoadFailed = true`——「不可用」与「你还没写过」严格分开（298） |

注意 #4 用 `widget.language`（267），#5 用 `entry.language`（294）。见 D10。

### 3.3 差距面板

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 7 | 371 | `crossModalReviewGaps` | `_loadGapPanel`，`initState`(168) | `gapCandidates` | 捕获 → `gapCandidatesError = describeApiFailure(error)` |
| 8 | 380 | `semanticProductionGapReview` | 同上 | `gapProduction = enriched.review` | 捕获 → 回退到 #9 |
| 9 | 387 | `productionGapReview` | #8 失败后的回退 | `gapProduction` | 捕获 → `gapProductionError` |

三者共用一个 `gapLoading`，最后统一 `setState`（394-402）：面板要么全等着，要么一起出。

### 3.4 语义检索

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 10 | 419 | `semanticEmbeddingCapability` | `initState`(169) | `semanticCanSearch = capability.canSearch` | 捕获后**完全静默**，开关不出现 |
| 11 | 434 | `semanticSearch` | 输入框 `onSubmitted`（语义模式，1451）、开关打开且查询非空（1469） | `semanticHits` | 捕获 → `const []`（D2） |
| 12 | 455 | `api: widget.api` 交给 `SemanticSearchDialog` | 工具菜单 →「Semantic index」 | 对话框自管六个 semantic-embedding 端点 | 对话框自管（见 `vocabulary_failure_leak_test`） |

### 3.5 能力投影审阅

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 13 | 464 | `auditProjectionEntry` | 详情动作条「Capability proposals」（1370） | 弹对话框；`proposals` 为空时出 `projectionReviewEmpty` 一句话 | 捕获 → SnackBar `projectionReviewUnavailable` + 诊断折叠，**不弹框** |
| 14 | 503 | `decideProjectionProposal(reject)` | 对话框内 ✕ | 关框，重开审阅（512-514） | **未捕获**（D7） |
| 15 | 521 | `decideProjectionProposal(confirm)` | 对话框内 ✓ | 关框，**并发**重开词条 + 重开审阅（529-535） | **未捕获**（D7） |

### 3.6 切片播放与媒体解析

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 16 | 558 | `readMedia`（给 `OccurrenceMediaResolver`） | 播放任一 occurrence | 解析出本地路径 | 解析器返回 `UnresolvedOccurrenceMedia` → `slicePlayer.showError`（574-577） |
| 17 | 559 | `fingerprintFile` | 同上（用户手选文件时） | 同上 | 同上 |
| 18 | 561 | `registerMedia` | 同上 | 同上 | 同上 |
| 19 | 600 | `readMedia` | `_playCorpus`（播放语料库命中） | 拼出 occurrence map 后走 #16 链路 | 捕获 → `slicePlayer.showError(dictionaryClipNeedsSource)` |
| 6 | 322 | `semanticAttempt` | 点开「我的产出」某条（仅当 `attemptId != null`） | 弹框列出全部修订 | **未捕获**（D8） |

### 3.7 语料库

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 20 | 622 | `searchCorpus` | 详情「Search my library」（`onSearchLibrary`，1268） | 结果交给词条视图去重后渲染 | 此处**未捕获**，由词条视图的调用点处理 |
| 21 | 635 | `readMedia` | `_collectCorpus` | 拿到 title/fingerprint 快照 | 与 #22 同一个 `try` |
| 22 | 636 | `upsertLexicalEntry` | `_collectCorpus`（把语料命中收成耐久切片） | 重读词条（658）+ SnackBar `dictionaryCollected`，返回 `true` | 捕获 → SnackBar `dictionaryCollectFailed` + 诊断，返回 `false` |
| 23 | 678 | `searchCorpus` | 空词表回退里的「Search my library」（1630） | `homeResults = values` | 捕获 → `const []`（D3） |
| 24 | 697 | `reindexCorpus` | 工具菜单 →「Rebuild library index」 | SnackBar `dictionaryReindexDone`，`{count}` 替换成轨道数 | 捕获 → SnackBar `dictionaryReindexFailed` + 诊断 |

### 3.8 词条写操作（全部共用同一句失败文案 `dictionaryUpdateFailed`）

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 25 | 720 | `setCapabilityOverride` | 详情四通道分段控件 | 重读词条（725）+ **重跑词表**（727） | 捕获 → SnackBar + 诊断；**不重读**，面板保持原样 |
| 26 | 745 | `updateLexicalLearningContent` | 详情「我的释义与笔记」保存 | 重读词条 + SnackBar `dictionaryContentSaved` | 同上 |
| 27 | 770 | `createLexicalSenseFolder` | 详情「义项文件夹」新建 | `_saveSenseFolderChange`：直接 `details = value`，**不重读** | 同上 |
| 28 | 788 | `updateLexicalSenseFolder` | 编辑 | 同上 | 同上 |
| 29 | 801 | `deleteLexicalSenseFolder` | 删除 | 同上 | 同上 |
| 30 | 810 | `assignLexicalSenseFolderOccurrence` | 归入义项 | 同上 | 同上 |
| 31 | 823 | `unassignLexicalSenseFolderOccurrence` | 移出义项 | 同上 | 同上 |
| 32 | 854 | `confirmUpgradeSuggestion` | 建议横幅「确认」 | 重读词条 + **重跑词表**（856） | 同上 |
| 33 | 873 | `rejectUpgradeSuggestion` | 建议横幅「否决」 | 只重读词条，**不重跑词表**（见 D9） | 同上 |

### 3.9 复习与观察

| # | 行 | 调用 | 触发者 | 成功 | 失败 |
| --- | --- | --- | --- | --- | --- |
| 34 | 906 | `createReviewItem` | 单条切片「Add this clip to review」（1312） | SnackBar `dictionaryReviewQueued` | 捕获 → `dictionaryReviewFailed` + 诊断 |
| 35 | 951 | `createReviewItem` | 详情动作条「Add to review」（1349） | 同上 | 同上 |
| 36 | 1038 | `createLexicalObservation` | 切片上标记「听出来了 / 没听出来」 | SnackBar `dictionaryMarkedHeard` / `dictionaryMarkedNotHeard`，返回 `true` | 捕获 → `dictionaryMarkFailed` + 诊断，返回 `false` |

`_markOccurrence` 在 `occurrence.sentenceId == null` 时**静默返回 `false`**，一次
请求都不发（1035-1036）。

### 3.10 不经 `widget.api` 但同属本屏的 I/O

- `hunting.load(widget.api)`：`initState` 的 post-frame 回调（174-176，避开首帧同步
  通知共享 controller）、打开猎词单（974）、面板刷新（985）。
- `hunting.addManual / promoteCandidate / archive`：猎词单动作。`_addToHuntingList`
  在词条已在单中时**先行短路**并出 `huntingAlreadyAdded`（1015-1018）；动作条上的按钮
  在 `busy || inHunting` 时本就禁用（1360）。
- `widget.auxiliaryAudio.speak(widget.api, …)`：合成发音（149-160），失败出
  `ttsUnavailable`。
- `widget.auxiliaryAudio.playRemote(url)`：词典发音（139-147），失败出
  `pronunciationUnavailable`。
- `Process.run('open', [url])`：外链（896），只发链接不抓内容（版权护栏）。

---

## 4 · 异步竞态护栏

### 4.1 唯一的护栏：`detailRequest`

```
detailRequest        123   单调序号
++detailRequest      223   每次 _openEntryById 自增
request != detailRequest
                     235   词条本体回来时校验
_detailStillCurrent  244   mounted && request == detailRequest
  ├─ 255  suggestions
  ├─ 282  pronunciation
  └─ 302  production
```

它挡住两件事：

1. **235**：用户先点 A 再点 B，A 的 `lexicalEntryDetails` 后到——丢弃，否则右栏会
   在 B 已经打开后被 A 覆盖。
2. **255 / 282 / 302**：A 的某个装饰后到——丢弃，否则会把 A 的建议/发音/产出画到
   B 的身份卡上。这是 S4(#82/V6) 把三个装饰改成并发之后必须配的锁。

`mounted` 同时挡住 dispose 之后的 `setState`。

### 4.2 明确**没有**护栏的地方

| 路径 | 行 | 后果 |
| --- | --- | --- |
| `_load` | 202-216 | 两次搜索并发时后到者胜，旧查询能覆盖新列表（**D4**） |
| `_runSemanticSearch` | 426-448 | 同理，两次提交乱序落地 |
| `_searchHomeCorpus` | 674-692 | 同理 |
| `_loadGapPanel` | 367-403 | 今天只在 `initState` 调一次，暂不可达；重构后若加刷新按钮会立刻变成真问题 |
| `_closeDetails` / `_landOnGapPane` | 313-316 / 408-415 | 不自增 `detailRequest`，已关闭词条的在途装饰仍会 `setState`（D12，今天无害） |

---

## 5 · 覆盖矩阵

`✅` = 已被现有测试钉住；`🆕` = 本次新增；`⬜` = 仍未覆盖。

### 5.1 已有测试覆盖的

| 行为 | 测试 |
| --- | --- |
| ✅ 双栏默认右栏是差距面板 | `vocabulary_workbench_test` |
| ✅ 打开词条时列表与 AppBar 不变形 | 同上 |
| ✅ 八个筛选 chip 全在 340pt 列内换行不被裁 | 同上 |
| ✅ 通道 chip 在「全部」下不重查 | 同上 |
| ✅ 详情动作条左槽承载来源而非重复词头 / 无切片时说 `vocabDetailSourceUnknown` | 同上 |
| ✅ 窄屏降级为单列 + 差距条 + 返回键 | 同上 |
| ✅ `openCrossModalReviewOnStart` 落在差距面板而非对话框 | 同上 |
| ✅ 首帧不同步通知共享 `HuntingController` | `vocabulary_screen_first_frame_test` |
| ✅ 差距面板两源皆 500 时逐源具名、不泄漏传输细节 | `vocabulary_failure_leak_test` |
| ✅ 能力建议查询失败 → SnackBar 具名、不泄漏 | 同上 |
| ✅ 慢装饰不拖住身份卡；单个装饰各自落地 | `vocabulary_entry_detail_test` |
| ✅ 词条视图五锚点、章节状态、义项、证据历史、产出区「不可用 ≠ 没有」 | `vocabulary_book_test` / `vocabulary_entry_detail_test` |

### 5.2 本次新增（`test/vocabulary_screen_characterization_test.dart`，33 条）

| 行为 | 备注 |
| --- | --- |
| 🆕 词表 500 → 永远转圈 + 错误逃逸 | 钉 D1 |
| 🆕 词条 500 → 点了等于没点，也不出提示 | 钉 D5 |
| 🆕 语义检索失败被说成「没有匹配」 | 钉 D2 |
| 🆕 语料检索失败被说成「库里没有」 | 钉 D3 |
| 🆕 重建索引失败具名 + 诊断一击可达；不泄漏 envelope 字段 | |
| 🆕 非 envelope 的失败体没有可展开诊断 | 钉「诚实的地板」 |
| 🆕 重建索引成功报轨道数、成功条没有诊断动作 | |
| 🆕 工具菜单最长条目被自身宽度裁掉 | 钉 D6 |
| 🆕 能力探测失败 / 索引为空 → 语义开关不出现 | |
| 🆕 语义增强失败时差距面板回退到普通产出审阅且不报错 | |
| 🆕 两次产出请求都失败才具名，且不牵连另一个来源 | |
| 🆕 词典失败 → 身份卡照出，落到合成发音 | |
| 🆕 通道判定失败：具名 + 不重读 + 四通道仍未评估 | |
| 🆕 通道判定成功：重读词条**且**重跑词表 | |
| 🆕 加入复习成功/失败两句话严格不同 | |
| 🆕 已在猎词单的词按钮禁用、tooltip 即理由、零请求 | |
| 🆕 能力建议为空时出空态句而非空对话框 | |
| 🆕 上一个词条的装饰不会画到后打开的词条上 | 钉 `detailRequest` 护栏 |
| 🆕 旧词表响应会覆盖新词表响应 | 钉 D4 |
| 🆕 切换词条时旧身份卡留在屏上、装饰回到等待态 | |
| 🆕 双栏：从差距面板开词条 → 右栏换成详情、列表还在、无返回键 | |
| 🆕 双栏：`Gaps` 行的选中态严格等价于「没开词条」 | |
| 🆕 窄屏：从差距面板开的词条，返回退回差距面板而非列表 | |
| 🆕 窄屏差距条在两源到齐后报计数 | |
| 🆕 空查询开语义模式：不发请求、出空态、hint 换词 | |
| 🆕 语义命中替换词表；关掉开关重跑精确查询 | |
| 🆕 语义模式下打字两个索引都不查，回车才查 | |
| 🆕 差距面板两源皆空 → 一句话空态（不是两条并列提示） | |
| 🆕 左栏可用而右栏还在等差距源 | |
| 🆕 选评估后查询同时带 capability + assessment；回「全部」两者都撤 | |
| 🆕 `initialEntryId` 直接进详情 | |

### 5.3 仍未覆盖（重构时需人工盯）

| 行为 | 为什么先不覆盖 |
| --- | --- |
| ⬜ 切片播放全链路（#16-#19、`OccurrenceMediaResolver`、`SlicePlayerController`） | 需要真实媒体与 `file_selector`，属集成层；`slice_player` 已有独立测试 |
| ⬜ `_startShadowingOccurrence`（586-593）会 `Navigator.pop` 整个路由 | 需要一个宿主路由与 `onStartShadowing` 桩，行为语义存疑（见 D13） |
| ⬜ `_collectCorpus` 成功/失败（#21/#22） | 需要词条视图的语料检索面板走到「保存」；词条视图侧已有 `onCollectCorpus` 回调测试 |
| ⬜ `_openProductionAttempt` 弹框内容（#6） | 依赖 `semanticAttempt` 的完整 wire，价值低于 D8 本身 |
| ⬜ `decideProjectionProposal` 成功/失败（#14/#15） | 对话框内嵌套异步 + 递归重开，成本高；D7 已在文档里点名 |
| ⬜ 猎词单底部弹层的三个动作（promote / archive / openEntry） | 属 `HuntingController` + `HuntingListPanel` 的契约，不是本屏的 |
| ⬜ `_markOccurrence`（#36）成功/失败 | 需要带 `sentenceId` 的 occurrence 与词条视图内的标记控件；词条视图侧已覆盖 `onMark` 布线 |
| ⬜ 导入/导出（`onImport` / `onExport`） | 是外部注入的回调，本屏只转发 |
| ⬜ 语义检索与语料回退的乱序竞态 | 与 D4 同因，钉一处即可说明问题；重构时一并修 |

---

## Suspected defects

以下都是**当前行为**，本次只钉不改。编号在测试注释里被引用。

### D1 · 词表没有失败态（`202-216`）

`_load()` 没有 `try`。`/v1/vocabulary` 一旦 500：

- 异常以未处理的异步错误逃逸（`unawaited(_load())`，165/727/856/1448/1473/1509/1708）；
- `loading` 永远停在 `true`，左栏永远转圈；
- 用户看不到任何句子，也没有重试入口。

违反 AGENT.md「UI must distinguish loading, empty, unavailable, degraded,
failed, cancelled, and completed states honestly」。屏幕里其它来源（差距面板、产出
语料）都做到了，唯独主查询没有。

### D2 · 语义检索失败被伪装成「没有匹配」（`426-448`）

`catch (_) { hits = const []; }`，渲染成 `semanticSearchNoHits`。「索引挂了」和
「索引里确实没有近邻」变成同一句话。

### D3 · 语料检索失败被伪装成「库里没有」（`674-692`）

同型。而同一个文件的 `_loadEntryProduction`（289-307）恰恰专门用
`productionLoadFailed` 把这两件事分开，并在注释里写明理由——所以这是**不一致**，
不是深思熟虑的取舍。

### D4 · 词表没有序号护栏（`202-216` vs `223/235/244`）

详情路径有 `detailRequest`，列表路径什么都没有。搜索框 `onChanged` 每个按键都发一次
请求（1445-1449，也没有防抖），并发响应按到达顺序落地：慢的旧查询能把快的新查询覆盖
掉，列表于是显示用户已经改掉的那个查询的结果。已由
「a stale vocabulary list response overwrites the fresher one」钉住。

### D5 · 词条打开失败是完全静默的（`234`）

`lexicalEntryDetails` 未捕获。点一个词 → 右栏纹丝不动、没有 SnackBar、没有任何解释，
异常逃逸到 zone。屏幕上所有其它写操作都出了 `dictionaryUpdateFailed`，唯独"打开"
这个最高频的读操作没有。

### D6 · 工具菜单裁掉自己最长的标签（`1197-1204`）

`_toolsItem` 是无约束 `Row`，而 `PopupMenuItem` 的最大宽度由 Material 固定在
280pt（内容区 256pt）。`importAssets`（"Import vocabulary assets"）加图标加间距溢出
约 112pt，标签被截断——与窗口大小无关，任何尺寸都复现。已由
「the tools menu clips its own longest label」钉住。

### D7 · 能力建议的确认/否决没有失败路径（`503`、`521`）

`decideProjectionProposal` 未捕获。点了 ✓ / ✕ 若后端拒绝：对话框停在原地，没有提示，
异常逃逸。同一个方法的**读**路径（464）反而是有 SnackBar 的。

另外 `confirm` 分支并发派发 `_openEntryById` + `_openProjectionReview`（529-535），
两者都不等待；快速连点可以叠出多层对话框。

### D8 · 打开产出尝试没有失败路径（`322`）

`semanticAttempt` 未捕获。点「我的产出」里某一条、其 attempt 读不出来时：不弹框、
不出声。注意 `attemptId == null` 时是**有**降级的（339-341 直接显示快照文本），
所以缺的只是失败分支。

### D9 · 确认与否决建议的刷新范围不对称（`848-883`）

`_confirmSuggestion` 成功后重跑 `_load()`（856），`_rejectSuggestion` 不跑（873-875）。
若当前评估筛选正好把该词圈进/圈出，否决之后列表与词条会短暂不一致。

### D10 · 发音查询用的是界面学习语言，不是词条语言（`267` vs `294`）

`_loadEntryPronunciation` 传 `language: widget.language`；同一批装饰里的
`_loadEntryProduction` 传 `language: entry.language`。跨语言词条（差距面板/猎词单
可以把任意词条送进来）会用错的语言查词典。

### D11 · 搜索框绕过 `setState`（`1445-1449`）

`onChanged` 直接改 `search` 与 `homeResults` 两个字段。今天没有可见后果，因为精确
模式紧接着 `_load()` 会自己 `setState`；但语义模式下**不调用** `_load()`，字段与已
渲染的树从此不同步，直到别的原因触发重建。属于潜伏项，重构成 ViewModel 时会自然
消失——也正因如此，重构后若行为有变，要先确认变的是这条。

### D12 · 关闭详情不推进 `detailRequest`（`313-316`、`408-415`）

在途装饰仍会对已关闭的词条 `setState`。今天无害（下次打开会重置这些槽），但它意味着
护栏的语义是「哪个词条最新」而不是「详情是否还开着」，重构时不要顺手"修正"成后者，
否则 D12 会变成行为改变。

### D13 · 影子跟读会弹掉整个路由（`586-593`）

`_startShadowingOccurrence` 在调用 `onStartShadowing` 前执行
`Navigator.of(context).pop()`。详情是**页内**表面而不是路由，所以这里弹掉的是整个
`VocabularyScreen` 路由。可能是有意的交接，但读起来像是想关一个对话框——列为存疑。

---

## 6 · 重构验收清单

1. `flutter analyze --fatal-infos --fatal-warnings` 与 `flutter test` 全绿。
2. `test/vocabulary_screen_characterization_test.dart` 33 条**一条不改**地通过。
   任何一条要改，都必须先在 PR 里说明「这是有意的行为变更」，并对照本文件相应条目。
3. 若重构顺手修掉了某个 `D*`，把对应测试改名成新行为、并在本文件里把该条目移出
   Suspected defects——不要留一条已经不成立的"存疑"。
4. 5.3 里未覆盖的行为，重构后需要人工走一遍（尤其切片播放与猎词单弹层）。
