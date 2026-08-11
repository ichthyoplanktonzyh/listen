# Separate Document Renditions from Structured Reading Resources

> Status: accepted, 2026-08-11.

Documents such as plain text, Markdown, HTML, EPUB, text-layer PDF, and scanned
PDF combine source bytes, authored layout, and logical reading content in
different ways. Listen therefore treats a supported original file or typed or
pasted plain text as a **Document Rendition** of a Material Revision, while
chapters, blocks, language spans, and stable anchors belong to a separate,
versioned **Structured Reading Resource**. This preserves source fidelity,
allows direct viewing before extraction, and lets multiple document, audio, and
video renditions remain capabilities of one Material.

Core owns the canonical rendition, resource, anchor, applicability, and learner
state semantics. App owns learner-facing intake, safe direct rendering, and
basic consumer-bundled decoding for supported formats. Gen may provide optional
expensive or reusable extraction, cleanup, and OCR, but it is never required to
view a supported rendition. All producers cross the same typed resource seam;
renderers and parsers do not become material authority.

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
numbers, or paragraph indexes. Existing contracts are not silently
reinterpreted: the current inline material `document_text` asset remains a
plain-text compatibility obligation, while Content Package v2 `document_text`
remains a Base Resource rather than becoming a Document Rendition. Future
executable contract evolution must map both explicitly to this boundary.
