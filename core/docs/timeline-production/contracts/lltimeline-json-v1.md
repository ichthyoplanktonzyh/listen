# LLTimeline JSON v1 Contract

更新时间：2026-06-18 15:11:06 CST

`LLTimeline JSON v1` 是生产端与轻量消费端之间的时间轴资源交换格式。
它以 OpenAI/WhisperX 常见的 segment/word 结构为骨架，增加 LLPlayerNext
需要的 provenance、资源版本、音素扩展、chunk timeline 和评估 artifact。

## Schema Identity

- 文件扩展名：`.lltimeline.json`
- schema id：`llplayer.timeline.v1`
- 兼容策略：v1 读入方必须忽略未知字段；必须拒绝未知主版本。
- 时间单位：毫秒，整数，半开区间语义 `[start_ms, end_ms)`。

## Top-Level Shape

```json
{
  "schema": "llplayer.timeline.v1",
  "metadata": {
    "created_at_ms": 1781776266000,
    "generator": {
      "id": "llplayernext",
      "version": "0.5.0",
      "mode": "production_engine"
    },
    "media": {
      "id": "media-id",
      "fingerprint": "sha-or-existing-fingerprint",
      "path": "/path/to/video.mp4",
      "title": "CNN10 sample",
      "duration_ms": 600000
    },
    "language": "en",
    "human_reviewed": false
  },
  "segments": [],
  "word_timelines": [],
  "active_word_timeline_id": null,
  "phone_timelines": [],
  "active_phone_timeline_id": null,
  "chunk_timelines": [],
  "active_chunk_timeline_id": null,
  "artifacts": []
}
```

## Metadata

Metadata 必须回答“这个资源如何生成、适用于哪个媒体、是否经过人工确认”。

最低要求：

- `created_at_ms`
- `generator.id`
- `generator.version`
- `generator.mode`
- `media.id`
- `media.fingerprint`
- `media.title`
- `language`
- `human_reviewed`

未来生产端应继续扩展：

- ASR 模型、aligner、VAD、人声分离、diarization 的 provider/version/config hash。
- benchmark/evaluation summary。
- parent resource id 和人工校正审计信息。

## Segments

Segments 代表字幕句/段，消费端可以用它重建基础字幕。

```json
{
  "id": "sentence-id",
  "index": 0,
  "start_ms": 1200,
  "end_ms": 4200,
  "text": "This is a sample.",
  "display_text": "This is a sample.",
  "tokens": [
    {
      "index": 0,
      "kind": "word",
      "text": "This",
      "normalized": "this",
      "start_char": 0,
      "end_char": 4
    }
  ]
}
```

## Word Timelines

一个资源文件可以包含多个候选 word timeline。消费端默认使用
`active_word_timeline_id` 指向的 timeline。

Word timeline 直接复用当前 domain 中的核心字段：

- `id`
- `track_id`
- `media_id`
- `algorithm_id`
- `algorithm_version`
- `config_hash`
- `parent_timeline_id`
- `created_by`
- `status`
- `metrics_json`
- `words`
- `created_at_ms`
- `updated_at_ms`

Word item 最低字段：

```json
{
  "sentence_id": "sentence-id",
  "token_index": 0,
  "text": "This",
  "normalized": "this",
  "type": "word",
  "start_ms": 1200,
  "end_ms": 1340,
  "confidence": 0.94,
  "timing_source": "forced_aligned",
  "provider_id": "whisperx",
  "provider_version": "large-v3-wav2vec2"
}
```

### Word Type

`type` 用于把 chunk 划分相关的非词声学事件放进同一条时间轴：

- `word`
- `silence`
- `breath`
- `noise`
- `music`
- `speaker_change`

当前 Rust `WordTiming` 还没有 `type` 字段，因此第一步导出兼容包时默认视为
`word`。后续进入生产端重管线时再把该字段提升为一等 domain model。

## Phone Timelines

v1 必须预留 phone timeline：

- 可以挂在 word 下。
- 也可以独立成为 `phone_timelines`，通过 word id 或 sentence/token index 关联。
- 没有 phone timeline 不影响消费端使用 word timeline。

## Chunk Timelines

Chunk timeline 是学习播放资源，不是临时计算结果。它可以由算法生成，也可以由人工
合并/拆分后保存。

最低字段：

- `id`
- `word_timeline_id`
- `algorithm_id`
- `created_by`
- `status`
- `chunks`

Chunk item 最低字段：

- `index`
- `start_ms`
- `end_ms`
- `text`
- `sentence_ids`
- `word_refs`
- `evidence`

## Artifacts

Artifacts 用于保存生产和评估副产物：

- VAD segments
- speaker turns
- vocal isolation report
- alignment diagnostics
- benchmark report
- manual correction audit

## v1 Implementation Slice

第一批代码实现：

- Rust domain contract。
- 从现有 subtitle track + active/candidate `WordTimeline` 导出 LLTimeline document。
- 将 LLTimeline document 导入为 media、subtitle track 和 word timeline resources。
- `phone_timelines`、`chunk_timelines`、`artifacts` 为空数组。

这样现有 ASR 管线可以先成为新资源系统的一个 candidate generator。
