# listen 设计宪章

> 本文件是 listen 前端设计的**唯一事实来源**（single source of truth），由
> [#28 设计主线](https://github.com/ichthyoplanktonzyh/LLPlayerNext/issues/28) 固化落库。
> 后续所有设计/UX slice 的验收都要逐条对照本宪章，而不是只看「编译过、测试绿」。
>
> 视觉气质定稿：[`listen-visual-identity.html`](./listen-visual-identity.html)

## 名字就是简报

产品名 **`listen`**（小写、单词、无标点）。这个名字本身是设计简报：

- 最轻的祈使句——不喊、不催，只是邀请；
- **双向倾听**——用户听内容，产品听用户（对话后处理出的词汇画像）；
- 耳朵为中心，拒绝吵闹的游戏化。

## 一句话气质

> **一个正在专注倾听你的、安静的房间。**

灯是调暗的——不是黑，是墨绿炭。发光的只有声音、词、和用户自己的语言；其余一切往后退。

## 五条可检验原则

每个设计/UX 改动都继承这五条，验收时逐条对照。

1. **暗，但不是黑** —— 底色墨绿炭，暗色优先；亮色是备选皮肤，不是灵魂。
2. **退后，让内容发光** —— 外壳（rail / 播放栏 / AppBar / 侧栏）安静，只有声音、词、画面
   在发光；全仓仅有的 3 处 `CustomPaint`（词级高亮、连读带、节奏带）是光源，不是装饰。
3. **在场，但不催促** —— 系统对用户的了解永远等用户自己去看，从不推送、弹窗、愧疚、连胜。
4. **诚实的仪器，不是讨好的玩具** —— 精确、描述性、从不作假；频率低 ≠ 不会用，只叫
   「练习靶子」。
5. **永远做减法** —— listen 天生文字密集（字幕/转写/词/句），美学的首要职责是**降低疲劳**：
   高易读、留呼吸、一次只讲一件事。每加一处强调，先问：它是内容吗？它该亮吗？

## 底色定义 · 墨绿炭

| 角色 | 值 | 出处 |
| --- | --- | --- |
| 设计稿底色（墨绿炭） | `#1a2420` | `listen-visual-identity.html` |
| 实现底色 `darkFog` | `#1b2422` | `apps/desktop/lib/theme/listen_theme.dart`（≈ 设计稿，视为等价） |
| 信号青（设计稿） | `#4db8a8` | 内容发光色；实现现值 `darkPrimary #5cc6b8`，是否校准归 Slice 2 裁决 |
| 琥珀强调 | `#e6b45c` | 设计稿与实现 `darkAccent` 完全相同 |
| 月白 | `#c7d4cf` | 对方的声音／照进来的光（owner 2026-07-23，#70 对话页拍板；进 palette 纪律测试） |

**暗色为家**：app 开箱默认即暗色（`themeMode = 'dark'`）；`system` / `light` 保留为用户
显式选项，且已显式选择过的用户永不被翻转。

## 舞台态 · stage mode

> owner 2026-07-23 拍板升格（#70 对话页设计，首例：实时对话 Live 态；
> 操作性定义详见 [`listen-live-conversation.html`](./listen-live-conversation.html)）。

安静的房间偶尔要熄灯：全屏沉浸的**实时**场景（用户正在用声音与系统互动）进入
「舞台态」，是原则 2「退后，让内容发光」的极限形——

1. **全暗场**：外壳全退，底色压至 `ground2`（比安静房间再暗半档）；
2. **唯一光源**：屏上只有正在发生的内容大形在发光（它是内容，所以配得上光）；
3. **色的角色**：用户的声音＝信号青（最亮时刻），对方的声音＝月白，
   琥珀只留给练习靶子时刻——正在说话的人不被标注；
4. **文字最小化**：舞台上至多一行余音字幕（说完淡出，不留历史，不滚动）；
   全文对读归事后页。用户自己的话在舞台上不上屏（provider 实时转写只是 guidance，
   诚实分层）；
5. **门厅→舞台两段进场**，退出走确认动线；**不联动系统全屏**（F 归播放器，#25 边界不动）。

## 关键裁决（避免走回头路）

- **B「书房/文学」方向已排除**：文字密集界面再叠阅读负担 = 疲劳，违反原则 5。
- **A「录音棚」与 C「精密仪表」合流**：A 是氛围（暗、静、内容发光），C 是骨架（诚实、
  精确、上网格），二者不冲突，合成当前气质。
- **本重构不是重新配色**：暗色 scaffold 已是 `darkFog`（≈ 目标墨绿炭），琥珀完全相同。
  重心在「暗色为家 + 外壳退后/内容发光 + 语流带重做 + token」。
- **语流/节奏带是既有功能的重做，不是新功能**：呈现改动不得改产品语义（见 AGENT.md
  「算法与指标」纪律）。
- **暗/亮岔路已定**（owner 2026-07-21）：暗色为灵魂、亮色为备选；「先暗色，不是黑」。

## 执行索引

| Slice | Issue | 内容 |
| --- | --- | --- |
| 1 | [#29](https://github.com/ichthyoplanktonzyh/LLPlayerNext/issues/29) | 宪章落库 + 暗色为家（本文件即其产物） |
| 2 | [#30](https://github.com/ichthyoplanktonzyh/LLPlayerNext/issues/30) | 外壳退后、内容发光（强调层重排） |
| 3 | [#31](https://github.com/ichthyoplanktonzyh/LLPlayerNext/issues/31) | 语流/节奏带重设计（视觉签名） |
| 4 | [#32](https://github.com/ichthyoplanktonzyh/LLPlayerNext/issues/32) | wordmark + 排版/间距/圆角/动效 token（并入 [#26](https://github.com/ichthyoplanktonzyh/LLPlayerNext/issues/26)） |

执行纪律：独立分支、每 commit 同步 CHANGELOG、`flutter analyze` 零告警、
`listen_theme_test` / `theme_palette_discipline_test` 保持绿灯。
