# Requirements

## Contracts

- CORE-CONTRACT-001: `contracts/openapi/v1.yaml` 是 HTTP canonical contract。
- CORE-CONTRACT-002: 已注册路由与 OpenAPI method+path 必须双向一致。
- CORE-CONTRACT-003: path parameters、schemas 和 examples 必须通过结构校验。
- CORE-CONTRACT-004: API/contract/runtime version 必须出现在启动握手与 health。
- CORE-CONTRACT-005: breaking contract change 必须显式升级 major 并提供迁移决策。

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

## Quality

- CORE-QA-001: 正常验证不得消费付费模型 credit 或要求真实凭据。
- CORE-QA-002: contract change 必须运行 `scripts/validate-contracts.sh`。
- CORE-QA-003: Rust change 必须运行 focused tests；review 前运行 strict gate 或说明例外。
- CORE-QA-004: artifact change 必须运行 unit、verify 和对应 smoke。
- CORE-QA-005: 代码事实变化必须同步 live planning/codebase 文档。
- CORE-QA-006: 正常 local realtime 测试不得下载模型；真实 cascade smoke 必须显式授权。
