# Requirements

## Contracts

- CORE-CONTRACT-001: `contracts/openapi/v1.yaml` 是 HTTP canonical contract。
- CORE-CONTRACT-002: 已注册路由与 OpenAPI method+path 必须双向一致。
- CORE-CONTRACT-003: path parameters、schemas 和 examples 必须通过结构校验。
- CORE-CONTRACT-004: API/contract/runtime version 必须出现在启动握手与 health。
- CORE-CONTRACT-005: breaking contract change 必须显式升级 major 并提供迁移决策。
- CORE-CONTRACT-006: content package 导入必须在持久化前完成验包，并以独立事务
  幂等附加候选；包不得创建、替换或降级 active 选择。
- CORE-CONTRACT-007: Content Package v2 必须让一个不可变 Package Release
  精确对应一个 Learning Edition 和一个 Material Revision，同时保持 Release、
  Resource、Blob、Media Rendition 与 Delivery 身份独立。
- CORE-CONTRACT-008: Content Package v2 必须同等表示 text、audio、video 与
  mixed material，不得把媒体、时长或字幕作为通用准入条件。
- CORE-CONTRACT-009: v2 检查必须在任何持久化或网络获取前完成 archive、canonical
  identity、hash、dependency、language-role、compatibility 与 size-limit 验证。
- CORE-CONTRACT-010: v2 Installation Plan 只能产生 candidate、opaque 或 missing
  disposition，不得携带或产生 active selection 与 Learner state。
- CORE-CONTRACT-011: Package Installation 与 Learning Edition Adoption 必须是
  独立语义操作；App 可以由一个明确 Learner intent 编排两者，但 package data
  不得声明本地采用或 active 状态。

## Runtime and Releases

- CORE-REL-001: contract/runtime artifacts 必须来自 clean commit。
- CORE-REL-002: manifest 必须记录 core commit、版本和 per-file SHA-256。
- CORE-REL-003: archive 解包必须拒绝路径穿越、重复成员和内容/manifest 漂移。
- CORE-REL-004: runtime bundle 必须能在源码树外启动、health、优雅退出。
- CORE-REL-005: 已发布 tag 与 artifact 不得静默覆盖。

## Architecture

- CORE-ARCH-001: domain 不依赖 application、HTTP、SQLite 或 provider adapters。
- CORE-ARCH-002: HTTP route 不直接拥有 provider/analysis workflow。
- CORE-ARCH-003: persistence 实现 repository seam，不定义产品政策。
- CORE-ARCH-004: secrets 不进入日志、read DTO 或普通持久化字段。
- CORE-ARCH-005: durable learning history 不因可替换 media/resource 被级联删除。
- CORE-ARCH-006: credential-free local realtime provider 必须限制为 loopback，
  并由 runtime seam 负责 sidecar readiness、终止与回收。
- CORE-ARCH-007: 可复用 whole-media 离线模型、provider、音频预处理和批生成
  位于 content-package producer 边界之外；Core 保留媒体身份、验包、候选、active
  选择、学习记录和消费体验。
- CORE-ARCH-008: learner recording、realtime conversation 和 learner-dependent
  LLM 能力保留在 Core，不得随离线生成管线迁出。
- CORE-ARCH-009: v2 的 Base Resource 运行时依赖不得要求 Assistance Resource；
  Assistance 可依赖 Base，生产输入关系只进入 Resource Provenance。
- CORE-ARCH-010: Core 的 material/package interface 必须返回可理解的能力、缺失
  条件与计划，不得要求 App 解析 Resource DAG 或推导 package policy。

## Quality

- CORE-QA-001: 正常验证不得消费付费模型 credit 或要求真实凭据。
- CORE-QA-002: contract change 必须运行 `scripts/validate-contracts.sh`。
- CORE-QA-003: Rust change 必须运行 focused tests；review 前运行 strict gate 或说明例外。
- CORE-QA-004: artifact change 必须运行 unit、verify 和对应 smoke。
- CORE-QA-005: 代码事实变化必须同步 live planning/codebase 文档。
- CORE-QA-006: 正常 local realtime 测试不得下载模型；真实 cascade smoke 必须显式授权。
