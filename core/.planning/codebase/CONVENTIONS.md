# LLPlayerNext — 项目级代码约定

> 最后更新：2026-06-18
> 回答"怎么写"。编码风格由 `rustfmt.toml` / `flutter analyze` 强制，本文件记录工具管不到的架构级约定。

---

## 1. Crate 依赖规则

### 依赖方向（严格单向）

```
domain  ←  api-events
  ↑          ↑
subtitle-core  diagnosis-core  speech-analysis
  ↑          ↑                  ↑
  └──────────┼──────────────────┘
             ↓
        application  ←  api-events
          ↑     ↑
persistence-sqlite  dictionary-provider
          ↑     ↑
          └─────┼──────────
                ↓
             api-http (binary)
```

### 硬规则

- **`domain` 不得依赖任何 workspace crate**，只允许 `serde`、`sha2`、`thiserror` 等基础外部库
- **`application` 是编排枢纽**：所有跨 crate 的用例逻辑必须在此层，HTTP handler 不直接调用 `speech-analysis` 模块函数
- **`api-http` 是唯一二进制 crate**：其他 crate 均为 library
- **新增 crate 必须向 `application` 注册**：新建的 capability crate 通过 `AppServices` trait 暴露

### Cargo.toml 约定

- 共享依赖版本号定义在 workspace `[workspace.dependencies]` 中
- 各 crate 使用 `dep.workspace = true` 引用，不写版本号
- dev-dependencies 无需共享版本号（criterion / proptest）

---

## 2. 错误处理

### 模式

- 所有 crate 使用 `thiserror` 派生自定义错误枚举
- 公开 API 返回 `Result<T, CrateNameError>`
- 错误类型命名：`DomainError`、`SubtitleError`、`PersistenceError` 等

```rust
// domain/src/lib.rs
#[derive(Debug, Error)]
pub enum DomainError {
    #[error("Empty value for {0}")]
    EmptyValue(&'static str),
}

// 使用
pub fn parse(value: impl Into<String>) -> Result<Self, DomainError> { ... }
```

### 规则

- 不要使用 `Box<dyn std::error::Error>` 作为公开 API 的返回类型（`main.rs` 除外）
- 不要在 library crate 中使用 `unwrap()` / `expect()` — 用 `?` 传播
- 错误信息应包含足够的上下文（哪个字段、哪个操作），不暴露敏感数据

---

## 3. 异步约定

### Runtime

- 全项目统一使用 **Tokio multi-thread runtime**
- 异步 trait 使用 `#[async_trait]` 宏（`async-trait` crate）

### 规则

- application 层的 trait 方法可以是 async（通过 `#[async_trait]`）
- persistence 层的方法可以是 sync 或 async，取决于 IO 模式
- 不要在 async 上下文中调用 `std::thread::sleep`，使用 `tokio::time::sleep`
- 不要在 sync 函数中调用 `tokio::spawn` — 使用 `tokio::task::spawn_blocking` 包装 CPU 密集型工作

---

## 4. API 设计（axum）

### 路由组织

```rust
// crates/api-http/src/lib.rs — 集中注册
pub fn router(state: ApiState) -> Router {
    Router::new()
        .route("/v1/transcription/...", post(...))
        .route("/v1/phonetic/...", get(...))
        // ...
        .with_state(state)
}

// 具体 handler 按功能拆分到独立文件
// crates/api-http/src/transcription.rs
// crates/api-http/src/phonetic_analysis.rs
// crates/api-http/src/m18.rs
// crates/api-http/src/speech_jobs.rs
```

### 规则

- 路由前缀：`/v1/<resource>/<action>`
- 认证：Bearer token 中间件，随机生成 token 通过 stdout JSON 传递给 Flutter
- 所有 handler 注入 `State<ApiState>`，ApiState 持有 `AppServices`
- SSE 事件通过 `api-events` crate 的 Schema 定义

---

## 5. 数据持久化

### SQLite 约定

- 使用 `rusqlite` bundled feature（SQLite 随二进制编译）
- 迁移文件在 `crates/persistence-sqlite/src/lib.rs` 中按版本号线性组织
- 新增迁移规则：
  - 递增版本号（当前最高 0010）
  - 新增迁移不修改已有迁移代码
  - 迁移前自动备份数据库文件
- 涉及用户数据的写操作必须使用事务

### 类型 ID

- 所有实体 ID 使用 `domain::string_id!` 宏生成强类型包装：
  ```rust
  string_id!(MediaItemId);
  string_id!(SubtitleSentenceId);
  string_id!(WordTimelineId);
  // ...
  ```
- ID 值本身通过 SHA-256 内容指纹派生，保证幂等（`from_fingerprint`）

---

## 6. Flutter 约定

### 状态管理

- 使用 `ChangeNotifier` + `InheritedWidget`（不引入 Riverpod/Bloc 等外部框架）
- 控制器命名：`XxxController`（`PlayerController`, `SubtitleController`, `LearningController`, `SettingsController`）
- 所有控制器通过 `AppControllers` InheritedWidget 注入，不在 widget 中直接实例化

### 数据模型

- 使用 `factory Xxx.fromJson(Map<String, dynamic> json)` 模式反序列化
- 模型类不可变（`final` 字段），状态变更通过控制器

### 与 Rust 通信

- 通过 `ApiService`（HTTP REST to `127.0.0.1:{port}/v1/*`）
- SSE 事件通过 `EventSource` 流式接收
- 不硬编码端口 — 从 Rust stdout JSON handshake 读取
- 不直接调用 Python 脚本 — 通过 Rust transcription coordinator

---

## 7. Python 管线约定

### CLI 入口

- Python 脚本通过 `argparse` 提供子命令（`doctor`, `prepare`, `run-whisperx`, `produce`）
- Rust 通过 `ProductionToolManager` 调用 Python CLI，不直接 import Python 模块

### venv 管理

- 不同功能的 venv 隔离：`timeline-production/`、`forced-align/`、`zipa/`
- 每个 venv 有独立 `setup-venv.sh` 和 `requirements.txt`
- Python 脚本开头检查 venv 存在性，不存在时给出安装提示而非直接报错

### 容错

- 对齐失败不得破坏已有 transcript（回退到 DTW 时间戳）
- 所有中间产物写入临时目录，完成后再移动到最终位置

---

## 8. 测试约定

### Rust

- 单元测试：`#[cfg(test)] mod tests { }` 与源码同文件
- 集成测试：`crates/<crate>/tests/<name>_test.rs`
- 属性测试：`subtitle-core` 使用 `proptest`
- 性能基准：`crates/<crate>/benches/<name>_bench.rs`（criterion）
- Fuzz：`cargo +nightly fuzz run <target>`

### Flutter

- 测试文件：`apps/desktop/test/<name>_test.dart`
- 使用 `flutter_test` 内置 `test()` / `expect()`

### 运行

- 提交前至少运行 `scripts/test.sh --quick`
- PR 前运行 `scripts/test.sh --full`

---

## 9. 序列化与契约

### LLTimeline JSON v1

- Schema 版本：`llplayer.timeline.v1`
- 不兼容字段变化必须提升 schema 版本号
- 新增字段使用 `#[serde(default)]` 保证向后兼容

### API 契约

- HTTP API 响应格式保持向后兼容
- 事件类型变更需同步更新 `api-events` crate
