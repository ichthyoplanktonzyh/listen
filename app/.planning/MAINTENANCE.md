# Planning Maintenance

## 文件职责

| 文件 | 职责 | 更新时机 |
|---|---|---|
| `PROJECT.md` | app 愿景、用户价值、边界和非目标 | 产品方向改变 |
| `REQUIREMENTS.md` | 可测试的前端要求 | 需求增删改 |
| `ROADMAP.md` | 前端阶段、依赖和优先级 | 排期改变 |
| `STATE.md` | 当前体验状态、pinned core、下一步 | 每个有效工作切片 |
| `MILESTONES.md` | 已完成 frontend phase 索引 | phase/milestone 收口 |
| `codebase/*` | 当前 Flutter 代码事实 | 架构或结构改变 |
| `CHANGELOG.md` | 每次提交的事实历史 | 每个 commit-worthy change |

## 维护规则

- 文档只写本仓可从 Flutter 代码、测试、lock、build 或 owner 决策验证的事实。
- 不复制 core roadmap、Rust 架构或 backend planning。
- 后端依赖用 `backend.lock.json` 和稳定链接描述，不写“当前 core main”。
- `STATE.md` 保持简短；不复制 changelog，不记录瞬时分支状态。
- `codebase/` 从当前 `lib/`、`macos/`、`tool/`、`test/` 更新。
- 完成的 phase 写 `CLOSEOUT.md` 后冻结。
- 每个 commit-worthy change 在根 `CHANGELOG.md` 添加精确到分钟的时间戳。

## Frontend Phase 生命周期

```text
.planning/phases/<id>-<slug>/
├── <id>-CONTEXT.md
├── <id>-PLAN.md
├── UI-SPEC.md          # visible work when needed
└── <id>-CLOSEOUT.md
```

CONTEXT 记录 user journey、问题和证据；PLAN 记录切片与验证；UI-SPEC 记录状态、
布局、响应式、可访问性和交互约束；CLOSEOUT 记录测试、截图/人工证据、core pin
和剩余风险。
