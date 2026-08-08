# listen-app Agent Guide

单人项目，owner 独立开发。这份文件只写两类东西：**agent 自己查不到的硬约束**，
以及**推翻既有做法时需要知道的边界**。

其余一切——目录结构、代码放在哪、有哪些模块、各层怎么分——去读代码。
文档里的结构描述会随重构变质，读它不如 `ls` 一次。

## 开发文化

> 代码和文档是「当前最优解的快照」，不是承诺，不是宪法。

1. **事实 > 文档 > 决策记录。** 跑起来的代码和实测结果最权威，其次是描述现状的文档，
   最弱的是 ADR、历史 phase、handoff。用一份过期文档去反驳一个更好的方案，是无效论证。
   文档与现实不符时，文档是 bug——顺手改掉，不用立项。
2. **只有三类约束是真的**：物理与技术现实、说得出理由的业界最佳实践、以及外部世界的
   边界（见下）。其余全部可推翻——命名、分层、目录约定、既有模式、流程步骤。
   「项目里现在是这么写的」不构成理由。
3. **破坏性变更是廉价的。** 没有别的开发者需要迁移，没有外部使用者依赖内部 API。
   结构错了就重写，别在错的结构上打补丁。不需要兼容层、废弃期，或者
   「稳妥起见先加个开关」。
4. **要有主张。** 给出推荐并执行，不要罗列 A/B/C 让 owner 挑。发现更好的做法就说出来，
   哪怕它跟既有实现或文档冲突。「保守起见沿用了现有模式」是错误答案，
   除非你能说清现有模式确实更好。
5. **冲突就地解决。** 说明冲突点 → 给出更优的理由 → 直接实施 → 顺手更新被推翻的文档。
   只有两类事需要先停下来问：不可逆的外部动作，和产品方向的取舍。

## 硬约束


### 规则由测试执行，不由文档执行

间距、圆角、字号槽位、图标尺寸、断点、列宽、调色板、等待语言、异常文本泄漏、
CJK 字面量、分层依赖——这些都由 `test/*_discipline_test.dart` 和
`test/architecture_layering_test.dart` 可执行地守着。每个测试头部都写着它自己的
理由和触发它的真实事故。

**那些测试才是权威，不是这份文档。** 要知道规则，读测试；要改规则，改测试并写清理由。
不要在这里重复它们——第二份副本只会漂移。

### 通用 Flutter 技能：只有 preview 那条有用

`dart-flutter:*` 那组技能带的是外部默认值，不是本仓库的规矩。实测下来只有一条有增量：

- **`flutter-add-widget-preview` 值得跟。** 仓库用 `@Preview` 展示 discovery 各状态，
  而「新状态有没有 preview」没有测试守着——加了个诚实状态却不给它一张图，
  是最容易漏的一类。改 discovery UI 时把这条当收尾清单。
- **`flutter-apply-architecture-best-practices` 不要跟。** 它讲的分层仓库已经有了，
  且由 `architecture_layering_test.dart` 执行，比技能强；它多出来的部分要么违反闸门
  （示例 View 直接用 `CircularProgressIndicator`，`loading_discipline_test.dart` 当场红），
  要么是无谓改造（`freezed`/`built_value`、`get_it`、`lib/ui/features/` 目录）。
- 其余（静态分析、单测、pattern matching）被 AGENT.md 的验证命令和既有测试约定覆盖。

「通用技能里是这么写的」和「项目里现在是这么写的」一样，都不构成理由。

### 语言分离

UI 语言和学习语言是两回事。`lib/` 里不写死任何一种界面语言的句子：
用 `AppLocalizations.of(context).text('key')`，并在 `lib/localization.dart` 的
`_values` 里同时补上 `en` 和 `zh` 两条。

（`cjk_literal_discipline_test.dart` 只能抓住中文字面量，抓不住英文的——那一半靠自觉。）

### 外部边界

`backend.lock.json` 钉住 core 的 commit、契约版本、运行时版本、平台架构和 SHA-256。
这一头连着真实的二进制，不能随手改。（`url` 两个字段目前都是空的——产物不是从 URL
拉的，不可变性靠 sha256 兜着。）

```sh
python3 tool/backend_artifacts.py install
python3 tool/backend_artifacts.py verify
```

**跨仓状态永远当场读，不要相信任何文档里手抄的版本号或 commit：**

```sh
python3 tool/repo_status.py
```

它扫三仓的 lock 文件和 git 状态，去被钉的那个 commit 里把契约版本读出来跟 lock
对账，并报出消费方之间的分歧、未打 tag 的 pin、本地 checkout 落后等问题。
`--markdown` 输出可直接贴进 issue，`--strict` 有问题时非零退出。

- 不手改 `.backend/` 内容；不提交 `.backend/`、构建产物、下载的归档、凭据、本机路径。
- 契约定义、Rust 后端行为、`.listenpkg` schema、`listen-gen` 内部实现属于别的仓库。
  app 任务里不动它们——需要新数据就先用 typed fixture 顶着把 UI 做出来，
  之后 pin 一个 release 进来。

### 不可逆动作

不在 `main` 上开发，不 force-push `main`，不自行 merge PR，
不跑破坏性的恢复/清理命令。

## 验证

```sh
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest discover -s tool -p 'test_*.py'
```

`--fatal-infos --fatal-warnings` 不是可选的。改动 backend lock 或打包时另跑：

```sh
python3 tool/backend_artifacts.py verify
tool/build-macos-release.sh
tool/verify-macos-release.sh
```

**没有任何 CI 会跑。** GitHub Actions 账户欠费停用，且这个仓库当前也没有
`.github/workflows/`。上面这些就是全部的质量闸门，只在本地跑。

所以报告验证结果时给出确切的命令和输出行，不要含糊过去，更不要说「CI 会兜住」——
没有东西会兜住。一个没启动的 job 是基础设施故障，不是验证通过。

完整启动、pinned-release 测试、本地 core 联调、手动冒烟，见
`docs/development/full-app-local-testing.md`。

三仓真实 roundtrip 是显式、较重的门禁，不属于普通 `flutter test`：

```sh
LISTEN_CORE_REPO=/absolute/path/to/listen-core \
LISTEN_GEN_REPO=/absolute/path/to/listen-gen \
  tool/verify_local_content_package_roundtrip.sh
```

## 活文档 / 历史记录

会主动指向你的只有这几份：

- `CONTEXT.md` — 领域词汇表（Content Source / Edition / Rendition 等）
- `docs/development/` — 实操手册

`.planning/` 下的 phase、roadmap、handoff，以及 `docs/decisions/` 里的 ADR，是**历史记录**：
它们记录的是当时基于当时信息做的选择。可以当背景读，**不能当论据引用**。

根 `CHANGELOG.md` 只在发版时由 owner 整理一次，普通功能/修复/重构分支不要动它。
