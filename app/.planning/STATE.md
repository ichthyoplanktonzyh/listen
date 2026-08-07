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

The app consumes only the pinned `listen-gen` release bundle: the bundle whose
bytes match the committed `listen_gen.lock.json` (manifest hash + artifact
size/hash), verified before every run, with machine events bound to the
verified tool version. No arbitrary `listen-gen` executable is honored.
On top of that, the daily-English workbench rebuild lands the rebuilt
workbench surface (discovery home, review deck, transcript and
sentence-analysis interactions) against typed fixtures.

## Open Questions

- Hosted Catalog/Registry 服务的归属仍未决定。
- `listen-gen` 的 private remote 已建（2026-08-04），但本地历史尚未 push，
  所以它的 commit 暂时仍无法被跨机器引用。

## Next

1. Observe the additive package path in the running app end to end.
2. Define the package discovery, lawful acquisition, match/generate/import,
   cancellation/retry, and explicit selection journey as an App phase.
3. Only afterward, migrate the old whole-media production path onto Gen; do not
   delete the existing implementation yet.
4. Use `CROSS_REPO.md` for Core, Gen, and future Catalog/Registry requests.
5. Handle formal release/installer delivery of the bundle in a separate PR (the
   `.pyz` is not yet packed into the shipped macOS app bundle).
