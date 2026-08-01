# Roadmap

## Current Baseline

Repository separation baseline 已建立：

- published canonical contract `1.0.0`;
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

## Offline Resource Generation Split

1. **Native ASR package slice** — external producer 原生完成 media → ASR
   Subtitle Text Track + Word Timeline → deterministic `.listenpkg`；LLTimeline
   只保留迁移转换。
2. **Candidate-only Core import** — 验包后用独立 SQLite 事务幂等附加 track、
   analysis candidates 与 corpus，不创建或改变 active。
3. **Whole-media cutover** — 在固定 fixture 和生产观察验证后，把离线生成入口
   切到 package producer；保留 learner recording 与 realtime ASR。
4. **Legacy removal** — 只在切流完成后，按独立切片删除 Core whole-media 模型/
   provider/预处理/批生成和对应 `scripts/timeline-production` 责任。

## Product Work

未发布的 contract `1.1.0` local realtime cascade 已完成并合并：
credential-free loopback profile、独立协议 codec、SQLite v53 与 opt-in managed
sidecar 已进入 core；后续 release、app lock/DTO handoff，以及经显式授权的 Apple
Silicon 实机短音频 smoke 继续遵循既有发布门禁。

Owner 已将语言学习模型重构设为下一条 P0 主线：

1. **Domain vocabulary (#81)** — 固定 Content Document/Selection、Learning
   Object 概念族、Activity/Attempt、Evidence/Judgment/Projection/User
   Authority、Capability/Channel 与 Learning Agenda 的边界；不创建万能父实体。
2. **Construction Learning MVP (#80)** — 先修正 spike 的英语中心 variant
   边界，再按“真实实例 → 解释 → 识别 → 变式产出 → evidence”交付最小垂直切片。
3. **Frontend-originated contracts** — Learning Session、Learning Agenda、
   Assistance Ladder、Learning Goal 与 Construction UI 先由 `listen-app`
   给出旅程、状态和信息请求，core 再设计最小兼容合约。

其他后端产品 phase 由 owner 决定优先级。任何跨仓 feature 必须先有 app 侧 user
journey/contract request，再进入 core contract 和实现 phase。纯 UI phase 不进入此 roadmap。
