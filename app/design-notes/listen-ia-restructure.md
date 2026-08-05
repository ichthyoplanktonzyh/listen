# listen IA 重构 · 七个房间压成四个

> owner 拍板 2026-08-05。本文件是这次重构的验收依据，落地后它描述的是**现状**，
> 不是计划——实现与本文冲突时，按 AGENT.md「事实 > 文档」，改文档。
>
> 上游输入：`/Users/shadow/Desktop/listen-user-journey.md`（用户旅程 + 每日英语听力调研）。
> 上位约束：[`listen-design-charter.md`](./listen-design-charter.md) 五条原则。

## 一、为什么改：三个能在代码里指出来的毛病

### 1. 「今日」和「我的资源」在回答同一个问题

`app_sidebar.dart` 的内容组里，`sidebarToday`（→ `DiscoveryHome`）和
`sidebarMyResources`（→ `ListeningHome`）并列。两个入口，一个问题：接下来听什么。
用户第一次点进来必须自己试出「今日 = 在线频道，我的资源 = 本地库」——这不是分类，
是实现细节泄漏到导航层。

### 2. 「历史记录」不是一个目的地，是一个排序

`HistoryPane` 的全部逻辑是：

```dart
final history = [...?entries]
  ..sort((a, b) => b.media.updatedAtMs.compareTo(a.media.updatedAtMs));
```

`entries` 就是 `ListeningHome` 拿到的同一份 `mediaLibraryActions.mediaLibrary`。
一份数据、两个房间、只差一个 `sort`。这跟当初「离线下载」从侧栏降级成
`ListeningHome` 里一个 `FilterChip` 是同一类问题（那次的判断写在
`listening_home.dart` 的注释里，是对的），只是漏了这一个。

### 3. 七个目的地按系统的对象模型分，不按用户意图分

内容 / 学习 / 洞察 三组、七个目的地，对应的是数据模型：媒体、词、句型、卡片、画像。
但用户脑子里「我的生词本」和「表达」是同一件事的两半——**我攒下来的语言**；
「复习」是它的动作，不是它的邻居。数据闭环（听 → 查词 → 练习 → 写证据 → 复习 → 画像）
在代码里是闭合的，在导航里被摊成了七个互不相干的平行房间，用户得自己在脑子里把环接回去。

## 二、为什么不抄每日英语听力的 IA

调研文档建议参考每日英语听力重构。**它的动线值得抄，它的 IA 不能抄。**

它的顶层是内容货架（推荐 / 名师播客 / 精品课 / 配音秀 / 精听党），能当骨架是因为
**它拥有内容**——它是内容提供方，货架上永远有货。listen 不拥有任何内容，用户自己的
内容才是内容。把这套 IA 搬过来，顶层板块开箱全是空的，第一屏就在撒谎，
直接撞 AGENT.md「诚实」那条不可推翻的硬约束。

打卡 / 连胜 / 徽章那一层撞宪章原则 3「在场，但不催促」。同样不抄。

**抄的是三条动线原则**（与 IA 结构无关，可独立落地）：

| 原则 | listen 现状 | 本次是否处理 |
| --- | --- | --- |
| 学习动作挂在播放器上，不跳页 | `MediaWorkbench` 已是这个形状 | 不动 |
| 查词即入库，零第二步 | 已是 | 不动 |
| 难度前置（选之前就知道合不合适） | content fit 卡是**进去之后**才给 | **不在本次范围**，另开 |

本次只做 IA 骨架。难度前置需要动 content fit 的取数时机，是另一件事。

## 三、目标 IA

```
今天      ← 新增。唯一开场：我现在该做什么
听        ← discovery + resources + history 合并
我的语言  ← vocabulary + expression + review 合并
教练      ← 不动
────────
开始对话  ← 启动动作，不占选中态（不动）
```

`AppRoute` 从 7 个值降到 4 个：`today` / `listen` / `language` / `coach`。

侧栏不再分组。四个目的地不需要小标题来解释自己——三组标题
（内容 / 学习 / 洞察）本身就是「七个太多了」的症状。

### 3.1 今天 · `AppRoute.today`

**它回答且只回答一个问题：我现在该做什么。**

宪章原则 3 允许「在场」，禁止的是催促。判定标准：用户来了才看到，不推送、不弹窗、
不连胜、不愧疚、没有红点数字焦虑。所以这一页是**几行静态的陈述**，不是任务清单——
其中只有真有去处的才是门：

| 行 | 数据来源 | 去向 |
| --- | --- | --- |
| 继续听 | `settingsController.lastMedia*` | 展开工作台 / 继续上次媒体 |
| 待复习 | `ReviewRepository.deckOverview().dueTotal` | 我的语言 · 复习 |
| 生词本 | `mediaLibraryActions.savedVocabulary` | 我的语言 · 词汇 |
| 卡壳收件箱 | `extensiveListeningController.activeItemCount` | **不是门**（见下） |
| 本地核心 | `playerController.status` | **不是门**（健康状态行） |

**只有真的有地方可去的行才是门。** 收件箱在实现上是工作台听力面板里的一个 tab
（`side_panel.dart`），没有独立目的地；给它一个门只能打开工作台，那就成了「继续听」
的第二份拷贝——正是本次要消灭的那类重复。所以它只陈述数量，不带 chevron。
本地核心同理：它是一行健康状态，解释「为什么其余几行可能显示未知」，本身不通往任何页面。

「最近媒体的字幕条数」骑在继续听卡片上（它描述的是那条媒体），不单独占一行。

**诚实分层是这一页的硬要求**，四种状态必须可区分，不得互相冒充：

- **未知**：core 未连接 / 还没读过 → 门是灰的，写「未连接」或什么都不写，
  **不写 0**。`ReviewDeckState.overview` 的注释已经把这条规矩写清楚了
  （「0 due」和「not loaded yet」是两个不同的事实），今天页继承它。
- **加载中**：走 `ListenLoading`，不许拿 0 顶着。
- **零**：确实读到了、确实是 0 → 写 0，且门仍可点（进去看得到「今天没有到期的卡」）。
- **失败**：写失败原因 + 可重试，不降级成 0。

新增 shell 级 `ReviewDueController`（`lib/controllers/review_due_controller.dart`）：
只调 `deckOverview()` 取 `dueTotal`，不持有会话、不持有 deck 页状态。它必须与
`ReviewRouteHost` 里那个路由级 `ReviewDeckController` 分开——后者随进出复习页
构建/销毁，今天页不能依赖它存在。

取数时机：**进入今天页时读一次**（`currentRoute` 监听器），core 连上时若正在今天页
再读一次，core 断开时 `reset()` 回未知。不轮询——轮询就是宪章禁止的那种「催促式在场」。

### 3.2 听 · `AppRoute.listen`

一个页面，顶部两段：**发现**（在线频道 / URL 导入）| **我的媒体**（本地库）。

分段是「货从哪来」，不是两个功能——两边的终点是同一个媒体库（用户旅程文档
J1 那张图：三个入口，终点统一）。分段状态是页面内部状态，不进 `AppRoute`：
它不值得一个可被外部跳转的地址。

**历史记录并入「我的媒体」**：`HistoryPane` 删除，它的排序变成「我的媒体」上的
一个排序选项（最近学过 ↔ 按队列分组），与已有的「仅离线」`FilterChip` 并列。
`sidebarHistory` 这个 key 留着当排序项标签。

### 3.3 我的语言 · `AppRoute.language`

一个页面，顶部三段：**词汇** | **表达** | **复习**。

这三段共享一个身份——「我攒下来的语言 + 对它的练习」。三个 `RouteHost`
（`VocabularyRouteHost` / `ExpressionRouteHost` / `ReviewRouteHost`）**原样保留**：
它们的控制器生命周期契约（进入构建、离开销毁、core 断开时渲染诚实的不可用面板）
是对的，本次不动它们的内部。变的只是谁把它们摆出来。

**代价与取舍**：三段各自持有路由级控制器。切分段 = 换 host = 上一段的控制器被销毁。
这是可接受的——三者本来就是独立的读取面，没有跨段的未提交状态。唯一要保的是
**复习会话**：会话是 push 在 host 之上的 `ReviewQueueScreen`，切分段时它不在栈上，
不受影响。

分段状态同样是页面内部状态，但它需要**可被外部指定**——教练页的建议要能直接落到
「复习」那一段。所以 `SegmentedPane` 是**受控**的：shell 持有
`ValueNotifier<LanguageSegment>` / `ValueNotifier<ListenSegment>`，pane 只上报点击。
自己持有选中态的 pane 只能从第一段进，教练的门就又变回「指向一个页面然后祈祷」。
所有想进这个目的地的调用方都走 `_openLanguage(segment)` / `_openListen(segment)`，
所以它不可能被打开在错的段上。

### 3.4 教练 · `AppRoute.coach`

页面不动。只改 `onNavigate` 的落点映射：

| `CoachSuggestionDestination.kind` | 旧落点 | 新落点 |
| --- | --- | --- |
| `review_queue` | `AppRoute.review` | `language` + 复习段 |
| `hunting_list` | `AppRoute.vocabulary` | `language` + 词汇段 |
| `cross_modal_review` | `_showVocabulary(...)` | 不变（它是 push，不是路由） |
| `personal_expression` | `AppRoute.expression` | `language` + 表达段 |
| `content_home` | `AppRoute.resources` | `listen` + 我的媒体段 |

### 3.5 顶栏 · 删除

侧栏压到四个之后，顶栏（`PlayerAppBar`）暴露成**第四套导航**。同一批动作有四份拷贝：

| 动作 | 顶栏 | macOS 原生菜单栏 | 侧栏 | 页面本身 |
| --- | --- | --- | --- | --- |
| 打开媒体 / 打开网址 | 「内容」菜单 | File | — | 听页两张主卡 + 播放栏按钮 |
| 词汇 / 复习 | 「学习」菜单 | Learning | 我的语言 | — |
| 设置 | 右侧齿轮 | Preferences | 侧栏底部 | — |
| wordmark | 标题位 | — | 侧栏顶部（下方 40px） | — |

加上一条独立的毛病：「字幕」菜单每一项都是 `mediaGatedItem`，没有媒体时整个菜单是
一排带理由的禁用项——诚实，但无用。而有媒体时它又和工作台的 `_SessionHeader`
叠成两层标题栏。

`macos_menu_bar.dart` 已经带了 File / Learning / Playback / Preferences，
且本仓库只有 macOS 一个发布目标。所以顶栏承担的东西，要么原生菜单栏已经有，
要么侧栏已经有，要么页面上就摆着。**删掉整条顶栏**，它独有的两件东西各自回家：

- **字幕的导入 / 生成 / 搜索**（生成与搜索确实是顶栏独有）+ 归档 →
  `SessionSubtitleMenu`，挂进工作台 `_SessionHeader` 的末端。
  那个 header 只在有媒体时存在，**门禁从条件变成结构**：这里不可能有死项。
- **工具中心 + 诊断 / 数据**（字幕资源、学习资产、资源、转写中心、音素分析中心、
  导出日志、词表导入导出）→ `ShellToolsMenu`，收进侧栏底部，挨着设置。
  它们是「你要做的事」，不是「你能待的地方」，所以不进目的地列表、不占选中态。

`ShellFadeAppBar` 随之删除（`ShellRecede` 仍然用 `ShellFade` 淡出播放栏与沉浸态控件）。
`ListenBreakpoints.appBarLabels` 保留——它是按最宽语言量出来的阈值，
现在由个人表达页的头部在用，只是注释要说清它已经不属于顶栏。

## 四、落地顺序

1. `AppRoute` 收敛到四个值 + 侧栏去分组；
2. `ListenPane`：`DiscoveryHome` / `ListeningHome` 两段；`HistoryPane` 降级为排序并删除；
3. `LanguagePane`：三个既有 host 三段；
4. `ReviewDueController` + `TodayPane`，含四种诚实状态；
5. 教练落点映射；
6. 删顶栏，字幕菜单进工作台 header，工具菜单进侧栏底部；
7. `en` / `zh` 两侧补齐所有新 key（AGENT.md 语言分离）；
8. 测试。

## 五、由测试执行的规则

规则由测试守着，不由本文守着（AGENT.md）。本次要落的：

- `app_sidebar_test.dart`：`AppRoute.values` 长度 7 → 4；「恰好一个目的地被选中」
  和「启动动作不占选中态」两条保持；三个分组标题不再存在。
- 新 `today_pane_test.dart`：**四种状态互不冒充**——未知写 `—` 并说明原因、
  加载中走统一等待语言、真 0 写 0 且仍可点、失败写原因且给重试。断言按行取数
  （`_countFor`），不是「页面上有没有 0」——有些行的 0 是真的。这是本次最主要的
  诚实闸门，也是最容易在后续迭代里被一个 `?? 0` 悄悄推平的一条。另外钉住：
  门只出现在真有去处的行（chevron 计数）。
- 新 `controllers/review_due_controller_test.dart`：首读前未知、失败不降级成 0、
  `reset()` 清掉上一轮的数、迟到的请求不能覆盖新的。
- 新 `pane_segments_test.dart`：分段是**受控**的——外部指定的段生效（教练落点不会
  打开错的段）、只构建选中段、点击只上报不自选。
- `listening_home_test.dart`：新增「最近学过是排序不是房间」——同样的行、换个顺序、
  一条都没被过滤掉。
- 新 `shell_chrome_menus_test.dart`（取代 `player_app_bar_test.dart`）：工具菜单
  **不得再出现任何已有归属的条目**（vocabulary / review / open-media / open-online /
  settings 一律不许在列表里）；字幕菜单**没有任何一项是禁用的**——门禁已经是结构性的；
  两个菜单在 zh 下不得漏出硬编码英文。
- `window_min_size_test.dart`：顶栏没了，最小宽度要守的变成「侧栏 + 一个还值得渲染的
  内容区」，`AppSidebar.railWidth` 因此从字面量提成常量。
- 既有 discipline 测试（间距 / 圆角 / 字号 / 等待语言 / CJK 字面量 / 分层依赖）
  全绿，不为这次重构放宽任何一条。

## 六、明确不在本次范围

- **难度前置**（content fit 提到选择之前）——另开。
- **零等待内容**（新用户首分钟的下载 + 生成硬伤）——产品边界问题，
  `media-content-acquisition-preparation.md` 已声明本阶段不实现。
- **轻量复习形态**（碎片时间的词卡 + 原声切片）——功能，不是 IA。
- **移动端**——设计文档现列为非目标。本次四目的地结构对移动端底部 Tab 是可迁移的
  （四个正好），但不为它做任何提前妥协。
