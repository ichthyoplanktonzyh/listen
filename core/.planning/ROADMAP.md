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

第一条 native package vertical 与 candidate-only Core import 已完成，真实 pinned
三仓 fixture round trip 已通过。下一阶段不再扩展 Core legacy producer，而是按
[active cutover roadmap](phases/001-offline-generation-split/001-ROADMAP.md)
完成唯一生产 seam 和旧实现删除：

1. **R0 · Honest integration gate — complete** —
   [listen-app#101](https://github.com/ichthyoplanktonzyh/listen-app/pull/101) 已让三仓
   round-trip 闸门结构化验证目标 E2E 确实执行并通过；任一跳过、失败或依赖准备
   错误均非零退出，同时修复 worktree 定位与 Gen contract lock 对账。
2. **R1 · Whole-media ASR cutover — complete** —
   拆开 Core whole-media 与 learner-recording transcription；Core 侧的
   `/v1/transcription/jobs*` 路由、job DTO/event 与 SQLite CAS job store 已删除，
   `TranscriptionCoordinator` 收敛为 `RecordingTranscriptionCoordinator`；
   App PR [#102](https://github.com/ichthyoplanktonzyh/listen-app/pull/102)
   已删除旧 job consumer/UI 并将 missing-transcript 唯一路由到 pinned Gen
   package journey；Core `v0.7.0-split.3`/contract `2.0.0` 已由 App 精确 pin，
   真实三仓 candidate-only round trip 通过。
3. **R2 · Native aligned Word Timeline** — alignment 作为 Gen 内部 stage，直接
   输出 package-native `word_timeline`，不复制 legacy production tree。
4. **R3 · Chunk/Prosody semantic alignment** — 消除 Core `ChunkTimeline` 与 package
   `prosody_analysis` 的重复/缺失投影，确定 foundation 的一个语义真源。
5. **R4 · Rich resources** — 按依赖顺序生产 Sense Group、Word Acoustics、Prosody
   Analysis 和可选 Phone Timeline。
6. **R5 · Legacy retirement** — 删除 `scripts/timeline-production`、旧 Core/App
   contracts/UI 和只服务旧生产链的 runtime/release inputs。

跨仓执行以 [listen-core#111](https://github.com/ichthyoplanktonzyh/listen-core/issues/111)、
[listen-gen#4](https://github.com/ichthyoplanktonzyh/listen-gen/issues/4) 和
[listen-app#100](https://github.com/ichthyoplanktonzyh/listen-app/issues/100)
同步。Core #103 已被新 seam supersede。

## Product Work

Published contract `2.0.0` folds the additive local realtime cascade work
(previously planned as `1.1.0`) together with the R1 whole-media ASR deletion.
The deletion of published `/v1/transcription/jobs*` is a breaking contract
change, so the next release is a major `2.0.0`: credential-free loopback
profile、独立协议 codec、SQLite v53 与 opt-in managed sidecar 已完成并合并；
release `v0.7.0-split.3` 与 app lock/DTO handoff 已完成；经显式授权的 Apple
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
