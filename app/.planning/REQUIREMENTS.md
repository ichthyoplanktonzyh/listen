# Requirements

## User Experience

- APP-UX-001: 每个异步能力必须有明确 loading、success、empty、error、cancel/retry 状态。
- APP-UX-002: provider/model/heuristic/projection provenance 不得被 UI 提升为更强事实。
- APP-UX-003: 高频 playback、subtitle cursor、word highlight、seek 和 loop 保持本地。
- APP-UX-004: visible flows 必须考虑 keyboard、focus、screen reader、reduced motion 和窗口尺寸。
- APP-UX-005: UI 与 learning language 独立。

## Architecture

- APP-ARCH-001: widget 不解析 raw HTTP map，不启动 backend 进程工作流。
- APP-ARCH-002: service 公共边界返回 typed client models。
- APP-ARCH-003: controller/coordinator 拥有状态机和生命周期；widget 负责呈现与输入。
- APP-ARCH-004: design literals 复用 `lib/theme` token。
- APP-ARCH-005: 正常开发和测试不依赖 sibling core checkout。

## Core Consumption

- APP-CORE-001: `backend.lock.json` 必须固定 core commit、versions、URLs 和 SHA-256。
- APP-CORE-002: artifact 安装必须校验 archive、manifest、per-file hash 和 compatibility。
- APP-CORE-003: startup handshake 在正常请求前验证 API/contract/runtime compatibility。
- APP-CORE-004: contract-facing change 必须包含 pinned fixtures 和 focused contract tests。
- APP-CORE-005: `.backend/`、下载包、build/dist 和 secrets 不得提交。
- APP-CORE-006: `.listenpkg` 导入必须显示结构化 receipt，并保持 candidate 与 active 分离。
- APP-CORE-007: Core fingerprint mismatch 必须是独立、可恢复且不泄漏原始 transport 的状态。

## Local Generation

- APP-GEN-001: App 只通过 versioned machine-event protocol 编排外部 `listen-gen`。
- APP-GEN-002: generator process、子进程取消和临时 package 生命周期由 service/controller seam 管理。
- APP-GEN-003: executable/provider 配置只来自显式本地 platform seam；secrets 不写入普通 settings、日志或 UI。
- APP-GEN-004: 旧 whole-media transcription、recording 与 realtime 路径在切流前保持可用。

## Quality

- APP-QA-001: review 前运行 strict analyze 和相关 Flutter tests。
- APP-QA-002: backend lock/assembly change 必须运行 installer verify、Release build 和 packaged smoke。
- APP-QA-003: visible change 必须有 widget/controller 测试或明确人工证据。
- APP-QA-004: 代码事实变化必须同步 live planning/codebase 文档。
