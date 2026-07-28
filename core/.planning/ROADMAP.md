# Roadmap

## Current Baseline

Repository separation baseline 已建立：

- canonical contract `1.0.0`;
- runtime `0.7.0`;
- API generation `1`;
- initial split release `v0.7.0-split.1`;
- `listen-app` 通过 immutable artifact + lock 消费。

## Near-term Maintenance

1. **Core planning reset** — 用当前后端代码事实替代 monorepo live planning。
2. **Standalone cleanup** — 清理或改写仍假定 Flutter/monorepo 的后端脚本和长期文档。
3. **Contract release discipline** — 固化版本决策、release checklist 和 consumer handoff。
4. **Local quality gate** — GitHub Actions 不可用期间保持可重复的本地严格验证。
5. **Cross-repo integration evidence** — 为 contract/runtime release 与 app lock 更新保留可审计证据。

## Product Work

后端产品 phase 由 owner 决定优先级。任何跨仓 feature 必须先有 app 侧 user
journey/contract request，再进入 core contract 和实现 phase。纯 UI phase 不进入此 roadmap。
