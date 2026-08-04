# State

> 只写「现在在做什么、下一步是什么」。
>
> 跨仓 pin、契约/运行时版本、分支与 HEAD **一律不写在这里**——手抄的状态会漂，
> 而且漂了没有任何机制会发现（2026-08-04 实测：本文件曾声称 contract 1.0.0 /
> core `4f4bad8b`，而同仓的 `backend.lock.json` 已经是 1.1.0 / `b980a206`）。
>
> 要看当前状态，当场读：
>
> ```sh
> python3 tool/repo_status.py
> ```

## Current Work

Phase 001 implements the additive local content-package journey against typed
App fixtures: existing package selection, strict external `listen-gen`
orchestration, Core import receipt, honest provenance, cancellation/retry, and
explicit subtitle/word-timeline selection.

## Open Questions

- Hosted Catalog/Registry 服务的归属仍未决定。
- `listen-gen` 的 private remote 已建（2026-08-04），但本地历史尚未 push，
  所以它的 commit 暂时仍无法被跨机器引用。

## Next

1. Receive immutable Core and versioned Gen handoffs for the Phase 001 requests.
2. Sync the final fixtures, update `backend.lock.json` only for the immutable
   Core release, and run the three-repository fixture E2E plus packaged smoke.
3. Keep the existing whole-media flow until the additive package path has been
   integrated and observed end to end.
