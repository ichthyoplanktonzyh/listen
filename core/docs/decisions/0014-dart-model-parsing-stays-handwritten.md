# 0014. Dart 模型解析保持手写，以 fixture 契约测试为防漂移守卫

- 日期：2026-07-03
- 状态：已接受
- 关联：Phase 2.23 T7（`design-notes/timeline-dart-codegen-research.md`）、
  `apps/desktop/test/contract/lltimeline_parse_test.dart`、
  `apps/desktop/test/contract/backend_event_contract_test.dart`

## 背景

`apps/desktop/lib/models/timeline.dart`（约 2.7k 行）手写 JSON 解析曾被列为
契约漂移风险（2.23 审核 A4）。Phase 2.23 已用两层 fixture 契约测试补上守卫：
LLTimeline committed fixture 的 Dart typed 解析测试（Rust/Python/Dart 三方共用
同一 fixture 文件）与 SSE golden 信封双端测试。T7 调研评估了
json_serializable / freezed 迁移的收益与成本。

## 决策

1. **存量 `timeline.dart` 不做 codegen 迁移。** 该解析器的核心价值是刻意的
   兼容容错（optional 字段软默认、旧资源形状、宽松 envelope）。codegen 消除的
   是样板，无法消除的恰恰是这些兼容语义——生成器的严格性反而可能静默改变
   容错行为；调研确认大多数非平凡字段仍需手写 converter，净收益小、风险为
   契约级。
2. **防漂移的标准机制是 fixture 契约测试，不是 codegen。** 新增或修改 Dart
   模型时必须扩展对应契约测试（committed fixture 解析 / golden 信封），
   这是 contract 变更流程的一部分。
3. **3.x 新增 DTO（practice/review 等）默认沿用手写 `fromJson` + 契约测试。**
   若 3.x 新模型家族数量显著增长（约 >10 个新家族）且样板成为真实负担，
   可按 T7 建议做"仅新代码"的 json_serializable 小试点，试点结论以新 ADR
   决定是否扩大——不回头迁移存量。
4. 移除任何手写容错行为都视为契约变更，需走 contract 流程，不当作清理。

## 后果

- 不引入 build_runner / 生成文件工作流；构建与评审面不变。
- Dart 侧契约安全依赖测试纪律：模型改动未同步 fixture 测试时由测试失败兜底。
- Phase 3.x 的 Flutter 工作不受阻塞，也不承担迁移成本。
