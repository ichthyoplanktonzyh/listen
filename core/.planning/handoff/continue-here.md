# Continue Here — Phase 2.6 已收口

> 最后更新：2026-06-23 CST
> 单一接续入口（历史 handoff 见同目录 dated 文件，不必读）。

## 现在在哪

**Phase 2.6（多语言学习基础，English + Chinese）已全部完成并收口**（Step 1-7）。
收口文档：`.planning/phases/2.6-multilingual-learning-foundation/2.6-CLOSEOUT.md`。
Step 7 **待提交**（见下）。下一步由你定（候选见末尾）。

| 提交 | 内容 |
|---|---|
| （未提交） | Step 7：双语回归收敛 + 收口（CLOSEOUT/STATE/ROADMAP/REQUIREMENTS） |
| `9278fc8` | Step 6：汉语面板（逐字拼音）+ 语言感知诊断 |
| `832642f` | CC-CEDICT 真实词典接入 |
| `655919a` | 修 diagnosis/phrase 后端 `language=en` 硬编码 |
| `860a7df` | Step 5：汉语词典 provider |
| `c7634dd` | Step 4：去 `language=en` 硬编码 + import 语言检测 |

## Phase 2.6 收口要点（2026-06-23）

- **Step 6**：诊断在 application 层给 recognition barrier 叠加该语言 profile 的听辨因素
  （zh: 声调/词边界/同音/轻声/变调；en: 弱读/连读…），**明确标注"可考虑因素非检测"**（中文无
  音频分析，ADR 延后）；`DiagnosisHint` 加 `reasons`，`diagnosis-core` 保持语言无关。词面板加
  汉字逐字拼音分解（字→拼音/声调，零额外查询、按脚本门控）。
- **Step 7**：双语回归收敛为显式集 + 新增英汉词汇/来源快照**隔离 capstone**；写 `2.6-CLOSEOUT.md`，
  STATE/ROADMAP/REQUIREMENTS 标记 Phase 2.6 完成。
- 验证：workspace 279 + flutter 63 + contracts 全通过；英语回归基线不变。
- **仅留设计 seam**：LANG-004（听觉锚定观察）、LANG-009（L1 诊断 seam）；非英语音频→听觉单位
  生产属后续独立 production-engine program。

## 下一步候选（Phase 2.6 之外，由你定）

1. **Phase 2.3 真实媒体手动 QA**：用真实媒体跑 Manual Timeline Review 闭环，决定是否正式收口。
2. **中文学习活体验证**：起 app 用真实中文视频 + 字幕手点一遍（导入→点词→逐字拼音/释义→标状态→
   来源复听→诊断听辨因素），确认端到端体验（本阶段各环节已分别测试，未串起来手验）。
3. **provider research**：填充 licensed reviewed development cases，复跑 ZIPA/Wav2IPA/MFA benchmark。
4. **Phase 2.6 延伸**（若要继续多语言）：逐字"义"、学习语言用户手动选择 UI、能力矩阵 API 暴露、
   第三个语言（如 es/ja）压力测试抽象。

## 已就位的地基（Step 4 直接用，别重造）

- 语言 profile：`domain::profile_for(&LanguageCode) -> LanguageLearningProfile`
  （`crates/domain/src/language_profile.rs`）。未知语言干净降级。
- 语言感知分词：`subtitle_core::tokenize(language: Option<&LanguageCode>, text)`
  + `Tokenizer` trait（`crates/subtitle-core/src/lib.rs`）。`import()` 已按字幕轨语言分词。
- 词汇单位：`domain::LexicalUnit`（`crates/domain/src/lexical_unit.rs`），`identity()` 对英语
  word 粒度向后兼容旧 `WordProfileId`。Step 4/后续创建非英语词汇状态时用它的 identity。

## 必须遵守的已锁定不变量（ADR 0012 / 2.5.5）

- **理解轴是唯一不变量**：全局 `WordStatus`（domain）语言无关、不动；按语言变的是诊断 **reason**。
- **开放 taxonomy**：kind 用 namespaced string（`core.*` + `<lang>.*`），未知干净降级，禁止穷举 enum。
- **ListeningUnit = 视图**，不新建持久表；听力 observation 可锚定 ListeningUnit。
- **`normalized_key` 不透明**，无子串假设；LexicalUnit 粒度×归一两轴。
- **L1 seam**：诊断签名预留 `(L1, L2_unit, status)`，v1 不读、不落 schema。
- 英语行为是**回归基线**，不得回退。

## 环境注意

- **cargo 不在 PATH**：`export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"`。
- **沙箱默认无 crates.io**：拉新依赖需 `dangerouslyDisableSandbox`。jieba-rs 0.7.4 已在 Cargo.lock +
  缓存，故 `--offline` 构建可用。中文默认走 jieba；`--no-default-features` 走字级 fallback。
- **flutter 在** `$HOME/.local/share/flutter/bin/flutter`（已确认存在），Step 4 UI 改动可验证。

## 验证命令

```sh
export PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH"
cargo test --workspace --offline
cargo test -p subtitle-core --no-default-features --offline   # 字级 fallback 路径
$HOME/.local/share/flutter/bin/flutter analyze
$HOME/.local/share/flutter/bin/flutter test
./scripts/validate-contracts.sh
```

## 冷启动阅读顺序

1. `.planning/STATE.md`（当前位置 / 实现进度 / 下一步）
2. `.planning/phases/2.6-multilingual-learning-foundation/2.6-PLAN.md`（Step 4 细节 + Validated Foundation）
3. `docs/decisions/0012-multilingual-learning-abstraction.md`（不变量与约束）
