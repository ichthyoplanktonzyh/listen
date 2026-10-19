# Project

## Mission

`listen-app` 是 listen 的 macOS-first Flutter 产品。它把本地媒体、字幕、时间轴、
词汇、诊断、练习、读写说和对话能力组织为清晰、诚实、可操作的学习体验。

## Product Direction

- 从用户旅程和 UI 所需信息出发设计功能；
- 支持从内容发现、合法媒体获取、已有 `.listenpkg` 匹配或导入，到缺失资源时调用
  `listen-gen`、经 Core 安装候选并进入学习的完整旅程；
- 将媒体可用性、package 可用性、生成状态、安装状态和 active 选择作为不同事实呈现；
- 允许使用官方、社区和本地未签名 package，并分别呈现 publisher、review、license
  与 timeline compatibility；
- 播放和高频呈现状态保持本地、流畅；
- backend 能力通过 versioned local API 消费；
- loading、空、失败、降级、取消和 provenance 在 UI 中真实可见；
- 学习资产和历史比一次性的媒体/resource 更持久；
- 桌面体验保持键盘、窗口、响应式、可访问性和 macOS 行为一致。

## Backend Relationship

后端权威仓库是 `ichthyoplanktonzyh/listen-core`。本仓不读取其源码，通过
`backend.lock.json` 固定 immutable contract/runtime release。

离线 package 生产由开源 `listen-gen` 承担。App 负责把它作为外部工具进行编排，
包括 progress、cancel、retry 和临时输出生命周期，但不拥有其 provider、预处理或
打包实现。未来 Hosted Catalog/Registry 的服务端归属尚未确定。

## Non-goals

- 不拥有 canonical OpenAPI、Rust domain/application/persistence；
- 不拥有 canonical `.listenpkg` schema、`listen-gen` 生产实现或 Registry server；
- 不从 moving core `main` 构建；
- 不把 Python/research runtime 嵌入 consumer app 或 widget；
- 不在 app planning 中安排纯后端 phase；
- 不用 UI fallback 掩盖缺失、失败或权限语义。
