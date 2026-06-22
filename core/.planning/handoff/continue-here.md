# Continue Here — Phase 2.6 Step 4

> 最后更新：2026-06-22 CST
> 单一接续入口（历史 handoff 见同目录 dated 文件，不必读）。

## 现在在哪

Phase 2.6（多语言学习基础，English + Chinese）进行中，**Step 1-3 已完成、已测试、已提交**，
工作区干净。下一步是 **Step 4**。

| 提交 | 内容 |
|---|---|
| `9c63464` | Step 3：LexicalUnit（粒度×归一、不透明 key） |
| `369d462` | Step 1-2：语言 profile + jieba 语言感知分词 |
| `9bdc599` | 多语言产品方向写入战略文档 + ADR 0012 |
| `74bb943` | Phase 2.5.5 语言学习抽象校验 |

## 下一步：Step 4 — 去除 `language=en` 硬编码

把学习语言从硬编码改为来自上下文。来源优先级（见 `2.6-PLAN.md` Step 4）：

1. 当前 active 字幕轨语言 → 2. 用户手动选择 → 3. 媒体/资源 metadata → 4. 安全 fallback `en`（UI 可改）。

重点路径：subtitle import language、vocabulary list language、dictionary lookup language、
word profile update language、source snapshot language、external vocabulary import default。

Exit criteria：同一 UI 能打开英语和汉语字幕并按不同语言查询词汇状态；`_sourceFor` 不再固定写
`language: en`。

起手定位：
```sh
grep -rn "language.*=.*en\|'en'\|\"en\"\|language=en" apps/desktop/lib | grep -i lang
grep -rn "language" apps/desktop/lib/services/api_service.dart
```
关键文件：`apps/desktop/lib/services/api_service.dart`、`apps/desktop/lib/main.dart`，以及
Rust 侧 `crates/application`（vocabulary / source snapshot 用例）和 `crates/api-http/src/routes`。

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
