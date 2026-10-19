# Separate Document Renditions from Structured Reading Resources

> Status: partially superseded by
> [0003](0003-complete-learning-material-boundary.md), 2026-08-24. Source
> fidelity, exact rendition/resource separation, stable anchors, provenance,
> and compatibility remain accepted. Direct viewing before extraction is now a
> Source preview concern rather than the formal learning boundary.

Documents such as plain text, Markdown, HTML, EPUB, text-layer PDF, and scanned
PDF combine source bytes, authored layout, and logical reading content in
different ways. Listen therefore treats a supported original file or typed or
pasted plain text as a **Document Rendition** of a Material Revision, while
chapters, blocks, language spans, and stable anchors belong to a separate,
versioned **Structured Reading Resource**. This preserves source fidelity,
allows direct viewing before extraction, and lets multiple document, audio, and
video renditions remain capabilities of one Material.

The layering is explicit. A **Source Asset** is the Learner-authorized original
bytes with digest, size, and binding. A **Document Rendition** binds the true
bytes of one concrete format (plain text, Markdown, HTML, EPUB, PDF); it is
not an extraction result, and a Source Document Rendition must bind a real
Source Asset rather than fabricating a Source Asset identity from a Rendition
identity. A **Structured Reading Resource** is a self-contained, format-neutral
Base Resource that owns the exact logical reading text (exact UTF-8 bytes) with
ordered hierarchy, blocks, spans, language metadata, and stable Reading
Anchors; every anchor range is byte-validated against that text. **Semantic
production** — TTS, translation, explanation — consumes Structured Reading,
never raw PDF or EPUB bytes, and Markdown is not a uniform intermediate format.
A producer that prefers Markdown derives a temporary Production Input
Projection from Structured Reading; it is not a Rendition, Resource, or
authoritative storage.

Core owns the canonical rendition, resource, anchor, applicability, and learner
state semantics. App owns learner-facing intake, safe direct rendering, and
basic consumer-bundled decoding for supported formats. Gen may provide optional
expensive or reusable extraction, cleanup, and OCR, but it is never required to
view a supported rendition, and it reads raw Document Rendition bytes only when
no compatible Structured Reading Resource exists. All producers cross the same
typed resource seam; renderers and parsers do not become material authority.

A Structured Reading Resource is an exact Base Resource. Reading positions,
annotations, corpus occurrences, and dependent resources bind to its Reading
Anchors. Page regions, document fragments, character ranges, and media times are
Rendition Locators that may map back to a source representation but do not serve
as cross-version learner-state identity. Replacing a resource or Material
Revision requires explicit compatibility or anchor mapping; otherwise existing
learner records remain retained but honestly detached rather than being silently
rebound or deleted.

This rejects flattening every document into one string, treating extraction as
a mandatory import gate, and storing learner state against file paths, page
numbers, or paragraph indexes. It also rejects a dual resource model in which
an inline `document_text` resource and a Structured Reading Resource both carry
logical reading content. A published contract identity is never silently
reinterpreted. During the pre-Phase-1 coordinated cutover, however, the current
inline material `document_text` representation and active Content Package v2
path may be replaced rather than preserved behind adapters; Content Package v3
carries raw document bytes on the Document Rendition and exact logical reading
content in a Structured Reading payload only. Historical artifacts remain
immutable; the new executable contract receives a new identity and becomes the
sole active Phase 1 path.
