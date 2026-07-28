# Planning Maintenance

## 文件职责

| 文件 | 职责 | 更新时机 |
|---|---|---|
| `PROJECT.md` | 后端使命、边界、原则、非目标 | 方向或边界改变 |
| `REQUIREMENTS.md` | 可验证的后端要求 | 需求增删改 |
| `ROADMAP.md` | 后端阶段、依赖和优先级 | 排期改变 |
| `STATE.md` | 当前状态、active phase、下一步 | 每个有效工作切片 |
| `MILESTONES.md` | 已完成阶段的链接索引 | phase/milestone 收口 |
| `codebase/*` | 当前代码事实 | 架构或结构改变 |
| `CHANGELOG.md` | 已发布、人工整理的历史 | release 收口 |

## 维护规则

- 文档只陈述当前仓库可以从代码、测试、release 或 owner 决策验证的事实。
- 不把 `listen-app` 的 UI 状态、文件路径、测试数量写成 core 当前事实。
- 跨仓状态使用稳定标识：仓库、commit、release tag、contract/runtime version、
  artifact SHA、issue 或 PR。
- `STATE.md` 保持简短，不复制 changelog，不记录瞬时分支状态。
- `codebase/` 从代码更新，不从旧 planning 猜测。
- 完成的 phase 写 `CLOSEOUT.md` 后冻结；更正写入新 phase/context。
- ADR 位于 `docs/decisions/`，既有 ADR 不重写；新决策追加编号并注明 supersedes。
- 普通 feature、fix、refactor、planning、docs 分支不修改根 `CHANGELOG.md`。
- 发布负责人在发布 contract/runtime/version 时，根据已合并 PR 一次性整理
  `CHANGELOG.md`；重点记录兼容性、迁移、安全与运维相关变化。

## Phase 生命周期

标准目录：

```text
.planning/phases/<id>-<slug>/
├── <id>-CONTEXT.md
├── <id>-PLAN.md
└── <id>-CLOSEOUT.md
```

开始时更新 `ROADMAP.md` 与 `STATE.md`；执行中维护 plan；完成时记录验证证据、
兼容性、release/迁移结果，并更新 `MILESTONES.md`。

## 归档规则

`archive/monorepo-baseline/` 是拆仓历史，不参与当前 first-read，不做日常修补。
需要历史背景时引用具体文件；不要把整个旧 phase 恢复为 active。
