# 跨仓请求模板

真正的工作项是**目标仓库的 GitHub issue**。这份文件不是需要遵守的流程，
是写那个 issue 时的检查清单——照着填，填完贴过去，本仓只留一个链接和本地集成状态。

当前谁钉了谁的哪个 commit，跑脚本当场看，不要手抄到任何文档里：

```sh
python3 tool/repo_status.py
```

## 硬规则

这几条不是清单，是约束：

- 不共享分支，不依赖同级 checkout，不 fetch 移动的 core `main`。
- 未发布的契约一律不当作稳定。
- app 不 import gen 的 Python 内部实现，只通过版本化的 CLI/协议调用它。
- 范围、兼容性、发布时机的冲突由 owner 裁决。

## 给 listen-core 的契约请求

规范 API、校验、持久化、包导入、激活选择、学习记录相关的请求提给 core。
不要改本地或同级的 `contracts/openapi/v1.yaml`。

```markdown
### 用户旅程与可见结果
### 涉及的界面/组件，以及全部 UI 状态
### 需要的字段、操作、过滤与排序
### loading / empty / error / cancel / retry / 部分结果 的语义
### 预期频率、数据量、延迟
### 隐私、用户权限、provenance 要求
### 媒体/包/凭据/进程/临时文件的归属与清理
### 兼容性、版本、幂等、迁移预期
### 代表性的 mock 请求与响应
```

包导入类请求还要写清：fingerprint 与 Timeline 兼容规则、原子性与幂等、
candidate 与 active 的行为差异、大小与路径权限上限、以及脱敏后的稳定失败形态。

## 给 listen-gen 的生成请求

> ⚠ gen 的 private remote 已建（`ichthyoplanktonzyh/listen-gen`，2026-08-04），
> 但本地历史尚未 push，所以 issue 流暂时还没真正可用。

媒体预处理、provider、离线生成、确定性包输出、进度、取消、CLI/协议相关的请求提给 gen。

```markdown
### 可执行文件与协议的兼容性
### provider 配置与凭据权限
### 进度与取消语义，含子进程清理
### 输入媒体与输出包的归属
### 确定性、脱敏、依赖闭合的输出要求
### 不花费付费额度的 fake/fixture 验证方式
```

gen 返回：版本化的 CLI 或协议、支持的包契约版本、失败与退出语义、
确定性 fixture、发布/安装说明。

## 给 Catalog / Registry 的请求

> ⚠ **该服务及其仓库归属尚未决定。** 不要默认指派给 App、Core 或 Gen。

请求必须保持发现、播放、合法媒体获取三者分离（尤其是 YouTube），并定义分页、
缓存、离线与不可用状态、可变元数据与不可变摘要的区别、信任与许可 provenance、
以及该服务缺席时的本地直接导入行为。

## core 回什么

- 规范 method/path 与 schema；
- 兼容性分类与契约版本；
- 实现与失败/生命周期语义；
- release tag、确切 core commit、产物 URL 与 SHA-256；
- 迁移或废弃说明。

app 侧完成握手 = 提交更新后的 `backend.lock.json`、同步的 fixture manifest、
客户端/契约测试，以及集成与打包冒烟证据。
