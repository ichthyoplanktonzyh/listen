# Project

## Mission

`listen-core` 为 listen 产品提供本地优先、可测试、可版本化的学习后端：

- Rust 领域、应用、持久化和 loopback HTTP 服务；
- 字幕、时间轴、诊断、词汇、练习、读写说和 provider 能力；
- 生产/研究管线与可审计 evaluation；
- canonical contracts 和可复现 runtime artifacts。

它处于开放 Resource Package 生态的可信消费平面：媒体、不可变 Package
Release 和学习记录是独立资产；Core 验证并幂等安装候选，active 选择与学习
历史始终留在本地学习语义中。可复用的昂贵离线生产迁移到 `listen-gen`。

## Consumer

主要消费者是独立仓库 `ichthyoplanktonzyh/listen-app`。消费者只能依赖：

1. 版本化 HTTP/OpenAPI 合约；
2. 版本化事件/资源 schema；
3. immutable contract/runtime release artifacts。

## Principles

- contract-first，发布物不可变；
- domain/application/adapters 单向依赖；
- 本地数据与 durable learning history 优先；
- provider-neutral 边界和显式 capability；
- provenance、失败、取消、降级语义诚实；
- heavy production runtime 与 consumer runtime 隔离；
- 不要求消费者读取源码或追踪 moving `main`。
- package release 不可变，listing 可变，更新只增加候选而不自动切换 active；
- publisher、review 和 license 状态相互独立，任何信任标签都不能绕过验包。

## Non-goals

- 不拥有 Flutter UI/UX、app state 或 macOS 最终产品装配；
- 不在 core planning 中安排纯前端工作；
- 不把实验性模型结果未经 evidence gate 直接声明为产品事实；
- 不为跨仓便利创建共享源码目录或恢复 monorepo 隐式路径依赖。
- 不拥有 Flutter 发现/目录体验、`listen-gen` 的离线生产实现，或尚未确定
  归属的 Hosted Catalog/Registry。
