# Roadmap

## Current Baseline

- Flutter package version `0.7.0+8`;
- macOS-first desktop app with embedded `fvp`;
- 181 committed Dart test files;
- core contract `1.0.0` and runtime `0.7.0` pinned to
  `listen-core` commit `4f4bad8b97a651e1cb731bfccb8fd7e1c4645e0a`;
- standalone artifact install, Release build, and packaged smoke path.

## Near-term Maintenance

1. **App planning baseline** — 建立 Claude 可直接接手的独立 frontend project memory。
2. **Frontend fact audit** — 持续核对 130-test 代码面的真实用户 journeys 与遗留债务。
3. **Contract request discipline** — 所有 backend 需求先写 user journey、UI states 和信息需求。
4. **Local quality gate** — GitHub Actions 不可用期间保持 strict analyze/test/build/smoke。
5. **Standalone confidence** — 不依赖旧 monorepo 或 sibling core 完成日常开发。

## Product Work

当前 active product phase 是本地精确媒体 `.listenpkg` 往返：App-owned journey、
typed fixtures、Core import request 与 Gen process protocol 已落库。与 immutable Core
release 同步前，不更新 `backend.lock.json`，也不宣称 packaged end-to-end 已完成。
