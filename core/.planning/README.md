# listen-core Planning

这里是 `listen-core` 的当前项目记忆，只维护后端、合约、生产管线和 runtime
artifact 的事实。

## 新会话读取顺序

1. `STATE.md`
2. `PROJECT.md`
3. `MAINTENANCE.md`
4. `codebase/ARCHITECTURE.md`
5. `codebase/STRUCTURE.md`
6. `codebase/TESTING.md`
7. 当前 active phase

## 当前与历史

- 根级 planning 文件、`codebase/`、`phases/`：当前 `listen-core` 事实。
- `archive/monorepo-baseline/`：拆仓时保存的旧 monorepo planning，全量冻结。
- 旧文档中的 Flutter 路径、测试数量、单仓流程不再是当前规则。

`listen-app` 维护自己的 `.planning`。跨仓信息只用 release、commit、contract
version、issue 或 PR 链接引用，不复制对方 roadmap。
