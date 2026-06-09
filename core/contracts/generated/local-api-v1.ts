// Handwritten client generation experiment for contracts/openapi/v1.yaml.
// Replace with generated Dart output when the Flutter desktop integration begins.
export type MediaKind = "video" | "audio";
export type WordStatus =
  | "unknown_meaning"
  | "known_not_recognized"
  | "known_recognized";

export interface ErrorBody {
  code: string;
  message: string;
  correlation_id: string;
  retryable: boolean;
}

export interface RegisterMedia {
  path: string;
  fingerprint: string;
  title: string;
  kind: MediaKind;
  duration_ms?: number | null;
}

export interface Health {
  status: "ok";
  api_version: 1;
}

export interface MediaItem {
  id: string;
  path: string;
  fingerprint: string;
  title: string;
  kind: MediaKind;
  duration: number | null;
  created_at_ms: number;
  updated_at_ms: number;
}

export interface Progress {
  position_ms: number | null;
}

export type SubtitleTokenKind = "word" | "whitespace" | "punctuation" | "other";

export interface SubtitleToken {
  index: number;
  kind: SubtitleTokenKind;
  text: string;
  normalized: string | null;
  start_char: number;
  end_char: number;
}

export interface SubtitleSentence {
  id: string;
  index: number;
  start: number;
  end: number;
  original_text: string;
  display_text: string;
  tokens: SubtitleToken[];
}

export interface SubtitleTrack {
  id: string;
  media_id: string;
  fingerprint: string;
  language: string | null;
  source: string;
  sentences: SubtitleSentence[];
}

export interface UpdateWordProfile {
  language: string;
  lemma: string;
  display_form: string;
  status?: WordStatus | null;
}

export interface WordProfile extends UpdateWordProfile {
  id: string;
  normalized_lemma: string;
  status: WordStatus | null;
  updated_at_ms: number;
}

export class LocalApiV1 {
  constructor(
    private readonly baseUrl: string,
    private readonly token: string,
  ) {}

  health(): Promise<Health> {
    return this.request("/v1/health", {}, false);
  }

  registerMedia(input: RegisterMedia): Promise<MediaItem> {
    return this.request("/v1/media", { method: "POST", body: JSON.stringify(input) });
  }

  readMedia(mediaId: string): Promise<MediaItem> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}`);
  }

  readProgress(mediaId: string): Promise<Progress> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}/progress`);
  }

  updateProgress(mediaId: string, positionMs: number): Promise<Progress> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}/progress`, {
      method: "PUT",
      body: JSON.stringify({ position_ms: positionMs }),
    });
  }

  importSubtitle(mediaId: string, path: string, language?: string): Promise<SubtitleTrack> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}/subtitles`, {
      method: "POST",
      body: JSON.stringify({ path, language }),
    });
  }

  readSubtitle(trackId: string): Promise<SubtitleTrack> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}`);
  }

  readWordProfile(language: string, lemma: string): Promise<WordProfile | null> {
    const query = new URLSearchParams({ language, lemma });
    return this.request(`/v1/word-profiles?${query}`);
  }

  updateWordProfile(input: UpdateWordProfile): Promise<WordProfile> {
    return this.request("/v1/word-profiles", {
      method: "PUT",
      body: JSON.stringify(input),
    });
  }

  readWordProfiles(language: string, lemmas: string[]): Promise<WordProfile[]> {
    return this.request("/v1/word-profiles/batch", {
      method: "POST",
      body: JSON.stringify({ language, lemmas }),
    });
  }

  createWordObservation(input: {
    word_profile_id: string;
    sentence_id: string;
    original_form: string;
    result: "recognized_in_context" | "not_recognized_in_context";
  }): Promise<unknown> {
    return this.request("/v1/word-observations", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  dictionaryLookup(language: string, lemma: string): Promise<unknown | null> {
    const query = new URLSearchParams({ language, lemma });
    return this.request(`/v1/dictionary?${query}`);
  }

  diagnoseSentence(sentenceId: string): Promise<unknown> {
    return this.request(`/v1/sentences/${encodeURIComponent(sentenceId)}/diagnosis`);
  }

  private async request<T>(
    path: string,
    init: RequestInit = {},
    authenticated = true,
  ): Promise<T> {
    const headers = new Headers(init.headers);
    headers.set("content-type", "application/json");
    if (authenticated) headers.set("authorization", `Bearer ${this.token}`);
    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers });
    if (!response.ok) throw (await response.json()) as ErrorBody;
    return (await response.json()) as T;
  }
}
