# 残留 / 延后项总览

> 最后更新：2026-06-25 CST
> 用途：跨阶段残留项汇总，供后续 phase 规划参考。每项标注来源阶段、优先级和推进条件。

## 优先级说明

- **P1**：有明确产品价值，下一批 phase 推进
- **P2**：有价值但不紧急，等相关工作启动时顺带
- **P3**：长期 seam / 研究项，需要时再做

---

## 一、英语真实语流分析 [P1]

> 推进阶段：Phase 2.10（集成已完成，待端到端验证）

| # | 项目 | 来源 | 现状 | 目标 |
|---|------|------|------|------|
| E1 | 端到端真实音频验证 | Phase 2.10 Step 5 | ⏳ 代码已就绪，待下载模型后用真实媒体测试 | App 内完整跑通：音频→CTC→IPA 显示→finding 分类 |
| E2 | 真实语流保真度审查 | Phase 2.5 | ⏳ 依赖 E1 完成后人工审查 | 人工 precision review 高置信 findings |

### 推进条件

- E1：App 设置 → Audio analysis models → 下载，或命令行 `./scripts/setup-phoneme-model.sh`
- E2：E1 通过后，人工检查弱读/省音/闪音 finding 的 precision

### 已完成（本轮关闭）

- ~~PhoneTimeline release provider 选型~~：✅ fb-espeak 选定（PER=30.5%, Apache 2.0）
- ~~语流规则从"文本预测"升级为"音频检测"~~：✅ CTC 管线已集成
- ~~Phone alignment benchmark~~：✅ 10 条 TIMIT cases，6 候选已 benchmark

---

## 二、架构优化 [P1]

> 推进阶段：Phase 2.11（Steps 1-3 已完成）

| # | 项目 | 来源 | 现状 | 目标 |
|---|------|------|------|------|
| A1 | LANG-004 听觉锚定观察 | Phase 2.6 | ⏳ Phase 2.11 Step 4，依赖 2.10 验证 | 观察可锚定 ListeningUnit（R1 修订） |
| A2 | LANG-009 L1 诊断 seam | Phase 2.6 | ⏳ Phase 2.11 Step 5，依赖 2.10 验证 | 诊断函数签名支持可选 L1 参数 |
| A3 | identity 边界 profile 化 | Phase 2.6 ja | Phase 2.11 Step 6，低优先 | 归一逻辑走 profile，支持大小写敏感语言 |

### 推进条件

- A1/A2：Phase 2.10 E1 验证通过后可推进
- A3：等实际碰到大小写敏感语言问题时推进

### 已完成（本轮关闭）

- ~~能力矩阵 API~~：✅ Phase 2.12 完成（profile 驱动门控）
- ~~学习语言来源优先级~~：✅ Phase 2.11 Step 2 完成
- ~~domain lib.rs 拆分~~：✅ Phase 2.11 Step 3 完成（1317→194 行，13 模块）

---

## 三、Phase 2.3 收口 [P2]

| # | 项目 | 来源 | 现状 | 目标 |
|---|------|------|------|------|
| Q1 | Phase 2.3 正式收口 | Phase 2.3 | 手动 QA 已通过，待写 closeout 文档 | 写 closeout、更新 STATE.md 标记完成 |

---

## 四、中文相关 [P3]

| # | 项目 | 来源 | 现状 | 推进条件 |
|---|------|------|------|---------|
| C1 | 中文 forced aligner | Phase 2.9 | MMS_FA/MFA 不支持中文；FunASR 可选 | ASR timestamps 已够用，优先级低 |
| C2 | CC-CEDICT 多音词 | Phase 2.6 | 取第一条读音，逐字"义"未做 | 用户实际遇到多音词问题时推进 |
| C3 | 中文声调检测 | Phase 2.6 | 无音频层声调分析 | 需要中文音频分析 provider |
| C4 | 中文语义 chunk | Phase 2.9 | 英语走 COCA/PHRASE，中文走纯声学 | 需要中文短语/搭配词表 |

---

## 五、日语相关 [P3]

| # | 项目 | 来源 | 现状 | 推进条件 |
|---|------|------|------|---------|
| J1 | 日语生产管线 | Phase 2.9 | `word_timeline: Unsupported` | 需 tokenizer + 声学模型 |
| J2 | 日语活用形归并 | Phase 2.6 ja | surface-first，食べる/食べた 不归并 | provider 供归一 key 流过 `tokenize()` |
| J3 | 纯 kanji 无 kana 语言检测 | Phase 2.6 ja | 纯汉字行仍判 zh | 需真正的 language-id provider |
| J4 | EDICT2 资源注册 | Phase 2.6 ja | seed 15 词已有 | 钉死 commit + sha256，像 CC-CEDICT |

---

## 六、小项 [P2]

| # | 项目 | 来源 | 现状 |
|---|------|------|------|
| M1 | GUI `--asr` 下拉选择 | Phase 2.9 | 当前 CLI only |
| M2 | ONNX 量化模型（fb-espeak） | Phase 2.10 | 当前 ~1.26GB PyTorch；ONNX 可降至 ~300MB |
| M3 | hi (Devanagari abugida) 书写轴验证 | Phase 2.5.5 | 列为下一个探针 |
