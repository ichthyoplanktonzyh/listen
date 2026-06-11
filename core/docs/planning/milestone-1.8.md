# Milestone 1.8: Core Learning Quality and Desktop Product Hardening

Milestone 1.8 is the `0.6.0` acceptance candidate. It introduces a unified
lexical asset model for words and user-confirmed phrases, versioned lemma
normalization, optional offline learning data, and provider-neutral subtitle
search while preserving the macOS-first desktop scope.

- Schema v7 migrates existing word assets without removing `/v1/word-*`
  compatibility endpoints.
- Words and phrases share status, history, notes, definitions, and durable
  source snapshots. Phrase candidates appear as clickable subtitle underlines
  and require explicit confirmation.
- Lemma normalization records provider/version and persists user corrections.
- ECDICT and CMUdict are explicit checksum-verified optional resources.
- The first subtitle-search provider is OpenSubtitles.com.
- Dictionary providers may supply pronunciation audio without coupling the
  learning panel to a specific provider.
- Vocabulary asset v3 is the current portable format. Import keeps newer local
  state, merges learning content independently, and deduplicates sources.

Automated verification and a macOS package precede collaborative acceptance.
No `v0.6.0` tag is created until the user confirms the manual checklist.
