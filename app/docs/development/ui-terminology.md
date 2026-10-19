# UI Terminology

Which terms stay English in the Chinese interface, and which get translated.
Reference for `lib/localization.dart` and for the gate in
`test/cjk_literal_discipline_test.dart`. Issue [#7].

## Why this file exists

`Listening Inbox` shipped with the English source string in the `zh` table, so
a Chinese interface read 「Listening Inbox」 directly beside 「泛听进行中」 and
「还没有标记的泛听片段」. The owner ruled it a missed translation on 2026-07-28
and it is fixed — but the ruling also noted that `Timeline`, `provider` and
`Whisper` sit in the same grey area, and that without a written rule the
argument restarts every time somebody adds a key.

So the rule is written down once here. This file is descriptive of the decisions
already embedded in `localization.dart` where they were consistent, and
prescriptive where they were not.

## The rule

**A term stays English only when translating it would send the learner looking
for something that does not exist.** That is a narrow test, and it is
deliberately narrower than "it is a technical word".

Three things pass it:

1. **Product and company names** — what the vendor calls itself, in the script
   the vendor uses. A learner reading our UI may have to find the same name in a
   vendor console, a pricing page or an error message.
2. **File formats, wire types and identifiers** — a name that appears in a
   filename, a payload, or a path the learner can see.
3. **Language endonyms** — a language names itself in its own script in every
   locale.

Everything else is copy, including every word that merely *sounds* technical. A
feature this app invented is not a proper name just because it was first written
in English.

## Stays English

| Term | Why | Where |
| --- | --- | --- |
| `Whisper` | OpenAI's model name. 「本地 Whisper 转写」 tells the learner which engine produced the transcript, and that name is what they would search for. | `realtimeTurnLearnerOutput`, `realtimeDebriefLearnerLabel`, `realtimeHonestLayering` |
| `OpenAI`, `Qwen`, `Model Studio` | Vendor and product names. | `llm_provider_settings.dart`, `realtime_provider_settings.dart` |
| `百炼` | Model Studio's **Chinese** product name — how Alibaba Cloud's own console spells it. Kept in the English interface for the same reason `Whisper` is kept in the Chinese one. | `realtime_provider_settings.dart` |
| `LLTimeline`, `WordTimeline` | Resource/type names that appear in exported filenames and in payloads. Note the contrast with `timeline` below: the *format* keeps its name, the *concept* does not. | `importLLTimeline`, `exportLLTimelineJson`, `statusManualReviewNoTimeline` |
| `JSON`, `SRT`, `VTT`, `PCM`, `ms` | Formats and units. | throughout |
| `fingerprint`, `correlation id` | Identifiers the learner may have to quote in a bug report. `correlation id` is rendered through `realtimeFailureReference` so the label around it is translated. | `resourceFingerprintMismatch`, `realtimeFailureReference` |
| `中文`, `日本語`, `한국어` | Language endonyms. | `settings_dialog.dart`, `subtitle_resource_manager_panel.dart` |

The last two rows are also the exemption list inside
`test/cjk_literal_discipline_test.dart`. Adding a proper name there means adding
a row here.

## Gets translated

| Term | Chinese | Note |
| --- | --- | --- |
| `timeline` (the concept) | 时间轴 | `activeTimeline` → 当前时间轴. The app's own word for word-level timing, not a vendor's. |
| `provider` | 服务 / 语音服务 / 服务方 | Context-dependent and correctly so: 「AI 服务」 in settings, 「语音服务断开了连接」 in a notice, 「服务方字幕」 when contrasting it with the local transcript. `provider` is a role, and roles are copy. |
| `Listening Inbox` | 泛听收集箱 | Owner ruling 2026-07-28. A feature surface this app invented. |
| `inbox`, `session`, `turn`, `debrief`, `stage`, `lobby` | 收集箱 / 会话 / 轮 / 结束页 / 舞台 / 门厅 | Same reason. None of these is a name anybody outside this repository uses. |
| Backend enum values (`completed`, `failed`, `template_visible`, …) | described, never printed | Not a translation question at all: a raw enum on screen is debug output (charter P4). They map to a sentence through a `switch`, and an unrecognised value degrades to a generic sentence rather than surfacing the token. |

## Still undecided

One inconsistency this rule exposes but does not resolve, left for the owner
rather than changed unilaterally in an i18n slice:

- `statusTimelineResourceRefreshed` is `'Timeline 资源已刷新'` in the `zh`
  table, while `activeTimeline` is `'当前时间轴'`. By the rule above the status
  line should read 「时间轴资源已刷新」. It is a visible string on the player's
  main screen, so changing it is a copy decision, not a typo fix.

## Adding a key

1. Write both tables. A key present in `en` and missing in `zh` silently falls
   back to English, which is how `Listening Inbox` survived — the fallback in
   `AppLocalizations.text` is a safety net, not a translation.
2. Do not paste the English string into the `zh` table to satisfy the fallback.
   If a term genuinely stays English, add it to "Stays English" above with a
   reason, so the next reader does not have to guess whether it was a decision
   or an oversight.
3. Interpolate with `{name}` placeholders and `replaceAll`, never by
   concatenating a translated fragment with a value — word order differs
   between the two languages.
4. Never interpolate a caught exception into either table. See
   `test/error_leak_discipline_test.dart`.

[#7]: https://github.com/ichthyoplanktonzyh/listen-app/issues/7
