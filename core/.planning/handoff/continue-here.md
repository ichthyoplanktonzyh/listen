# Continue Here — Phase 2.6 Step 6

> 最后更新：2026-06-22 CST
> 单一接续入口（历史 handoff 见同目录 dated 文件，不必读）。

## 现在在哪

Phase 2.6（多语言学习基础，English + Chinese）进行中，**Step 1-5 已完成、已测试**，
Step 5 + 两处补强**待提交**（见下）。下一步是 **Step 6**。

| 提交 | 内容 |
|---|---|
| （未提交） | CC-CEDICT 真实词典接入 |
| （未提交） | 修 diagnosis/phrase 后端 `language=en` 硬编码 |
| `860a7df` | Step 5：汉语词典 provider（点中文 token 出拼音+释义） |
| `8133ab9` | 清理：删除死代码 `normalizeLexical` |
| `c7634dd` | Step 4：去 `language=en` 硬编码 + import 语言检测 |
| `9c63464` | Step 3：LexicalUnit（粒度×归一、不透明 key） |

## Step 5 + 补强已完成（2026-06-22）

汉语词典走既有 provider 接口接入，点中文 token 出拼音 + 释义；并补掉 Step 4 漏的后端硬编码。

- **真实词典 CC-CEDICT**：`ChineseDictionaryProvider` 读安装的 CC-CEDICT `.u8`（约 12 万词条，
  缓存加载，镜像 ECDICT loader），解析 `繁 简 [pin1 yin1] /释义/` 并把数字拼音转调号（`u:`→`ü`、
  轻声、大写专名、a/e/ou/末元音规则），简繁双查；25 词种子降为离线兜底。注册进学习资源目录
  （`m18.rs` catalog，钉死镜像 commit + 真实 SHA-256，CC-BY-SA 4.0），像 ECDICT 一样可安装。
  已用真实 118k 词条文件冒烟验证（你好/咖啡/量子力学/中国/行 等）。**已知局限**：多音词取第一条。
- **后端 `language=en` 硬编码已修**：`diagnose_sentence` / `phrase_candidates` 原写死 `en`，
  现经 `sentence_language`（→ 新仓储方法 `sentence_track_language`，JOIN `subtitle_tracks.language`，
  默认 `en`）按句子所属轨语言查 profile。已加测试证明中文诊断读 zh profile、en 不泄漏。
- **provider 注册/派发/拼音载体/面板**：同前——`dictionaries` vec 注册、`lookup_dictionary` 按
  `supported_languages` 派发、拼音走 `DictionaryLookup.phonetics`、`WordLearningPanel` 隐藏空 IPA 区。

Exit criteria 已满足：点中文 token → 词典区显示拼音 + 释义（装了 CC-CEDICT 即全量、否则种子兜底）；
未命中干净降级、不影响播放/词汇状态；中文诊断读对语言。

可改进（非阻塞）：`_openWord` 仍会对中文调英语 `lookupPronunciation` 并缓存空结果（已被面板隐藏、
英汉缓存不冲突，无害）。CC-CEDICT 装载依赖第三方镜像仓库存续（钉死 commit→文件不可变；仓库若被删
则安装 404、provider 回落种子，干净降级）。多音词只显示第一条读音。

## 下一步：Step 6 — Chinese Learning Panel And Diagnosis

为汉语定义最小学习体验（见 `2.6-PLAN.md` Step 6）：

- 面板：字/词、拼音、声调、释义、来源原句、状态切换。
- 诊断初版 reason（per-profile，**非新增状态枚举**——状态枚举语言无关、复用）：不认识词/字、
  认识但没听出、词边界切分困难、声调/轻声、同音上下文。诊断 reason taxonomy 用开放 namespaced
  string（`zh.tone_confusion` / `zh.word_boundary` / `zh.homophone` 等，见 ADR 0012 §5 / R0）。

Exit criteria：外国人学汉语基础路径成立（打开中文媒体→导入中文字幕→点词→看拼音/释义→标记状态→
来源复听）；面板解释音节/声调到词义映射，不简化为英文式 lemma 查询。

起手定位：
```sh
grep -rn "diagnose\|diagnosis" crates/application/src/diagnosis.rs crates/api-http/src/routes/dictionary.rs
grep -rn "profile_for\|diagnosis_rules\|reason" crates/domain/src/language_profile.rs
```
关键文件：`crates/application/src/diagnosis.rs`、`crates/domain/src/language_profile.rs`（zh profile 的
`diagnosis_rules`/`sound_features`）、client `WordLearningPanel` + 诊断展示、`_refreshDiagnosis`。
注意 zh profile 已声明 `pronunciation: zh.pinyin`、`sound_features: [zh.tone, zh.neutral_tone,
zh.tone_sandhi, zh.erhua]`、`diagnosis_rules` 含 tone_confusion/word_boundary/homophone 等。

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
