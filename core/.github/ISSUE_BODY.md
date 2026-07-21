## 概述

经过对 Flutter 前端代码的全面审查，发现以下 10 个 UI/UX 及架构问题，按优先级排序。

---

## 🔴 优先级高

### 1. `_PlayerScreenState` 膨胀（2500+ 行）

**位置**：`apps/desktop/lib/main.dart`

**问题**：`_PlayerScreenState` 是应用的唯一 Composition Root，管理 30+ 控制器/协调器实例、10+ 个 `late final` Coordinator 的绑定逻辑、数十个 UI 状态标志位、以及所有页面切换逻辑。全部集中在 2500+ 行的一个 State 中。

**影响**：
- 任何修改都需要理解 2500 行代码的影响面
- 大量 `setState(() {})` 散布在各处回调中，触发整棵树重建
- Coordinator 绑定逻辑全部堆积在 `initState()`（100+ 行），难以维护

**建议**：按功能域拆分——将阅读模式、写作模式、口语模式等独立子树的逻辑提取为单独的 State/Hook widget。

### 2. 状态管理双轨制

**位置**：`apps/desktop/lib/state/store.dart` + `apps/desktop/lib/main.dart#L1862-L1876`

**问题**：项目同时存在两种状态管理模式：
- `Store<T>` + `StoreBuilder`：支持字段级细粒度选择，只重建变化部分
- `ChangeNotifier` + `Listenable.merge`：合并 14 个监听器，**任何变化都触发整棵树的 builder 回调**

后者（`Listenable.merge`）实际上抵消了 Store 细粒度更新的全部优势。例如 `huntingSessionController` 的一次状态变化会触发 `PlayerStage`、`SidePanel`、`PlaybackBar` 等所有 widget 重建。

**建议**：统一到 Store 模式，或将 `Listenable.merge` 拆散为多个 `ListenableBuilder` 包裹各自关心的子树。

---

## 🟡 优先级中

### 3. 仅支持浅色主题

**位置**：`apps/desktop/lib/theme/listen_theme.dart`

**问题**：`ListenTheme.light()` 是唯一的主题实现，没有暗色/深色模式。

对于语言学习类桌面应用，用户常在暗光环境下看视频学习，亮色 UI 会造成视觉疲劳。亮色 UI 边缘与暗色视频背景的对比度过高，影响沉浸式学习体验。

**建议**：实现 `ListenTheme.dark()`，并根据系统偏好自动切换。

### 4. AppBar 菜单过载

**位置**：`apps/desktop/lib/widgets/app_bar/player_app_bar.dart`

**问题**：AppBar 承载了 20+ 个菜单项——打开媒体（2 种）、导入字幕（3 种）、生成字幕（2 种）、搜索字幕、转写中心、音素分析中心、学习资产/资源、词汇本/复习/教练面板、短语候选/纠正词元/导出日志、导入导出词汇、归档媒体、设置等。

在水平空间有限的 AppBar 中，这些功能大概率被塞进多个下拉菜单，导致关键操作难以被用户发现。

**建议**：重新梳理信息架构——常用操作（打开媒体、设置）保持在可见区域，其余功能归入更清晰的层级菜单或侧面板入口。

### 5. Widget 测试覆盖不足

**位置**：`apps/desktop/test/`

**问题**：控制器/逻辑测试有 ~45 个，契约测试 ~14 个，但 Widget 测试只有 ~20 个。对于 23+ 个面板组件、7 个流程、5 个侧面板选项卡的应用来说，覆盖率偏低。核心交互路径（单词选择→面板切换→诊断显示→练习启动）缺少端到端的 Widget 测试。

### 6. 导航策略不一致

**位置**：`apps/desktop/lib/main.dart` + `apps/desktop/lib/widgets/flows/`

**问题**：大部分页面通过 `Stack` 条件渲染 + `SlideTransition` 切换（首页/工作台），但部分全屏页面（`VocabularyScreen`、`ReviewQueueScreen` 等）使用 `Navigator.push`。这种混用导致：
- 返回键行为不一致
- 状态/数据传递方式不同（push 通过 `Future` 返回，条件渲染通过回调）
- Stack 中大量不可见 widget 仍可能消耗资源

---

## 🟢 优先级低

### 7. 可访问性（Accessibility）缺失

**位置**：全局

**问题**：整个代码库中唯一使用了 `Semantics` 的是 `_WorkbenchSplitter`（`"Resize media and transcript"`）。其他所有交互组件（按钮、选项卡、滑块、字幕 token）都没有语义标签。影响自动化测试准确性和键盘导航流畅性。

### 8. 部分字符串硬编码未本地化

**位置**：`apps/desktop/lib/main.dart` 中多处

**问题**：状态字符串如 `'Starting local core...'`、`'Local core connected'`、`'Core unavailable: $error'`、`'Review source media is unavailable for shadowing'`、`'Could not save personal expression history: $error'` 等硬编码，未通过 `AppLocalizations` 处理。

### 9. 模型层过于集中

**位置**：`apps/desktop/lib/models/timeline.dart` + 5 个 part 文件，`apps/desktop/lib/models/types.dart` + 5 个 part 文件

**问题**：虽然 part 文件按逻辑拆分，但所有模型仍然在同一个库作用域中。随功能增长会给编译时间和命名空间带来压力。两块模型文件各自覆盖 5 个不同子领域，但都在各自的单一 `part of` 作用域内。

### 10. 响应式断点分散

**位置**：多文件

**问题**：响应式断点值（760、820、520、720）散布在多个文件中，没有集中管理。嵌套的 `LayoutBuilder` 可能导致布局计算不一致。

---

## 优先级汇总

| 优先级 | 问题 | 影响面 |
|--------|------|--------|
| 🔴 高 | `_PlayerScreenState` 2500 行膨胀 | 开发效率、可维护性 |
| 🔴 高 | 状态管理双轨制导致全局重建 | 性能、代码一致性 |
| 🟡 中 | 缺乏暗色主题 | 用户体验、视觉疲劳 |
| 🟡 中 | AppBar 菜单过载 | 功能可发现性 |
| 🟡 中 | Widget 测试覆盖不足 | 迭代信心 |
| 🟡 中 | 导航策略不一致 | 用户体验一致性 |
| 🟢 低 | 可访问性缺失 | 包容性 |
| 🟢 低 | 部分字符串硬编码 | 国际化完整性 |
| 🟢 低 | 模型层过于集中 | 编译/可维护性 |
| 🟢 低 | 响应式断点分散 | 布局一致性 |
