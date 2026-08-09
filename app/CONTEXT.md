# Listen App Context

Canonical product purpose, shared language, context ownership, and learner
journeys live in
[`ichthyoplanktonzyh/listen`](https://github.com/ichthyoplanktonzyh/listen).
`backend.lock.json` independently pins runtime behavior and compatibility.

This glossary adds only concepts owned by the learner-facing application.

## Material Intake

**Material Intake**:
The learner-facing act of opening a source asset or community item and resolving
what Listen can use immediately.
_Avoid_: Package Installation, Content Enrichment

**Local Asset Binding**:
A learner-approved association between a local file and a Language Material or
Material Revision.
_Avoid_: Source Identity, ownership proof

**Retention Decision**:
The Learner's explicit choice to move a Temporary Material into the Personal
Library.
_Avoid_: Automatic import, recent-file history

## Discovery And Acquisition

**Discovery Result**:
A learner-facing description of a potentially useful Language Material,
Learning Edition, or Package Listing that has not yet entered the Personal
Library.
_Avoid_: Learning Material, Package Installation

**Acquisition Option**:
A declared way to play, obtain, or bind a required source asset, including its
availability and rights context.
_Avoid_: Download entitlement, Discovery Result

**Package Match**:
A candidate relation between a Material Revision or Media Rendition and a
compatible Package Release.
_Avoid_: Package Installation, matching title

**Discovery Inbox**:
The learner-facing stream of Discovery Items collected from Content
Subscriptions, direct imports, and future community discovery.
_Avoid_: Personal Library, automatic retention

**Start Learning Intent**:
The Learner's explicit decision to make one Discovery Item locally usable and
retain it for learning. The App may orchestrate Material Acquisition, Package
Installation, and Learning Edition Adoption without exposing those steps.
_Avoid_: Preview, Package Installation, implicit activation

## Experience And Capabilities

**Unavailable State**:
A learner-facing state that names why a requested capability cannot currently
run and, when possible, identifies a recovery action.
_Avoid_: Silent no-op, disabled control without explanation, generic failure

**Capability Presentation**:
The App's honest presentation of which Learning Activities are available,
degraded, unavailable, or still being prepared for the current material.
_Avoid_: Hard-coded language workflow, feature flag list

**Generation Request**:
A learner-visible request to enrich one material, including selected
capabilities, progress, cancellation, warnings, and the resulting artifact.
_Avoid_: Provider command line, Content Package schema

**Search Scope Selection**:
The Learner's choice among Current Material, Personal Corpus, and Community
Corpus for one query.
_Avoid_: Separate search product

**External Context Presentation**:
An attributed, provider-limited presentation of External Context References
that remains separate from Listen-owned corpus results.
_Avoid_: Imported corpus data, hidden fallback

## Updates And Synchronization

**Package Update Notice**:
A notification that a newer Package Release exists for an installed Learning
Edition. It never changes the active release by itself.
_Avoid_: Automatic replacement, release installation

**Package Update Decision**:
The Learner's explicit acceptance, deferral, or rejection of a Package Update
Notice.
_Avoid_: Background mutation

**Sync State**:
The learner-visible condition of private data replication across devices,
including current, pending, offline, conflicted, and failed states.
_Avoid_: Network connectivity, package download status

**Sync Conflict**:
A concurrent change to learner-owned data that cannot be merged without
preserving both versions or asking the Learner.
_Avoid_: Last-write-wins for every data type, server error
