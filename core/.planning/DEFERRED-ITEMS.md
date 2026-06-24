# 残留 / 延后项总览

> 最后更新：2026-06-24 CST
> 用途：跨阶段残留项汇总，供后续 phase 规划参考。每项标注来源阶段、优先级和推进条件。

## 优先级说明

- **P1**：有明确产品价值，下一批 phase 推进
- **P2**：有价值但不紧急，等相关工作启动时顺带
- **P3**：长期 seam / 研究项，需要时再做

---

## 一、英语真实语流分析 [P1]

> 推进阶段：Phase 2.10

| # | 项目 | 来源 | 现状 | 目标 |
|---|------|------|------|------|
| E1 | PhoneTimeline release provider 选型 | Phase 2.5 | 无 release provider；候选 MFA/ZIPA/Wav2IPA/Allosaurus 均未过 benchmark | 选出一个 phone recognizer，通过质量门禁 |
| E2 | 语流规则从"文本预测"升级为"音频检测" | Phase 2.5/2.7 | `analyze_rules()` 全是 `LikelyByContext`/`PossibleByRule` | 弱读/省音/闪音有音频层证据支撑 |
| E3 | Phone alignment benchmark 复跑 | Phase 2.5 | research infrastructure 已验证，但未用真实 development cases 跑过 | 至少 10 条 development cases 通过 quality gate |
| E4 | 真实语流保真度审查 | Phase 2.5 | provider 不能把弱读/省音规范化回字典发音后仍声称 detected | 人工 precision review 高置信 findings |

### 推进条件

- Phase 2.5 的 `2.5-BENCHMARK.md` 质量门禁是入口标准
- 已有 research infrastructure：`phonetic-eval.py`、`phonetic-research-adapter.py`、evaluation catalog
- PhoneTimeline 资源契约已就绪（Phase 2.5），app 端可消费

---

## 二、架构优化 [P1]

> 推进阶段：Phase 2.11

| # | 项目 | 来源 | 现状 | 目标 |
|---|------|------|------|------|
| A1 | LANG-004 听觉锚定观察 | Phase 2.6 | ListeningUnit 为视图概念，观察仍锚定词 | 观察可锚定 ListeningUnit（R1 修订） |
| A2 | LANG-009 L1 诊断 seam | Phase 2.6 | `(L1, L2_unit, status)` 签名在设计层预留，未进入 `diagnose` 代码 | 诊断函数签名支持可选 L1 参数 |
| A3 | 能力矩阵 API 暴露 client | Phase 2.6 | 面板用脚本门控 | 后端暴露语言能力矩阵，client 按能力显示/隐藏功能 |
| A4 | 学习语言来源优先级 | Phase 2.6 | active 字幕轨语言 → en fallback | 支持用户手动选择 + 媒体 metadata 两个来源 |
| A5 | identity 边界 profile 化 | Phase 2.6 ja | `normalize_lemma` 约 6 处对 en/zh/ja 行为等价 | 归一逻辑走 profile，支持大小写敏感语言 |
| A6 | domain `lib.rs` 拆分 | Phase 2.3.5 | 约 1317 行，Phase 2.3.5 判定暂不作为前置项 | 按领域拆分为独立 module |

### 推进条件

- 不改变已有产品行为（英语 + 中文回归基线）
- A1/A2 依赖真实声音侧（E1-E4）有一定进展后才有实际效果
- A3 可独立推进

---

## 三、中文相关 [P3]

| # | 项目 | 来源 | 现状 | 推进条件 |
|---|------|------|------|---------|
| C1 | 中文 forced aligner | Phase 2.9 | MMS_FA/MFA 不支持中文；FunASR 可选 | ASR timestamps 已够用，优先级低 |
| C2 | CC-CEDICT 多音词 | Phase 2.6 | 取第一条读音，逐字"义"未做 | 用户实际遇到多音词问题时推进 |
| C3 | 中文声调检测 | Phase 2.6 | 无音频层声调分析 | 需要中文音频分析 provider |
| C4 | 中文语义 chunk | Phase 2.9 | 英语走 COCA/PHRASE，中文走纯声学 | 需要中文短语/搭配词表 |

---

## 四、日语相关 [P3]

| # | 项目 | 来源 | 现状 | 推进条件 |
|---|------|------|------|---------|
| J1 | 日语生产管线 | Phase 2.9 | `word_timeline: Unsupported` | 需 tokenizer + 声学模型 |
| J2 | 日语活用形归并 | Phase 2.6 ja | surface-first，食べる/食べた 不归并 | provider 供归一 key 流过 `tokenize()` |
| J3 | 纯 kanji 无 kana 语言检测 | Phase 2.6 ja | 纯汉字行仍判 zh | 需真正的 language-id provider |
| J4 | EDICT2 资源注册 | Phase 2.6 ja | seed 15 词已有 | 钉死 commit + sha256，像 CC-CEDICT |

---

## 五、小项 [P2]

| # | 项目 | 来源 | 现状 |
|---|------|------|------|
| M1 | GUI `--asr` 下拉选择 | Phase 2.9 | 当前 CLI only |
| M2 | Phase 2.3 正式收口 | Phase 2.3 | 手动 QA 已通过，待写 closeout |
| M3 | hi (Devanagari abugida) 书写轴验证 | Phase 2.5.5 | 列为下一个探针 |
