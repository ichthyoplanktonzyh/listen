# LLPlayerNext 项目交接：2026-06-11

本文档是新线程恢复项目工作的首要入口。所有判断以 Git 当前状态和本文档
列出的提交为准，不依赖旧对话上下文。

## 1. 当前结论

- 已发布版本：`v0.5.0`，Milestone 1.7 本地 ASR。
- 当前开发阶段：Milestone 1.8 `0.6.0` 验收候选。
- M1.8 自动验收已经通过，但完整人工验收尚未明确收口。
- 不得创建 `v0.6.0` 标签，直到用户明确确认 M1.8 人工验收通过。
- 不得开始实施 M1.9，直到用户确认 M1.8 收口。
- Windows、Linux、移动端仍不属于当前阻塞范围。

## 2. 权威 Git 状态

交接时的当前分支：

```text
test/software-rendering-m1.8
```

当前提交：

```text
b2419e5 Disable hardware acceleration (workaround for Xcode 26.5 OpenGL issue)
```

提交关系：

```text
a32fb8e  v0.5.0 / main
  └─ 24292f1  Implement Milestone 1.8 acceptance candidate
      └─ 954b9c6  Harden Milestone 1.8 acceptance candidate
          └─ b2419e5  Disable hardware acceleration
```

重要分支：

- `main`：停留在 `v0.5.0`，尚未包含 M1.8。
- `test/software-rendering-m1.8`：当前应作为继续验收和 handoff 的权威分支。
- `codex/milestone-1.8-learning-quality`：包含提交 `dc859be` 的条件挂载
  `Video` 尝试。该尝试不是最终黑屏根因修复，不应直接作为后续基线。
- `fix/black-screen-conditional-video`：另一项围绕 Widget 生命周期的实验，
  也不是最终根因修复。

新线程开始后，先执行：

```sh
cd /Users/shadow/LLPlayerNext
git switch test/software-rendering-m1.8
git status
git log --oneline --decorate -5
```

在用户确认当前软件渲染版本无误后，应将 `b2419e5` 的方案整理进正式 M1.8
分支，再决定 M1.8 的最终收口提交；不要直接合并实验分支中的其他黑屏尝试。

## 3. 黑屏问题与当前兼容决策

### 已确认根因

黑屏并非下午新增的短语、OpenSubtitles 或词典发音业务代码导致。

已确认的问题链路：

```text
Xcode 26.5
  -> clean build 重新编译 media_kit_video 原生框架
  -> TextureHW.swift 的 macOS OpenGL 硬件渲染路径异常
  -> 播放正常但视频纹理输出黑帧
```

关键证据：

- 曾经正常的旧提交在 clean build 后同样黑屏，排除业务代码回归。
- 设置 `enableHardwareAcceleration: false` 后视频恢复正常。
- Xcode 26.5 安装前的增量缓存产物可以正常工作。
- macOS 26.2 更早已经使用，不能解释当天才出现的问题。

### 当前正式兼容策略

当前代码在 `apps/desktop/lib/player_adapter.dart` 中使用：

```dart
VideoControllerConfiguration(
  enableHardwareAcceleration: false,
)
```

这会绕过 `media_kit_video` 的 OpenGL 硬件纹理路径，使用软件渲染。当前优先级
是可靠显示视频，代价是 CPU 使用率提高，尤其可能影响 4K、高帧率和长时间播放。

### 后续处理边界

- M1.8 保持软件渲染默认值。
- 不再通过条件挂载 `Video`、修改播放器 Stack 或依赖旧增量缓存规避问题。
- 后续单独跟踪 `media_kit_video`、Flutter macOS Texture、Xcode 26.5 和 Metal
  路径的上游进展。
- 只有 clean build、4K、字幕覆盖、跳转和长时间播放均通过后，才能恢复硬件
  加速默认值。
- 未来可以提供“兼容模式（软件渲染）/ 实验性硬件加速”设置，但不是当前
  M1.8 收口的必要条件。

## 4. M1.8 已实现能力

M1.8 代码主要位于提交 `24292f1`、`954b9c6` 和 `b2419e5`。

### 统一学习资产

- SQLite schema v7。
- 使用统一 `LexicalEntry` 表示单词和用户确认的短语。
- 单词与短语独立保存状态、历史、释义、笔记和多个来源句。
- 词汇资产包 v3。
- 当前 v3 重复导入会保留本机较新状态，独立合并学习内容、历史和来源。

### Lemma、固定搭配与离线资源

- Provider 中立的 `LexicalNormalizationProvider`。
- 确定性英文规则、用户修正和可选 ECDICT 数据。
- 用户修正造成资产冲突时返回明确冲突，不静默覆盖。
- ECDICT 和 CMUdict 可显式下载、checksum 校验和删除。
- 固定搭配候选来自内置规则和已安装 ECDICT。
- 当前句中的候选短语使用字幕下方横线展示。
- 点击单词文字仍打开单词学习；点击横线选择整个短语。
- 短语必须由用户确认状态后才进入学习资产。

### OpenSubtitles

- Provider 中立的字幕搜索边界，首个实现为 OpenSubtitles.com。
- 支持标题、文件名和 OpenSubtitles 媒体 hash 搜索。
- 支持下载并导入主字幕或副字幕。
- 主、副字幕菜单均有搜索入口。
- 缺少媒体或 API key 时会明确提示和引导。
- 认证失败、限流和服务错误具有结构化错误，不阻断播放器。

### 词典发音

- `DictionaryPhonetic` 支持可选 `audio_url`。
- Free Dictionary API 会保留其返回的发音音频资源。
- 学习面板音标旁展示发音按钮。
- 发音使用独立播放器，不应替换或暂停当前视频。

### 自动验证

在提交 `954b9c6` 上已经通过：

- Rust workspace tests、format、clippy。
- Flutter analyze 和 widget tests。
- 契约校验。
- M1、M1.5、M1.6、M1.7、M1.8 历史回归。
- macOS 构建与打包 smoke test。

软件渲染提交 `b2419e5` 已由用户实测确认能恢复视频画面。新线程应以用户实际
验证为准继续完成 M1.8 人工验收。

## 5. 当前安装包

交接时磁盘上的安装包：

```text
/Users/shadow/LLPlayerNext/dist/LLPlayerNext-macos-arm64.zip
```

交接时 SHA-256：

```text
443f26ac1194b3712b20660db9466b3cf0caceb92f940219499b29a4b4eaf4e1
```

该安装包由软件渲染分支构建。任何重新构建都会改变 checksum，新线程不得继续
引用该 checksum，除非重新计算确认。

## 6. M1.8 尚未完成的工作

M1.8 当前状态仍是“等待协同人工验收”，不是发布完成。

必须由用户确认的重点：

1. 软件渲染下本地视频、音频、跳转、循环和双字幕正常。
2. 4K 或高码率材料的 CPU 占用和播放流畅度可以接受。
3. 字幕短语横线、单词点击、短语确认和独立状态正常。
4. OpenSubtitles 使用用户真实 API key 可搜索并导入主、副字幕。
5. 词典发音按钮可播放，且不打断视频。
6. ECDICT、CMUdict 的安装、删除和离线降级正常。
7. 当前 v3 资产导出、恢复和重复导入正常。
8. ASR、设置、中英文切换和旧桌面功能没有回归。

详细清单见：

```text
docs/verification/milestone-1.8-acceptance.md
```

用户确认后才可以：

- 更新验收报告为完成；
- 创建 M1.8 收口提交；
- 创建 `v0.6.0` 标签；
- 开始实施 M1.9。

## 7. M1.9 建议起点

M1.9 的方向是“发音与词级同步基础”，不是直接实现真实语流分析。

在开始编码前，新线程应先与用户确认并形成正式 M1.9 计划。建议范围：

- 建立 Provider 中立的 pronunciation/phoneme 数据契约。
- 首版以美式英语为默认，但保留语言、口音和音素体系扩展字段。
- 使用 CMUdict 或可替换 G2P Provider 生成规范发音。
- 内部优先使用 ARPAbet，UI 可映射显示 IPA。
- 为整句生成规范音标，并保留音标到字幕 token 的映射。
- 建立词级时间对齐 Provider 边界。
- 优先使用已有 ASR word timestamps；必要时研究 WhisperX、Montreal Forced
  Aligner、aeneas 等方案。
- 在字幕中实现当前单词随播放位置高亮或跳动。
- 用确定性规则展示弱读、连读、缩约和常见音变提示。
- 规则分析必须明确标注为“预测/规范规则”，不能冒充真实音频检测结果。
- 所有发音与对齐结果应可缓存，并记录 Provider、版本和模型 provenance。

M1.9 明确不包括：

- 真实音频到实际音素序列的模型；
- 稳定的真实弱读、省音、同化检测；
- 音素级实时跳动；
- M2.0 的模型训练和真实语流分析。

## 8. M2.0 建议起点

M2.0 的方向是“真实语流分析”。该阶段应基于 M1.9 已建立的 token、词级时间轴、
音素契约和 UI，而不是另起一套结构。

建议研究与实施顺序：

1. 定义真实语流分析 Provider、模型和 provenance 契约。
2. 评估音频到音素的模型，例如 Wav2Vec2Phoneme、Allosaurus、CharsiuG2P 等。
3. 生成实际音素序列和时间位置。
4. 将实际音素与字幕词和规范音素进行动态规划对齐。
5. 输出规范音素、实际检测音素、差异类型和置信度。
6. 再逐步实现音素级跳动、弱读、省音、同化等真实检测。

关键风险：

- 许多 Speech-to-IPA 模型会输出规范化发音，而非真实语流细节。
- 高质量自然语流实际音素标注数据稀缺。
- 实际音素序列与字幕单词的稳定对齐比生成音素本身更困难。
- UI 必须区分规范规则、模型预测和高置信真实检测。

详细讨论资料：

```text
discuss/pronunciation-rules-and-connected-speech-references.md
discuss/real-connected-speech-analysis-and-speech-to-ipa.md
```

## 9. 架构与开发约束

- 新仓库固定为 `/Users/shadow/LLPlayerNext`。
- Clean-room 重构，不复制旧 GPL LLPlayer 源码。
- 当前只承诺 macOS Apple Silicon，但公共领域契约保持平台无关。
- SQLite、播放器、字幕、ASR、词典、发音和对齐的公共契约不得暴露具体第三方
  库类型。
- 原始媒体和字幕可以消失；学习资产、状态、历史和来源快照必须持久存在。
- 播放位置、字幕同步、循环和后续词级同步继续在客户端本地执行。
- 不要覆盖用户现有数据或未提交改动。
- 不要创建 `v0.6.0` 标签，除非用户明确确认 M1.8 验收完成。

## 10. 新线程启动清单

新线程收到项目后应按顺序执行：

1. 阅读本文档。
2. 阅读 `docs/verification/milestone-1.8-acceptance.md`。
3. 阅读两个 `discuss/` 发音与真实语流讨论文件。
4. 确认当前分支为 `test/software-rendering-m1.8`。
5. 确认用户是否已经完成 M1.8 软件渲染版本人工验收。
6. 若 M1.8 尚有问题，仅修复 M1.8，不开始 M1.9。
7. 若用户明确确认 M1.8，通过正式收口流程后再规划 M1.9。

