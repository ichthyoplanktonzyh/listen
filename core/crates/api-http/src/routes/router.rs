use axum::Router;
use axum::middleware;
use axum::routing::{delete, get, post, put};

use super::corpus::{reindex_corpus, search_corpus};
use super::dictionary::{diagnose_sentence, dictionary_lookup};
use super::language::{language_profile, list_languages};
use super::learner::{l1_specialty_occurrences, learner_profile, update_learner_profile};
use super::llm::{
    delete_llm_provider, feedback_via_llm_provider, generate_rubric_via_llm_provider,
    get_llm_provider, judge_via_llm_provider, list_llm_providers, probe_llm_provider,
    register_llm_provider,
};
use super::media::{
    archive_subtitle, cold_start_words, delete_subtitle, export_subtitle, import_lltimeline,
    import_lltimeline_for_media, import_subtitle, list_media_library, media_subtitles, read_media,
    read_subtitle, register_media, restore_subtitle, set_media_triage_intent, track_content_fit,
    update_track_language,
};
use super::personal_expression::{
    create_pattern, delete_pattern, export_patterns, get_pattern, list_pattern_attempts,
    list_pattern_versions, list_patterns, record_pattern_attempt, revise_pattern,
};
use super::phonetic_analysis::{
    cancel_phonetic_analysis_job, cancel_phonetic_analysis_model_install,
    clear_terminal_phonetic_analysis_jobs, create_phonetic_analysis_job,
    delete_phonetic_analysis_job, delete_phonetic_analysis_model, install_phonetic_analysis_model,
    phonetic_analysis_findings, phonetic_analysis_job, phonetic_analysis_jobs,
    phonetic_analysis_models, phonetic_analysis_providers, register_custom_phonetic_analysis_model,
    retry_phonetic_analysis_job, track_phonetic_analyses, update_phonetic_finding_feedback,
};
use super::practice::{
    archive_hunting_target, capture_listening_inbox_item, coach_dashboard, coach_evidence,
    compare_shadowing, complete_listening_session, complete_shadowing_attempt,
    confirm_upgrade_suggestion, create_hunting_target, create_practice_item,
    create_practice_session, create_recording_asset, create_review_item, custom_study,
    delete_recording_asset, export_anki_package, graduate_coach_material, import_anki_package,
    list_due_review_items, list_hunting_candidates, list_hunting_occurrences, list_hunting_targets,
    list_listening_inbox_items, list_upgrade_suggestions, practice_attempt,
    process_listening_inbox_item, recording_asset, recording_audio_facts,
    reject_upgrade_suggestion, review_daily_limits, review_deck_overview, review_interval_preview,
    review_item, review_queue, submit_custom_study_attempt, submit_hunting_check,
    submit_practice_attempt, submit_review_attempt, update_review_daily_limits,
    upgrade_suggestion_history,
};
use super::production_corpus::{
    production_gap_review, reindex_production_corpus, search_production_corpus,
};
use super::projection_review::{
    audit_projection, cross_modal_gaps, decide_projection, list_projection_proposals,
    rebuild_projections,
};
use super::pronunciation::{
    analyze_pronunciation_sentence, generate_track_pronunciation, pronunciation_lookup,
    pronunciation_providers, track_pronunciation,
};
use super::reading::{reading_position, record_reading_marking, save_reading_position};
use super::realtime_conversation::{
    connect as connect_realtime_conversation, delete_profile as delete_realtime_profile,
    list_profiles as list_realtime_profiles, list_sessions as list_realtime_sessions,
    list_turns as list_realtime_turns, register_profile as register_realtime_profile,
    save_session as save_realtime_session, save_turn as save_realtime_turn,
};
use super::semantic::{
    confirm_speaking_target, create_judgment_adjudication, create_semantic_attempt,
    create_semantic_judgment, create_semantic_rubric, create_writing_disposition,
    create_writing_finding, delete_writing_draft, generate_local_writing_findings,
    lookup_semantic_rubric, save_writing_draft, semantic_attempt, semantic_attempt_judgments,
    semantic_judgment_adjudications, semantic_rubric, semantic_rubric_attempts,
    writing_dispositions, writing_draft, writing_findings,
};
use super::semantic_embedding::{
    capability as semantic_embedding_capability, disable as disable_semantic_embedding,
    enable as enable_semantic_embedding, enrich_gap_review as enrich_production_gap_semantically,
    install as install_semantic_embedding, rebuild as rebuild_semantic_embedding,
    search as semantic_search, uninstall as uninstall_semantic_embedding,
};
use super::sound_line::{
    cancel_sound_line_job, create_sound_line_job, retry_sound_line_job, sound_line_job,
    sound_line_jobs,
};
use super::speech::{
    cancel_speech_job, create_speech_job, retry_speech_job, speech_job, speech_jobs,
};
use super::syntax::{
    cancel_syntax_capability, disable_syntax_capability, enable_syntax_capability,
    install_syntax_capability, run_syntactic_consumers, run_track_syntax_analysis,
    syntax_capability, track_syntax_analysis_status, uninstall_syntax_capability,
    update_syntax_capability, validate_syntax_capability,
};
use super::timelines::{
    activate_chunk_timeline, activate_phone_timeline, activate_sense_group_analysis,
    activate_word_timeline, archive_chunk_timeline, archive_phone_timeline,
    archive_sense_group_analysis, archive_word_timeline, chunk_providers, chunk_timeline,
    create_track_word_timeline, delete_chunk_timeline, delete_phone_timeline,
    delete_sense_group_analysis, delete_word_timeline, export_chunk_timeline,
    export_phone_timeline, export_track_lltimeline, export_word_timeline, generate_chunk_timeline,
    generate_sense_group_analysis, generate_track_word_timings, phone_timeline,
    publish_word_timeline, sense_group_analysis, track_chunk_diagnostics, track_chunk_partitions,
    track_chunk_timeline_summaries, track_chunk_timelines, track_phone_timeline_summaries,
    track_phone_timelines, track_sense_group_analyses, track_sense_group_analysis_summaries,
    track_word_timeline_summaries, track_word_timelines, track_word_timing_diagnostics,
    track_word_timings, word_timeline,
};
use super::transcription::{
    archive_transcription_job, cancel_recording_transcription, cancel_transcription_job,
    cancel_transcription_model_install, create_recording_transcription, create_transcription_job,
    delete_transcription_model, install_transcription_model, pronunciation_rules,
    recording_transcription_job, register_custom_transcription_model, retry_transcription_job,
    transcription_job, transcription_jobs, transcription_models, transcription_providers,
};
use super::tts::{clear_speech_synthesis_cache, speech_synthesis_capability, synthesize_speech};
use super::vocabulary::{
    assign_sense_folder_occurrence, create_sense_folder, delete_sense_folder, export_vocabulary,
    get_capability_profile, import_external_vocabulary, import_vocabulary,
    list_learning_observation_history, list_vocabulary, read_progress, set_capability_override,
    unassign_sense_folder_occurrence, update_media_availability, update_progress,
    update_sense_folder,
};
use crate::event_stream::events;
use crate::{ApiState, authorize};

pub(crate) fn protected_router(state: &ApiState) -> Router<ApiState> {
    media_analysis_routes()
        .merge(learning_routes())
        .merge(generative_routes())
        .merge(provider_and_event_routes())
        .route_layer(middleware::from_fn_with_state(state.clone(), authorize))
}

fn media_analysis_routes() -> Router<ApiState> {
    Router::new()
        .route("/v1/media", post(register_media).get(list_media_library))
        .route(
            "/v1/media/{media_id}/triage-intent",
            put(set_media_triage_intent),
        )
        .route("/v1/lltimeline/import", post(import_lltimeline))
        .route("/v1/media/{media_id}", get(read_media))
        .route(
            "/v1/media/{media_id}/lltimeline/import",
            post(import_lltimeline_for_media),
        )
        .route(
            "/v1/media/{media_id}/subtitles",
            get(media_subtitles).post(import_subtitle),
        )
        .route(
            "/v1/subtitles/{track_id}",
            get(read_subtitle).delete(delete_subtitle),
        )
        .route("/v1/subtitles/{track_id}/archive", post(archive_subtitle))
        .route("/v1/subtitles/{track_id}/restore", post(restore_subtitle))
        .route(
            "/v1/subtitles/{track_id}/language",
            axum::routing::patch(update_track_language),
        )
        .route("/v1/subtitles/{track_id}/export", get(export_subtitle))
        .route(
            "/v1/subtitles/{track_id}/content-fit",
            get(track_content_fit),
        )
        .route(
            "/v1/subtitles/{track_id}/cold-start-words",
            get(cold_start_words),
        )
        .route("/v1/pronunciation/providers", get(pronunciation_providers))
        .route("/v1/pronunciation/lookup", get(pronunciation_lookup))
        .route(
            "/v1/pronunciation/analyze-sentence",
            post(analyze_pronunciation_sentence),
        )
        .route("/v1/pronunciation/rules", get(pronunciation_rules))
        .route(
            "/v1/subtitles/{track_id}/pronunciation",
            get(track_pronunciation),
        )
        .route(
            "/v1/subtitles/{track_id}/pronunciation-analysis",
            post(generate_track_pronunciation),
        )
        .route(
            "/v1/subtitles/{track_id}/word-timings",
            get(track_word_timings).post(generate_track_word_timings),
        )
        .route(
            "/v1/subtitles/{track_id}/word-timelines",
            get(track_word_timelines).post(create_track_word_timeline),
        )
        .route(
            "/v1/subtitles/{track_id}/word-timelines/summary",
            get(track_word_timeline_summaries),
        )
        .route(
            "/v1/subtitles/{track_id}/lltimeline/export",
            get(export_track_lltimeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}",
            get(word_timeline).delete(delete_word_timeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}/activate",
            post(activate_word_timeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}/publish",
            post(publish_word_timeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}/archive",
            post(archive_word_timeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}/export",
            get(export_word_timeline),
        )
        .route(
            "/v1/subtitles/{track_id}/word-timing-diagnostics",
            get(track_word_timing_diagnostics),
        )
        .route(
            "/v1/subtitles/{track_id}/chunk-partitions",
            get(track_chunk_partitions),
        )
        .route(
            "/v1/subtitles/{track_id}/chunk-diagnostics",
            get(track_chunk_diagnostics),
        )
        .route("/v1/chunk/providers", get(chunk_providers))
        .route(
            "/v1/subtitles/{track_id}/chunk-timelines",
            get(track_chunk_timelines).post(generate_chunk_timeline),
        )
        .route(
            "/v1/subtitles/{track_id}/chunk-timelines/summary",
            get(track_chunk_timeline_summaries),
        )
        .route(
            "/v1/chunk-timelines/{timeline_id}",
            get(chunk_timeline).delete(delete_chunk_timeline),
        )
        .route(
            "/v1/chunk-timelines/{timeline_id}/activate",
            post(activate_chunk_timeline),
        )
        .route(
            "/v1/chunk-timelines/{timeline_id}/archive",
            post(archive_chunk_timeline),
        )
        .route(
            "/v1/chunk-timelines/{timeline_id}/export",
            get(export_chunk_timeline),
        )
        .route(
            "/v1/subtitles/{track_id}/sense-group-analyses",
            get(track_sense_group_analyses).post(generate_sense_group_analysis),
        )
        .route(
            "/v1/subtitles/{track_id}/syntactic-consumers",
            post(run_syntactic_consumers),
        )
        .route(
            "/v1/subtitles/{track_id}/syntax-analysis",
            get(track_syntax_analysis_status).post(run_track_syntax_analysis),
        )
        .route("/v1/syntax/capability", get(syntax_capability))
        .route(
            "/v1/syntax/capability/install",
            post(install_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/cancel",
            post(cancel_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/validate",
            post(validate_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/enable",
            post(enable_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/disable",
            post(disable_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/uninstall",
            post(uninstall_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/update",
            post(update_syntax_capability),
        )
        .route(
            "/v1/subtitles/{track_id}/sense-group-analyses/summary",
            get(track_sense_group_analysis_summaries),
        )
        .route(
            "/v1/sense-group-analyses/{analysis_id}",
            get(sense_group_analysis).delete(delete_sense_group_analysis),
        )
        .route(
            "/v1/sense-group-analyses/{analysis_id}/activate",
            post(activate_sense_group_analysis),
        )
        .route(
            "/v1/sense-group-analyses/{analysis_id}/archive",
            post(archive_sense_group_analysis),
        )
        .route(
            "/v1/subtitles/{track_id}/phone-timelines",
            get(track_phone_timelines),
        )
        .route(
            "/v1/subtitles/{track_id}/phone-timelines/summary",
            get(track_phone_timeline_summaries),
        )
        .route(
            "/v1/phone-timelines/{timeline_id}",
            get(phone_timeline).delete(delete_phone_timeline),
        )
        .route(
            "/v1/phone-timelines/{timeline_id}/activate",
            post(activate_phone_timeline),
        )
        .route(
            "/v1/phone-timelines/{timeline_id}/archive",
            post(archive_phone_timeline),
        )
        .route(
            "/v1/phone-timelines/{timeline_id}/export",
            get(export_phone_timeline),
        )
        .route("/v1/speech/jobs", get(speech_jobs).post(create_speech_job))
        .route("/v1/speech/jobs/{job_id}", get(speech_job))
        .route("/v1/speech/jobs/{job_id}/cancel", post(cancel_speech_job))
        .route("/v1/speech/jobs/{job_id}/retry", post(retry_speech_job))
        .route(
            "/v1/sound-line/jobs",
            get(sound_line_jobs).post(create_sound_line_job),
        )
        .route("/v1/sound-line/jobs/{job_id}", get(sound_line_job))
        .route(
            "/v1/sound-line/jobs/{job_id}/cancel",
            post(cancel_sound_line_job),
        )
        .route(
            "/v1/sound-line/jobs/{job_id}/retry",
            post(retry_sound_line_job),
        )
        .route(
            "/v1/media/{media_id}/progress",
            get(read_progress).put(update_progress),
        )
        .route(
            "/v1/media/{media_id}/availability",
            axum::routing::put(update_media_availability),
        )
        .route("/v1/transcription/providers", get(transcription_providers))
        .route("/v1/transcription/models", get(transcription_models))
        .route(
            "/v1/transcription/models/install",
            post(install_transcription_model),
        )
        .route(
            "/v1/transcription/models/register-custom",
            post(register_custom_transcription_model),
        )
        .route(
            "/v1/transcription/models/{model_id}/cancel-install",
            post(cancel_transcription_model_install),
        )
        .route(
            "/v1/transcription/models/{model_id}",
            axum::routing::delete(delete_transcription_model),
        )
        .route(
            "/v1/transcription/jobs",
            get(transcription_jobs).post(create_transcription_job),
        )
        .route("/v1/transcription/jobs/{job_id}", get(transcription_job))
        .route(
            "/v1/transcription/jobs/{job_id}/cancel",
            post(cancel_transcription_job),
        )
        .route(
            "/v1/transcription/jobs/{job_id}/retry",
            post(retry_transcription_job),
        )
        .route(
            "/v1/transcription/jobs/{job_id}/archive",
            post(archive_transcription_job),
        )
        .route(
            "/v1/phonetic-analysis/providers",
            get(phonetic_analysis_providers),
        )
        .route(
            "/v1/phonetic-analysis/models",
            get(phonetic_analysis_models),
        )
        .route(
            "/v1/phonetic-analysis/models/install",
            post(install_phonetic_analysis_model),
        )
        .route(
            "/v1/phonetic-analysis/models/register-custom",
            post(register_custom_phonetic_analysis_model),
        )
        .route(
            "/v1/phonetic-analysis/models/{model_id}/cancel-install",
            post(cancel_phonetic_analysis_model_install),
        )
        .route(
            "/v1/phonetic-analysis/models/{model_id}",
            delete(delete_phonetic_analysis_model),
        )
        .route(
            "/v1/phonetic-analysis/jobs",
            get(phonetic_analysis_jobs).post(create_phonetic_analysis_job),
        )
        .route(
            "/v1/phonetic-analysis/jobs/clear",
            post(clear_terminal_phonetic_analysis_jobs),
        )
        .route(
            "/v1/phonetic-analysis/jobs/{job_id}",
            get(phonetic_analysis_job).delete(delete_phonetic_analysis_job),
        )
        .route(
            "/v1/phonetic-analysis/jobs/{job_id}/cancel",
            post(cancel_phonetic_analysis_job),
        )
        .route(
            "/v1/phonetic-analysis/jobs/{job_id}/retry",
            post(retry_phonetic_analysis_job),
        )
        .route(
            "/v1/subtitles/{track_id}/phonetic-analyses",
            get(track_phonetic_analyses),
        )
        .route(
            "/v1/phonetic-analysis/{analysis_id}/findings",
            get(phonetic_analysis_findings),
        )
        .route(
            "/v1/phonetic-analysis/findings/{finding_id}/feedback",
            put(update_phonetic_finding_feedback),
        )
        .route(
            "/v1/sentences/{sentence_id}/diagnosis",
            get(diagnose_sentence),
        )
}

fn learning_routes() -> Router<ApiState> {
    Router::new()
        .route(
            "/v1/lexical-entries/batch",
            post(super::lexical_entries::read_lexical_entries),
        )
        .route(
            "/v1/lexical-entries",
            get(super::lexical_entries::list_lexical_entries)
                .put(super::lexical_entries::upsert_lexical_entry),
        )
        .route(
            "/v1/lexical-entries/{id}",
            get(super::lexical_entries::lexical_details),
        )
        .route(
            "/v1/lexical-entries/{id}/capability-profile",
            get(get_capability_profile),
        )
        .route(
            "/v1/lexical-entries/{id}/observations",
            get(list_learning_observation_history),
        )
        .route(
            "/v1/lexical-entries/{id}/capability/{capability}",
            put(set_capability_override),
        )
        .route(
            "/v1/lexical-entries/{id}/learning-content",
            put(super::lexical_entries::update_lexical_learning_content),
        )
        .route(
            "/v1/lexical-entries/{entry_id}/sense-folders",
            post(create_sense_folder),
        )
        .route(
            "/v1/lexical-entries/{entry_id}/sense-folders/{sense_id}",
            put(update_sense_folder).delete(delete_sense_folder),
        )
        .route(
            "/v1/lexical-entries/{entry_id}/sense-folders/{sense_id}/occurrences/{occurrence_id}",
            put(assign_sense_folder_occurrence).delete(unassign_sense_folder_occurrence),
        )
        .route(
            "/v1/lexical-observations",
            post(super::lexical_entries::create_lexical_observation),
        )
        .route(
            "/v1/lexical-normalization",
            post(super::lexical_entries::normalize_lexical),
        )
        .route(
            "/v1/lexical-normalization/correct",
            post(super::lexical_entries::correct_lemma),
        )
        .route(
            "/v1/sentences/{sentence_id}/phrase-candidates",
            get(super::lexical_entries::phrase_candidates),
        )
        .route("/v1/practice/sessions", post(create_practice_session))
        .route("/v1/coach/dashboard", get(coach_dashboard))
        .route("/v1/coach/evidence", get(coach_evidence))
        .route(
            "/v1/coach/materials/{media_id}/graduate",
            post(graduate_coach_material),
        )
        .route(
            "/v1/listening/sessions/{id}/complete",
            post(complete_listening_session),
        )
        .route("/v1/practice/items", post(create_practice_item))
        .route("/v1/practice/attempts", post(submit_practice_attempt))
        .route("/v1/practice/attempts/{id}", get(practice_attempt))
        .route(
            "/v1/practice/shadowing-attempts",
            post(complete_shadowing_attempt),
        )
        .route("/v1/shadowing/comparisons", post(compare_shadowing))
        .route("/v1/recordings", post(create_recording_asset))
        .route(
            "/v1/recordings/{id}",
            get(recording_asset).delete(delete_recording_asset),
        )
        .route(
            "/v1/recordings/{id}/audio-facts",
            get(recording_audio_facts),
        )
        .route(
            "/v1/recording-transcriptions",
            post(create_recording_transcription),
        )
        .route(
            "/v1/recording-transcriptions/{job_id}",
            get(recording_transcription_job),
        )
        .route(
            "/v1/recording-transcriptions/{job_id}/cancel",
            post(cancel_recording_transcription),
        )
        .route(
            "/v1/listening-inbox/items",
            get(list_listening_inbox_items).post(capture_listening_inbox_item),
        )
        .route(
            "/v1/listening-inbox/items/{id}/process",
            post(process_listening_inbox_item),
        )
        .route("/v1/hunting/candidates", get(list_hunting_candidates))
        .route(
            "/v1/hunting/targets",
            get(list_hunting_targets).post(create_hunting_target),
        )
        .route("/v1/hunting/targets/{id}", delete(archive_hunting_target))
        .route("/v1/hunting/occurrences", get(list_hunting_occurrences))
        .route("/v1/hunting/checks", post(submit_hunting_check))
        .route(
            "/v1/review/items",
            get(list_due_review_items).post(create_review_item),
        )
        .route("/v1/review/queue", get(review_queue))
        .route("/v1/review/decks", get(review_deck_overview))
        .route(
            "/v1/review/settings/limits",
            get(review_daily_limits).put(update_review_daily_limits),
        )
        .route("/v1/review/custom-study", post(custom_study))
        .route(
            "/v1/review/custom-study/attempts",
            post(submit_custom_study_attempt),
        )
        .route("/v1/review/anki/import", post(import_anki_package))
        .route("/v1/review/anki/export", post(export_anki_package))
        .route("/v1/review/items/{id}", get(review_item))
        .route(
            "/v1/review/items/{id}/interval-preview",
            get(review_interval_preview),
        )
        .route("/v1/review/attempts", post(submit_review_attempt))
        .route("/v1/review/cross-modal", get(cross_modal_gaps))
        .route("/v1/projections/rebuild", post(rebuild_projections))
        .route(
            "/v1/projections/entries/{id}",
            get(list_projection_proposals).post(audit_projection),
        )
        .route(
            "/v1/projections/proposals/{id}/decision",
            post(decide_projection),
        )
        .route(
            "/v1/review/upgrade-suggestions",
            get(list_upgrade_suggestions),
        )
        .route(
            "/v1/review/upgrade-suggestions/history",
            get(upgrade_suggestion_history),
        )
        .route(
            "/v1/review/upgrade-suggestions/{id}/confirm",
            post(confirm_upgrade_suggestion),
        )
        .route(
            "/v1/review/upgrade-suggestions/{id}/reject",
            post(reject_upgrade_suggestion),
        )
        .route("/v1/vocabulary", get(list_vocabulary))
        .route("/v1/corpus/search", get(search_corpus))
        .route("/v1/corpus/reindex", post(reindex_corpus))
        .route(
            "/v1/production-corpus/search",
            get(search_production_corpus),
        )
        .route(
            "/v1/production-corpus/reindex",
            post(reindex_production_corpus),
        )
        .route("/v1/production-gap/review", get(production_gap_review))
        .route(
            "/v1/personal-expression/patterns",
            get(list_patterns).post(create_pattern),
        )
        .route(
            "/v1/personal-expression/patterns/{id}",
            get(get_pattern).put(revise_pattern).delete(delete_pattern),
        )
        .route(
            "/v1/personal-expression/patterns/{id}/versions",
            get(list_pattern_versions),
        )
        .route(
            "/v1/personal-expression/patterns/{id}/attempts",
            get(list_pattern_attempts).post(record_pattern_attempt),
        )
        .route("/v1/personal-expression/export", get(export_patterns))
        .route(
            "/v1/production-gap/semantic-enrichment",
            get(enrich_production_gap_semantically),
        )
        .route("/v1/vocabulary/export", get(export_vocabulary))
        .route("/v1/vocabulary/import", post(import_vocabulary))
        .route(
            "/v1/vocabulary/import-external",
            post(import_external_vocabulary),
        )
        .route(
            "/v1/learner/profile",
            get(learner_profile).put(update_learner_profile),
        )
        .route("/v1/learner/l1-specialty", get(l1_specialty_occurrences))
        .route(
            "/v1/reading/positions/{track_id}",
            get(reading_position).put(save_reading_position),
        )
        .route("/v1/reading/markings", post(record_reading_marking))
}

fn generative_routes() -> Router<ApiState> {
    Router::new()
        .route(
            "/v1/speech-synthesis/capability",
            get(speech_synthesis_capability),
        )
        .route("/v1/speech-synthesis", post(synthesize_speech))
        .route(
            "/v1/speech-synthesis/cache",
            delete(clear_speech_synthesis_cache),
        )
        .route(
            "/v1/semantic-embedding/capability",
            get(semantic_embedding_capability),
        )
        .route(
            "/v1/semantic-embedding/install",
            post(install_semantic_embedding),
        )
        .route(
            "/v1/semantic-embedding/enable",
            post(enable_semantic_embedding),
        )
        .route(
            "/v1/semantic-embedding/disable",
            post(disable_semantic_embedding),
        )
        .route(
            "/v1/semantic-embedding",
            delete(uninstall_semantic_embedding),
        )
        .route(
            "/v1/semantic-embedding/reindex",
            post(rebuild_semantic_embedding),
        )
        .route("/v1/semantic-search", get(semantic_search))
        .route("/v1/semantic/rubrics", post(create_semantic_rubric))
        .route("/v1/semantic/rubrics/lookup", get(lookup_semantic_rubric))
        .route("/v1/semantic/rubrics/{id}", get(semantic_rubric))
        .route(
            "/v1/semantic/rubrics/{id}/attempts",
            get(semantic_rubric_attempts),
        )
        .route("/v1/semantic/attempts", post(create_semantic_attempt))
        .route(
            "/v1/semantic/writing-drafts/{id}",
            get(writing_draft)
                .put(save_writing_draft)
                .delete(delete_writing_draft),
        )
        .route("/v1/semantic/attempts/{id}", get(semantic_attempt))
        .route(
            "/v1/semantic/attempts/{id}/writing-findings",
            get(writing_findings).post(create_writing_finding),
        )
        .route(
            "/v1/semantic/attempts/{id}/writing-findings/local",
            post(generate_local_writing_findings),
        )
        .route(
            "/v1/semantic/attempts/{id}/speaking-targets",
            post(confirm_speaking_target),
        )
        .route(
            "/v1/semantic/attempts/{id}/judgments",
            get(semantic_attempt_judgments),
        )
        .route("/v1/semantic/judgments", post(create_semantic_judgment))
        .route(
            "/v1/semantic/judgments/{id}/adjudications",
            get(semantic_judgment_adjudications),
        )
        .route(
            "/v1/semantic/adjudications",
            post(create_judgment_adjudication),
        )
        .route(
            "/v1/semantic/writing-findings/{id}/dispositions",
            get(writing_dispositions).post(create_writing_disposition),
        )
        .route(
            "/v1/llm/providers",
            get(list_llm_providers).post(register_llm_provider),
        )
        .route(
            "/v1/llm/providers/{id}",
            get(get_llm_provider).delete(delete_llm_provider),
        )
        .route("/v1/llm/providers/{id}/probe", post(probe_llm_provider))
        .route(
            "/v1/realtime/providers",
            get(list_realtime_profiles).post(register_realtime_profile),
        )
        .route(
            "/v1/realtime/providers/{id}",
            delete(delete_realtime_profile),
        )
        .route(
            "/v1/realtime/conversations/ws",
            get(connect_realtime_conversation),
        )
        .route(
            "/v1/realtime/sessions",
            get(list_realtime_sessions).post(save_realtime_session),
        )
        .route("/v1/realtime/sessions/{id}/turns", get(list_realtime_turns))
        .route("/v1/realtime/turns", post(save_realtime_turn))
        .route("/v1/llm/providers/{id}/judge", post(judge_via_llm_provider))
        .route(
            "/v1/llm/providers/{id}/feedback",
            post(feedback_via_llm_provider),
        )
        .route(
            "/v1/llm/providers/{id}/rubric",
            post(generate_rubric_via_llm_provider),
        )
        .route("/v1/languages", get(list_languages))
        .route("/v1/languages/{code}/profile", get(language_profile))
}

fn provider_and_event_routes() -> Router<ApiState> {
    Router::new()
        .route(
            "/v1/learning-resources",
            get(super::learning_resources::list),
        )
        .route(
            "/v1/learning-resources/{id}/install",
            post(super::learning_resources::install),
        )
        .route(
            "/v1/learning-resources/{id}",
            axum::routing::delete(super::learning_resources::remove),
        )
        .route("/v1/subtitle-search", post(super::subtitle_search::search))
        .route(
            "/v1/subtitle-search/download",
            post(super::subtitle_search::download),
        )
        .route("/v1/events", get(events))
        .route("/v1/dictionary", get(dictionary_lookup))
}
