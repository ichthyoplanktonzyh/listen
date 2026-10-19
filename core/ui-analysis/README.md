# LLPlayerNext UI Statecharts 分析

## 概述

本分析运用 **Statecharts（状态图）** 方法论对 LLPlayerNext 项目的 UI 状态管理进行建模。Statecharts 由 David Harel 于 1987 年提出，是对有限状态机（FSM）的形式化扩展，核心概念包括：

| 概念 | 含义 | 本项目中的体现 |
|------|------|----------------|
| **层次化状态（Hierarchy）** | 状态可嵌套，子状态继承父状态行为 | `PlayerScreen` 中的全局 UI 状态嵌套各子控制器的状态 |
| **正交区域（Orthogonality）** | 多个独立并发运行的状态机 | `PlayerController` / `SubtitleController` / `LearningController` 并行运行 |
| **历史状态（History）** | 记住退出前的最后一个子状态 | 侧面板 Tab 选择 `sidePanel` 保留上次选择 |
| **守卫条件（Guard）** | 转移需满足的条件 | `mounted` 检查、`mediaId != null` 等前置条件 |
| **动作（Action）** | 进入/退出状态时或转移时执行的操作 | `entry:` 加载数据、`exit:` 清理资源、转移时调用 API |
| **延迟事件（Delayed Event）** | 经过指定时间后触发的事件 | `progressTimer` 每 5 秒保存播放进度 |

## 项目架构简览

```
┌──────────────────────────────────────────────────────┐
│                    PlayerScreen                       │
│  ┌───────────────┐  ┌──────────────────────────────┐ │
│  │  PlayerSurface │  │        SidePanel             │ │
│  │  (视频 + 字幕)  │  │  ┌──────┬─────────┬───────┐ │ │
│  │               │  │  │Transcript│Resources│Word│Diag│ │
│  └───────────────┘  │  └──────┴─────────┴───────┘ │
│  ┌──────────────────────────────────────────────┐   │
│  │              Bottom Bar (Controls)            │   │
│  └──────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘

状态容器（独立正交区域）：
  PlayerController.Store<PlayerState>
  SubtitleController.Store<SubtitleState>
  LearningController.Store<LearningState>
  SettingsController (简单 ChangeNotifier)
```

## 识别的状态机概要

本项目包含 **4 个并发运行的正交状态机**，外加 **1 个事件驱动的 Orchestrator**：

| # | 状态机 | Store 类型 | 职责 |
|---|--------|-----------|------|
| 1 | **PlayerMachine** | `Store<PlayerState>` | 媒体播放生命周期 |
| 2 | **SubtitleMachine** | `Store<SubtitleState>` | 字幕加载与同步 |
| 3 | **LearningMachine** | `Store<LearningState>` | 词汇学习与诊断 |
| 4 | **SettingsMachine** | ChangeNotifier | 设置持久化 |
| 5 | **AppOrchestrator** | `_PlayerScreenState` | 编排以上状态机的协调与事件分发 |

## 状态图形式化约定

本文使用 **SCXML 风格**的文本表示法：

```
状态名 [区域名] {
  entry: 进入动作
  exit: 退出动作
  
  子状态A {
    entry: ...
    on EVENT: 目标状态 / 动作
  }
}

转移: 源状态 --[事件(守卫)]--> 目标状态 / 动作
```

## 文件结构

```
ui-analysis/
├── README.md                  # 本文 — 总览与约定
├── 01-player-machine.md       # PlayerMachine 状态图
├── 02-subtitle-machine.md     # SubtitleMachine 状态图
├── 03-learning-machine.md     # LearningMachine 状态图
├── 04-orchestrator.md         # AppOrchestrator 编排层分析
└── 05-recommendations.md      # 基于 Statecharts 的改进建议
```
