# Continue Here — Phase 2.6 Step 7

> 最后更新：2026-06-22 CST
> 单一接续入口（历史 handoff 见同目录 dated 文件，不必读）。

## 现在在哪

Phase 2.6（多语言学习基础，English + Chinese）进行中，**Step 1-6 已完成、已测试**，
Step 6 **待提交**（见下）。下一步是 **Step 7（双语回归 + 收口）**——Phase 2.6 最后一步。

| 提交 | 内容 |
|---|---|
| （未提交） | Step 6：汉语面板（逐字拼音）+ 语言感知诊断 |
| `832642f` | CC-CEDICT 真实词典接入 |
| `655919a` | 修 diagnosis/phrase 后端 `language=en` 硬编码 |
| `860a7df` | Step 5：汉语词典 provider |
| `c7634dd` | Step 4：去 `language=en` 硬编码 + import 语言检测 |

## Step 6 已完成（2026-06-22）

汉语学习面板 + 语言感知诊断。落点：

- **诊断听辨因素（possibilities，非检测）**：`application::diagnose_sentence` 给 recognition barrier
  叠加该语言 profile 的 `diagnosis_reasons`（zh: tone_confusion/word_boundary/homophone/neutral_tone/
  tone_sandhi；en: weak_form/linking/…）。`diagnosis-core` 保持语言无关（reason 在 application 层叠），
  `DiagnosisHint` 新增 `reasons`（serde default）。**中文无音频分析（ADR 0012 延后），所以是"可考虑
  因素"而非检测**——UI 明确标注"非检测结果"。profile 驱动，英语也受益、无 `if zh`。
- **词面板逐字拼音分解**：多字 Han 词把每个字与拼音音节对齐（字→拼音/声调），纯从词典拼音切分、
  零额外查询、按脚本（多字 Han）门控而非语言。空 IPA 区仍隐藏。
- **client**：`diagnosis_card` 渲染 reason（`l.diagnosisReason()`，未知 reason 回落原名，干净降级）；
  localization 加 en/zh reason 标签 + `字`/`possibleListeningFactors`。OpenAPI `DiagnosisHint` 加 `reasons`。
- 测试：application `recognition_barrier_carries_the_language_listening_reasons`；widget `diagnosis_card`
  reason 渲染 + `word_learning_panel` 逐字拼音。

Exit criteria 已满足：学汉语闭环成立（导入中文字幕→点词→逐字拼音+释义→标记状态→来源复听）；面板讲
音节/声调→词义，非英文式 lemma 查询；诊断给中文听辨因素。

**未做（刻意，非过度工程）**：中文专属音频/声调检测（production-engine 范畴，ADR 延后）；逐字"义"
（只做了逐字"音"，逐字释义需 N 次查询）；能力矩阵 API 暴露给 client（面板的脚本门控暂够用）。
未跑活体 UI 点选（后端 SQLite 集成测 + client widget 测 + 契约校验已覆盖各环节）。

## 下一步：Step 7 — Tests And Closeout（Phase 2.6 收尾）

见 `2.6-PLAN.md` Step 7。新增双语 fixtures 与回归，并写收口文档：

- fixtures：英语既有 + 中文简单字幕 + 中英混排字幕。
- 测试：tokenizer contract、词汇语言隔离、dictionary provider 语言路由、source snapshot 语言正确、
  中文 token click 的 UI smoke。（多数已有零散覆盖，Step 7 收敛成显式回归集 + 收口。）
- 文档：更新 ROADMAP / REQUIREMENTS / STATE，写 `2.6-CLOSEOUT.md`。

Exit criteria：英语全回归通过；汉语最小学习闭环通过；文档更新。

起手定位：
```sh
ls .planning/phases/2.6-multilingual-learning-foundation/   # 看是否已有 CLOSEOUT 模板（参考 2.5 收口）
grep -rn "zh\|chinese\|咖啡" apps/desktop/test crates/*/src/tests.rs   # 盘点已有双语测试
```
关键：把分散在 subtitle-core/dictionary-provider/persistence-sqlite/flutter 的中文测试梳理成 Phase 2.6
回归清单；按 2.5 的 CLOSEOUT 体例收口。

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
