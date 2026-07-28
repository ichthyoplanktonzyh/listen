# Subtitle Resource Semantics And Lifecycle

更新时间：2026-06-20 CST

## Core Semantics

在 LLPlayerNext 消费端，字幕资源是一类统一资源，而不是按文件扩展名分裂的功能：

- `.srt`
- `.vtt` / WebVTT
- `.lltimeline.json`
- ASR 生成字幕轨
- 未来其他带句级、词级、音素级或 chunk timeline 的字幕格式

这些资源都回答同一个问题：当前媒体播放时，消费端应该按什么文本和时间轴驱动字幕、
词级高亮、chunk 展示、phone 高亮和后续学习交互。

不同格式只代表能力不同：

| 资源类型 | 基础消费 | 词级消费 | chunk 消费 | phone 消费 |
| --- | --- | --- | --- | --- |
| SRT / WebVTT | 句级字幕 | 估算词级 timing | 基于估算 timing 降级分块 | 不可用，除非另有分析 |
| whisper.cpp / ASR 字幕 | 句级字幕 | 使用 ASR reported timing 或降级估算 | 基于 ASR timing 分块 | 不可用，除非另有分析 |
| LLTimeline JSON | 句级字幕 | 优先使用 active WordTimeline 精确 timing | 基于 active WordTimeline 分块，后续可升级为 active ChunkTimeline | 若存在 PhoneTimeline 则消费，否则降级 |

## Persistence

导入资源必须进入本地 SQLite，而不是只存在于 Flutter 内存中。

主要表：

- `media_items`
- `subtitle_tracks`
- `subtitle_sentences`
- `word_timeline_runs`
- `lltimeline_resources`
- `word_timings` legacy compatibility cache

当前媒体的字幕资源管理页面通过 API 从数据库读取：

```text
GET /v1/media/{media_id}/subtitles
GET /v1/subtitles/{track_id}/word-timings
GET /v1/subtitles/{track_id}/word-timelines/summary
GET /v1/subtitles/{track_id}/lltimeline/export
```

生命周期操作也必须回写数据库：

```text
POST   /v1/subtitles/{track_id}/archive
POST   /v1/subtitles/{track_id}/restore
DELETE /v1/subtitles/{track_id}
GET    /v1/subtitles/{track_id}/export.srt
```

## Attachment Rules

`.lltimeline.json` 是交换资源，不应硬绑定生产端本机的 media id、track id 或 path。

导入到当前媒体时：

- 当前媒体 fingerprint 匹配：直接挂载。
- fingerprint 不匹配：提示用户确认；用户确认后仍可挂载。
- 挂载时重映射本机 track / sentence / WordTimeline id，避免数据库冲突。
- 保留原始 media id / fingerprint / path / title 作为 provenance。
- 同一媒体下相同字幕 fingerprint 再次导入时复用已有 track id，避免重复导入导致资源不可见。

## Consumption Path

激活字幕资源后，播放器消费链路必须刷新：

```text
activate subtitle resource
  -> set primary track
  -> load active WordTimeline / legacy word timings
  -> load chunk partitions
  -> load phonetic analyses when available
  -> refresh current cue / word / chunk / phone state
```

各能力独立降级：

- word timing 失败不应抹掉句级字幕。
- chunk partition 失败不应抹掉词级高亮。
- phone analysis 失败不应抹掉字幕或 chunk。
- pronunciation provider 失败不应阻断 active timeline 消费。

## UI Contract

字幕资源管理是顶层资源管理页面，行为应类似词汇本：

- 顶部 AppBar 提供 `字幕资源` 入口。
- 页面展示当前媒体关联的所有字幕资源。
- 每个资源展示来源、状态、句数、词级/chunk/phone 能力。
- 支持导入 SRT/WebVTT 和 LLTimeline JSON。
- 支持刷新、激活、归档、恢复、删除、导出。
- 当前右侧 Transcript 面板只负责消费 active 字幕资源，不承担完整资源管理职责。

## Development Guardrail

桌面开发时必须确认运行的是包含最新迁移的 sidecar。

2026-06-20 曾出现 `target/release/api-http` 旧二进制优先于新 `target/debug/api-http` 被
启动，导致真实数据库停在 `user_version=9`，缺少：

- `word_timeline_runs`
- `lltimeline_resources`
- `subtitle_tracks.status`

修复后：

- release sidecar 已重新构建；
- 真实本地数据库已迁移到 `user_version=12`；
- 开发 sidecar 查找顺序改为 debug 优先于 release。

快速核对：

```sh
sqlite3 "$HOME/Library/Application Support/LLPlayerNext/llplayernext.sqlite" \
  "pragma user_version; select count(*) from lltimeline_resources; select count(*) from word_timeline_runs;"
```
