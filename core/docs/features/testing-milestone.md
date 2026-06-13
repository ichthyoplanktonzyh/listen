# Testing Milestone — 测试体系建设

> **Created:** 2026-06-13
> **Branch:** `feature/asr-word-timestamps`
> **Status:** P0 complete, P1 complete, P2 partial
> **Target:** P0 → P1 → P2 梯度推进

## 概述

在 `0.7.1` / `testing-workflow` 基础上系统性提升测试覆盖率和质量。按优先级分三梯队推进：

| Tier | 目标 | 时间 |
|------|------|------|
| **P0** | 填补最关键的测试空白 | 1-2 天 |
| **P1** | 建立防御性测试基础设施 | 3-5 天 |
| **P2** | 性能 + E2E + 回归 | 下个里程碑 |

---

## 当前基线 (0.7.1)

### 测试基础设施

| 组件 | 文件 | 状态 |
|------|------|------|
| 统一测试入口 | `scripts/test.sh` | ✅ 4 种模式 + strict/JSON/debug/verbose |
| 共享工具库 | `scripts/lib-testing.sh` | ✅ API 生命周期 + curl + 断言 |
| 契约验证 | `scripts/validate-contracts.sh` | ✅ Schema + OpenAPI + 示例 |
| 基础设施自测 | `scripts/test-infrastructure.sh` | ✅ cleanup + mode + strict + JSON + log retention |
| CI | `.github/workflows/ci.yml` | ✅ Rust 3 OS + desktop/contracts + coverage/bench + fuzz smoke |

### Rust 测试分布

| Crate | 单元测试 | 集成测试 | 总计 | 差距 |
|-------|----------|----------|------|------|
| `api-events` | 2 | 0 | 2 | 🟡 |
| `api-http` | 11 | 0 | 11 | ✅ 含 API 版本快照 |
| `application` | **42** | 0 | **42** | ✅ P0 完成 |
| `diagnosis-core` | 18 | 0 | 18 | ✅ P1 完成 |
| `dictionary-provider` | 3 | 0 | 3 | 🟡 |
| `domain` | 3 | 0 | 3 | 🟡 |
| `persistence-sqlite` | 19 | 6 | 25 | ✅ 最佳 |
| `speech-analysis` | 14 | 3 | 17 | ✅ 含 proptest |
| `subtitle-core` | 12 | 0 | 12 | ✅ 含 proptest |
| **总计** | **~124** | **9** | **~133** | |

### Flutter 测试分布

| 文件 | 描述 |
|------|------|
| `controllers_test.dart` | 控制器逻辑 |
| `external_tools_test.dart` | 外部工具解析 |
| `m18_ui_test.dart` | M18 UI 组件 |
| `settings_test.dart` | 设置页 |
| `timeline_test.dart` | 时间线/字幕 |
| `transcription_ui_test.dart` | 转写 UI |
| `vocabulary_book_test.dart` | 词汇本 |
| **总计 7 个文件, ~38 tests** | widget/unit 级 |

### 测试缺口总览

| 维度 | 现状 | 目标 |
|------|------|------|
| `api-http` 独立集成测试 | 仍以内嵌 Router 测试为主 | 后续按需要迁移到 `tests/` |
| CI 覆盖率门禁 | 50% | 逐步提升 |
| Fuzz 测试 | 3 targets + CI smoke | 积累 corpus、延长定时运行 |
| 性能回归 | benchmark 可编译 | 建立统计基线与退化策略 |
| API 兼容性 | 表面回归门 | 增加语义 breaking-change 检测 |
| Flutter golden 测试 | 无 | P2 |
| E2E 测试 | 无 | P2 |

---

## P0 — 关键空白填补

### P0-1: `application` crate 单元测试

**目标文件:** `crates/application/src/lib.rs` (新增 `#[cfg(test)] mod tests`)

**测试目标 (纯函数优先):**

| 函数 | 测试用例 |
|------|----------|
| `require_text()` | 空字符串 → Validation 错误; 空白 → Validation 错误; 有效文本 → Ok |
| `clean_optional()` | None → None; 空白 → None; 有效文本 → Some |
| `normalize_american_english()` | went/was/did/had 等不规则过去式; ies→y; ing→去尾; ed→去尾; s→去尾; ss 保留; 无变化返回原值 |
| `normalize_phrase()` | "take care of" → 各词 normalize 后 join |
| `phrase_candidates()` | 句子中匹配到的 phrase; 部分匹配; 无匹配 |
| `lexical_from_word()` | profile → LexicalEntry 映射完整性 |
| `lexical_source_from_word()` | SourceContext → LexicalSourceContext 映射 |
| `timing_priority()` | Estimated=1, ForcedAligned=2, AsrReported=3, UserAdjusted=4 |

**状态:** ✅ done — 42 测试，覆盖所有核心纯函数

### P0-2: `api-http` 集成测试

**目标文件:** `crates/api-http/tests/api_integration_test.rs`

**测试场景:**

| # | 测试 | 验证点 |
|---|------|--------|
| 1 | Health endpoint 公开可达 | 200, `api_version: 1` |
| 2 | Media 注册 + 读取 | 创建 → GET 返回相同数据 |
| 3 | Subtitle 导入 (真实 SRT 文件) | 200, sentences 数量正确 |
| 4 | 认证失败返回 401 | 无 token 或错误 token |
| 5 | 词汇 CRUD 流程 | update → read → list |
| 6 | SSE events 流 | 连接建立, 收到初始事件 |
| 7 | 发音规则查询 | 返回 rule_catalog |

**状态:** 🟡 已在 lib.rs 有 6 个 HTTP 层测试（含 media、subtitle、speech batch job 等）。独立 `tests/` 集成测试优先级降低。

### P0-3: CI 覆盖率门禁

**当前状态:** CI 已有 `cargo-llvm-cov` 产出 `lcov.info`，但没有阈值检查。

**目标:** 在 coverage job 中加入最低阈值检查。

```yaml
- run: cargo llvm-cov --workspace --lcov --output-path lcov.info --fail-under-lines 45
```

起步阈值 50%（`application` crate 已有 42 测试），后续提高到 60%。

**状态:** ✅ done — `--fail-under-lines 50` 已加入 CI coverage job

---

## P1 — 防御性基础设施

### P1-1: `testdata/` 规范化

**当前状态:** `testdata/` 已有基础结构，但需要：
- `testdata/fixtures/` — 测试 fixture (JSON, SRT 等)
- `testdata/fixtures/asr/` — ASR 相关 fixture
- `testdata/fixtures/subtitles/` — 字幕 fixture
- `testdata/generated/` — 生成的媒体文件 (已是)
- 更新 `testdata/README.md` 描述分类和使用方式

**状态:** ✅ done — testdata/README.md 已重写为完整 fixture catalog

### P1-2: Fuzz 测试

**目标 crate:** `subtitle-core` (SRT/WebVTT 解析), `speech-analysis` (ASR JSON 解析)

使用 `cargo-fuzz`:
```bash
rustup toolchain install nightly --profile minimal
cargo install cargo-fuzz --locked
(cd crates/subtitle-core && cargo +nightly fuzz run srt_parse -- -max_total_time=10)
(cd crates/subtitle-core && cargo +nightly fuzz run vtt_parse -- -max_total_time=10)
(cd crates/speech-analysis && cargo +nightly fuzz run asr_timing -- -max_total_time=10)
```

| Fuzz Target | 输入 | 检查 |
|-------------|------|------|
| `srt_parse` | 任意字节序列 | 不 panic、不 OOM |
| `vtt_parse` | 任意字节序列 | 不 panic、不 OOM |
| `asr_timing_extract` | 任意 JSON | 不 panic、不 OOM |

**状态:** ✅ done — 3 fuzz targets (srt_parse, vtt_parse, asr_timing)，CI
使用 nightly Rust 对每个 target 执行 10 秒 smoke run。两个 fuzz manifest
声明独立 workspace 并提交各自锁文件，`asr_timing` target 已与当前公共函数
签名同步。

### P1-3: `--quick` 模式增强

**当前:** `--quick` 只跑 fmt + clippy + analyze，不跑测试。

**改进:** 在 quick 模式中加入**快速单元测试子集**（仅 lib tests，排除 integration tests，排除 `#[ignore]`）：

```bash
cargo test --workspace --lib  # 只跑单元测试，跳过集成测试
```

这样 `--quick` 总耗时仍然 <30s，但多了实际测试验证。

**状态:** ✅ done — `cargo test --workspace --lib` 已加入 quick 模式

### P1-4: `diagnosis-core` 单元测试补充

**目标文件:** `crates/diagnosis-core/src/lib.rs` (新增 `#[cfg(test)] mod tests`)

纯逻辑 crate，非常适合增加测试。覆盖 diagnosis 核心算法。

**状态:** ✅ done — 18 测试覆盖 diagnose 所有分支

### P1-5: 测试基础设施自测与生命周期收口

- 新增 `scripts/test-infrastructure.sh`，验证 cleanup、runner 模式、strict
  参数、JSON 输出和失败日志保留。
- `setup_test_dir()` 自动注册 EXIT cleanup；所有验证脚本失败或正常退出时
  都会清理 API、mock 进程和临时目录。
- M1.7/M1.8 统一使用 `start_api()`，避免重复启动逻辑和孤儿 API 进程。
- ECDICT 并行测试改用 `tempfile::NamedTempFile`，消除基于时钟文件名碰撞。
- `.claude/worktrees/` 被忽略，避免本地 worktree 被误纳入提交。

**状态:** ✅ done

---

## P2 — 深度覆盖 (下个里程碑)

### P2-1: Flutter Golden 测试
- 字幕叠加层渲染截图对比
- 当前词高亮样式截图对比
- 使用 `alchemist` 或 `golden_toolkit`

### P2-2: E2E 测试
- macOS 桌面应用截图对比
- 使用 `integration_test` package

### P2-3: 性能基准 (`cargo bench`)
- 已通过 `criterion` 建立 2 个 crate 的基准测试基础设施
- `subtitle-core`: SRT/VTT 解析 (small + 2k 句)、tokenize、normalize_display
- `speech-analysis`: ASR timing 提取 (small + 500 segments)、word timing 估算

**状态:** 🟡 基础设施完成 — 10 benchmark cases，CI 使用
`cargo bench --workspace --no-run --locked` 防止 benchmark 编译腐化；性能退化
阈值仍待定义。

### P2-4: API 表面回归测试
- 已添加 `openapi_version_snapshot_and_path_count` 测试
- 版本快照 (1.0.0)、路径数快照 (51)、schema 存在性、v1 前缀检查

**状态:** 🟡 部分完成 — 能捕获路径数量和关键 schema 名称变化，但不能替代
字段类型、required 集合等语义 breaking-change 检测。

### P2-5: Property-based testing
- 已通过 `proptest` 添加 10 个属性测试
- `speech-analysis`: estimate_word_timings 输出计数、start≤end、边界、单调性 (4)
- `subtitle-core`: normalize_display 幂等性、无panic；tokenize 规范化；SRT/VTT 无panic；SRT 解析字段有效性 (6)

**状态:** ✅ done — 10 property-based tests

---

## 进度追踪

| # | 任务 | Tier | 状态 | 完成日期 |
|---|------|------|------|----------|
| 1 | 测试里程碑文档 | — | ✅ done | 2026-06-13 |
| 2 | `application` crate 单元测试 | P0 | ✅ done | 2026-06-13 |
| 3 | `api-http` 集成测试 | P0 | 🟡 已在 lib.rs 中有 6 个 HTTP 层测试 | |
| 4 | CI 覆盖率门禁 | P0 | ✅ done | 2026-06-13 |
| 5 | `testdata/` 规范化 | P1 | ✅ done | 2026-06-13 |
| 6 | Fuzz 测试框架 (3 targets) | P1 | ✅ done | 2026-06-13 |
| 7 | `--quick` 增强 | P1 | ✅ done | 2026-06-13 |
| 8 | `diagnosis-core` 测试补充 | P1 | ✅ done | 2026-06-13 |
| 9 | Flutter golden 测试 | P2 | ⬜ | |
| 10 | E2E 测试 | P2 | ⬜ | |
| 11 | 性能基准与编译门禁 | P2 | 🟡 基础设施完成 | 2026-06-13 |
| 12 | API 表面回归测试 | P2 | 🟡 部分完成 | 2026-06-13 |
| 13 | Property-based testing | P2 | ✅ done | 2026-06-13 |
| 14 | 测试基础设施自测与 cleanup 收口 | P1 | ✅ done | 2026-06-13 |
| 15 | Fuzz CI smoke | P1 | ✅ done | 2026-06-13 |
| 16 | Benchmark CI 编译门禁 | P2 | ✅ done | 2026-06-13 |
| 17 | OpenAPI 语义兼容性检测 | P2 | ⬜ | |

---

## 参考

- [Unified Testing Workflow](./testing-workflow.md)
- [ADR 0007 — Pronunciation and Word Timing Foundations](../decisions/0007-pronunciation-and-word-timing.md)
- [CI Configuration](../../.github/workflows/ci.yml)
- [Test Data README](../../testdata/README.md)
