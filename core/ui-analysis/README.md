# LLPlayerNext UI/UX 分析

> 生成日期: 2026-06-24
> 目的: 为 UI/UX 重构提供基础 —— 先理解数据/状态，再设计界面。

## 核心主张

UI/UX 只是数据/状态的投影。重构 UI/UX 之前，必须先回答：

1. **我们有什么数据/状态？** → 见 [状态机分析](01-state-machines.md)
2. **UI 展示了哪些信息？** → 见 [UI 数据架构](02-ui-data-architecture.md)
3. **数据如何在系统中流动？** → 见 [数据流与领域模型](03-data-flow-and-domain-models.md)

## 文件结构

```
ui-analysis/
├── README.md                        ← 本文件
├── 01-state-machines.md             ← 5 个状态机的完整分析
├── 02-ui-data-architecture.md       ← 每个 UI 组件消费的数据和展示的信息
└── 03-data-flow-and-domain-models.md ← 数据流路径 + 核心领域模型
```

## 关键发现

### 当前状态管理的优势

1. **不可变状态 (Immutable State)**: 所有 Controller 使用 `copyWith` 模式，状态变更可追踪
2. **ChangeNotifier 模式**: Simpler 且易于理解，每个 Controller 独立管理自己的状态切片
3. **单一编排层**: `_PlayerScreenState` 是唯一的数据编排点，API 调用和跨 Controller 同步集中在此

### 当前状态的劣势 (UI/UX 重构需关注)

1. **状态分散在 4 个 Controller**: Widget 需要通过 `ListenableBuilder` 或 `AppControllers.of(context)` 合并监听多个 Controller，粒度不够细
2. **状态与 UI 逻辑耦合**: `_PlayerScreenState` 同时负责编排数据、管理本地 UI 状态（`status`, `dragging`, `connectingApi`）和布局构建，职责过重（~600 行 build/builder 方法）
3. **无 Selector 模式**: Widget 监听到任何状态变更就会重建，即使只关注一个字段。例如 `PlayerState` 有 15 个字段，但任何字段变更都会触发所有监听者
4. **UI 状态和业务状态混合**: `status` (String 状态栏文本) 和 `connectingApi` 等本地 UI 状态与业务状态混在一起
5. **状态类型不够精确**: 很多字段使用 `Map<String, dynamic>`（如 `wordProfiles`, `pronunciationBySentence` 等），缺少类型安全
6. **无副作用管理**: API 调用直接在 Orchestrator 中编排，没有统一的状态机管理 loading/error/success 状态
7. **无导航状态管理**: 页面跳转（VocabularyScreen、SubtitleResourcesScreen 等）使用 Navigator.push，状态不共享
