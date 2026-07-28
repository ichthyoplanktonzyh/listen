# Project

## Mission

`listen-app` 是 listen 的 macOS-first Flutter 产品。它把本地媒体、字幕、时间轴、
词汇、诊断、练习、读写说和对话能力组织为清晰、诚实、可操作的学习体验。

## Product Direction

- 从用户旅程和 UI 所需信息出发设计功能；
- 播放和高频呈现状态保持本地、流畅；
- backend 能力通过 versioned local API 消费；
- loading、空、失败、降级、取消和 provenance 在 UI 中真实可见；
- 学习资产和历史比一次性的媒体/resource 更持久；
- 桌面体验保持键盘、窗口、响应式、可访问性和 macOS 行为一致。

## Backend Relationship

后端权威仓库是 `ichthyoplanktonzyh/listen-core`。本仓不读取其源码，通过
`backend.lock.json` 固定 immutable contract/runtime release。

## Non-goals

- 不拥有 canonical OpenAPI、Rust domain/application/persistence；
- 不从 moving core `main` 构建；
- 不把 Python/research runtime 嵌入 consumer app；
- 不在 app planning 中安排纯后端 phase；
- 不用 UI fallback 掩盖缺失、失败或权限语义。
