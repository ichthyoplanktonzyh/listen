# LLPlayerNext — 文档体系维护规则

> 最后更新：2026-06-18
> 基于 GSD 文件结构体系，结合本项目实践制定

---

## 一、文件职责速查

| 文件 | 更新频率 | 职责 | 语气 |
|---|---|---|---|
| `CHANGELOG.md`（根目录） | 每次提交 | 记录做了什么。历史账本。 | 事实陈述 |
| `STATE.md` | 每个 phase 完成时 | 记录现在在哪、下一步干什么。项目活记忆。 | 情境描述 |
| `PROJECT.md` | 产品方向变化时 | 战略描述：愿景、定位、原则、非目标 | 宏观 |
| `REQUIREMENTS.md` | 需求增删改时 | 战术描述：可实施、可测试的需求项 | 精确 |
| `ROADMAP.md` | 路线调整时 | 阶段管理：里程碑划分、优先级、依赖关系 | 规划 |
| `MILESTONES.md` | 里程碑完成时 | 已完成里程碑的索引汇总（不搬内容，只链接） | 归档 |

## 二、目录职责

### `.planning/` — 项目管理中枢

| 目录 | 存放内容 | 生命周期 |
|---|---|---|
| `phases/XX-phase-name/` | phase 的计划、上下文、验证、总结。**一个 phase 一个文件夹，内聚完整。** | 完成 → 冻结 |
| `codebase/` | 系统架构骨架：ARCHITECTURE / STACK / DATA-MODEL / TESTING。**帮助新会话快速建立全局理解。** | 随架构演进更新 |
| `discuss/` | 自由讨论。可能是灵感、技术调研、方案对比。**不要求结构规范。** | 落地 → 迁入对应 phase；纯参考 → 保留 |
| `handoff/` | 会话交接记录。**精简为上，STATE.md 已承载大部分交接信息。** | 按需创建 |
| `design-notes/`（phase 级子目录） | 该 phase 推进中产生的设计笔记、方案讨论、参考材料。**是 phase 的上游输入。** | phase 完成 → 冻结 |

### `docs/` — 长期参考（面向外部/最终用户）

| 目录 | 存放内容 | 规则 |
|---|---|---|
| `decisions/` | ADR（架构决策记录）。编号、不可变。 | 新增决策 → 追加编号 |
| `release/` | 发布说明、安装指南、已知问题。 | 每次发布追加 |
| `verification/` | M1.x 验证报告。 | ❄️ 已冻结 |
| `planning/` | M1.x 里程碑计划。 | ❄️ 已冻结 |
| `development/` | 开发流程参考（git 工作流、功能测试）。 | 流程变化时更新 |

---

## 三、Phase 生命周期

### 3.1 创建 phase

```bash
# 约定：phase 目录名 = 编号 + 短横线 + 功能描述
.planning/phases/X.X-feature-name/
```

### 3.2 phase 标准文件

```
X.X-feature-name/
├── X.X-PLAN.md          ← 执行计划（必须）
├── X.X-CONTEXT.md       ← 上下文：从哪些讨论来、关键决策（按需）
├── X.X-SUMMARY.md       ← 完成总结（完成时必须）
└── design-notes/        ← 上游设计参考（按需）
```

### 3.3 phase 完成流程

1. 所有任务完成，测试通过
2. 撰写 `X.X-SUMMARY.md`
3. 更新 `STATE.md`（当前状态、下一步）
4. 更新 `MILESTONES.md`（如果是里程碑收口）
5. **phase 文件夹冻结**，不再修改

### 3.4 长期子系统（如 timeline-production）

- 在 phase 目录下拥有独立的内部结构
- 不受 phase 完成冻结约束（持续演进）
- 内部文件的增删改由子系统自行管理
- 重大结构变化需同步更新 `codebase/ARCHITECTURE.md`

---

## 四、文档迁移规则

### 何时迁移

| 场景 | 操作 |
|---|---|
| `discuss/` 中的讨论落地为正式 phase | 链接或提炼到 phase 的 CONTEXT.md，原文保留在 discuss/ |
| 功能设计文档需要从 `docs/features/` 归入 phase | 移入 phase 的 `design-notes/` |
| 新的 phase 开始 | 从 discuss/ 和旧 phase 中收集相关上下文 |

### 何时不动

| 场景 | 规则 |
|---|---|
| 已完成的 M1.x 文档 | ❄️ 冻结不动。MILESTONES.md 提供索引链接。 |
| ADR（`docs/decisions/`） | 编号不变。新增决策用新编号。 |
| 根目录 `CHANGELOG.md` | 持续增量追加。不迁移。 |

---

## 五、禁止事项（反模式）

| 反模式 | 正确做法 |
|---|---|
| ❌ 把实现细节写入 PROJECT.md | 战略级描述，不涉及具体实现 |
| ❌ 同一 milestone 的文档散落在 3 个目录 | 一个 phase 的所有产物放在一个 phase 文件夹下 |
| ❌ 修改已冻结的 phase 文件 | 冻结即历史事实。新发现写入新 phase 的 CONTEXT.md |
| ❌ STATE.md 写得像 CHANGELOG | STATE 是当前状态机，不是历史列表 |
| ❌ codebase/ 写成了 README 的翻版 | codebase/ 是架构骨架（数据模型+依赖图+边界+测试体系），不是使用说明 |
| ❌ timeline-production 的目录直接塞入外部讨论文件 | 讨论文件放入 phase 级的 `design-notes/` |
| ❌ handoff 文件堆积过多 | 精简为一个 `continue-here.md`，核心交接信息已在 STATE.md 中 |

---

## 六、日常维护 checklist

### 每次提交
- [ ] `CHANGELOG.md` 增量更新，精确时间戳

### 每次 phase 完成
- [ ] 撰写 `X.X-SUMMARY.md`
- [ ] 更新 `STATE.md`：当前位置、下一步、最近决策
- [ ] 更新 `MILESTONES.md`（如果涉及里程碑收口）

### 产品方向/需求变化
- [ ] 更新 `PROJECT.md`（战略层面）
- [ ] 更新 `REQUIREMENTS.md`（战术层面）
- [ ] 更新 `ROADMAP.md`（阶段重排）
- [ ] 在 `STATE.md` 中记录变化摘要和时间戳

### 架构变化
- [ ] 更新 `codebase/ARCHITECTURE.md`（crate 依赖图、数据流、边界）
- [ ] 更新 `codebase/STACK.md`（新增/替换依赖）
- [ ] 如需新增 ADR → `docs/decisions/NNNN-description.md`

### 新会话启动
1. 先读 `STATE.md` — 了解当前在哪
2. 再读 `codebase/ARCHITECTURE.md` — 了解系统骨架
3. 然后 `codebase/STACK.md` + `codebase/DATA-MODEL.md`
4. 最后按需深入具体 phase 文件夹
