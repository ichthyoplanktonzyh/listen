# Continue Here — Phase 2.6 Step 5

> 最后更新：2026-06-22 CST
> 单一接续入口（历史 handoff 见同目录 dated 文件，不必读）。

## 现在在哪

Phase 2.6（多语言学习基础，English + Chinese）进行中，**Step 1-4 已完成、已测试**，
工作区有 Step 4 改动**待提交**（见下）。下一步是 **Step 5**。

| 提交 | 内容 |
|---|---|
| （未提交） | Step 4：去 `language=en` 硬编码 + import 语言检测 |
| `9c63464` | Step 3：LexicalUnit（粒度×归一、不透明 key） |
| `369d462` | Step 1-2：语言 profile + jieba 语言感知分词 |
| `9bdc599` | 多语言产品方向写入战略文档 + ADR 0012 |
| `74bb943` | Phase 2.5.5 语言学习抽象校验 |

## Step 4 已完成（2026-06-22）

去除了学习语言硬编码，改为来自 active 字幕轨语言。落点：

- **后端 `subtitle_core::import`**：caller 未声明语言时按脚本检测（含汉字→`zh`，否则 `en`），
  用于分词与存储 `track.language`；声明的语言优先。English 回归基线不变。
  （`crates/subtitle-core/src/lib.rs` `detect_language` + 3 个 import 检测测试）
- **Flutter `SubtitleTrack` 模型**：新增 `language` 字段（后端早已序列化，之前 client 没读）。
- **`api_service.dart`**：`readWordProfiles / updateWordProfile / listVocabulary /
  importExternalVocabulary / lexicalEntries / lookupDictionary / normalizeLexical /
  correctLemma` 改为必填 `language` 命名参；`importSubtitle` 改为可选 `language`（null→后端检测）。
- **`main.dart`**：新增 `_learningLanguage` 解析器（`primaryTrack?.language ?? 'en'`），
  串到所有 word-profile/vocab/dict/phrase 调用与 `_sourceFor`；`VocabularyScreen` /
  `LearningAssetsScreen` 接收 `language`。`m18_ui` 短语 upsert 从 `source['language']` 取语言。

Exit criteria 已满足：同一 UI 打开汉语字幕→jieba 分词、`track.language=zh`、按 zh 查询词汇/字典；
英语仍走 en；`_sourceFor` 不再固定写 `language: en`。

仍未做（属 Step 4 计划但本阶段不强求的 P2/P3 来源）：用户手动语言覆盖 UI、媒体 metadata 来源——
已在 `_learningLanguage` 注释处留 seam。

## 下一步：Step 5 — Chinese Dictionary And Pronunciation Provider

接入最小汉语 provider（见 `2.6-PLAN.md` Step 5）：中文词/字查询、拼音、声调、基础释义，
可选 HSK/频率/词性。数据先用本地小 fixture，许可证后续定。

Exit criteria：点击中文 token 能显示拼音和释义；provider 缺失时不影响字幕播放与词汇状态。

起手定位：
```sh
grep -rn "dictionary\|pronunciation" crates/api-http/src/routes/*.rs
ls crates/dictionary-provider/src 2>/dev/null; grep -rn "Provider" crates/application/src/dictionary.rs crates/application/src/pronunciation.rs
```
关键文件：`crates/dictionary-provider`、`crates/application/src/{dictionary,pronunciation}.rs`、
`crates/api-http/src/routes/{dictionary,pronunciation}.rs`，client `WordLearningPanel`。

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
