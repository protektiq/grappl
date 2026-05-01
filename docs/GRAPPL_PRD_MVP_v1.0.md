# GRAPPL — BJJ Film Intelligence Platform
## Product Requirements Document — MVP v1.0

| Field | Value |
|---|---|
| Product Name | GRAPPL — BJJ Film Intelligence Platform |
| Document Type | Product Requirements Document (PRD) |
| Version | 1.0 — MVP |
| Date | April 30, 2026 |
| Scope | Single-user, local deployment (Minikube / Ubuntu) |
| Target Stack | Go, Kubernetes, Roboflow, LangChain, Supabase, Sigstore, OpenRewrite |
| Development Mode | Solo — Claude Code + Cursor (Plan Mode) |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Goals & Non-Goals](#3-goals--non-goals)
4. [User Stories](#4-user-stories)
5. [Functional Requirements](#5-functional-requirements)
6. [Non-Functional Requirements](#6-non-functional-requirements)
7. [System Architecture](#7-system-architecture)
8. [Data Model](#8-data-model)
9. [Detection Model Strategy](#9-detection-model-strategy)
10. [AI Coaching Pipeline](#10-ai-coaching-pipeline)
11. [MVP Feature Matrix](#11-mvp-feature-matrix)
12. [Build Plan](#12-build-plan)
13. [Learning Objectives](#13-learning-objectives)
14. [Risks & Mitigations](#14-risks--mitigations)
15. [MVP Success Criteria](#15-mvp-success-criteria)
16. [Post-MVP Roadmap](#16-post-mvp-roadmap)
- [Appendix — Technology Reference](#appendix--technology-reference)

---

## 1. Executive Summary

GRAPPL is a personal, AI-powered grappling film review platform built for a single practitioner. It ingests raw training and competition footage, automatically detects and classifies positional transitions and submission attempts using a custom-trained computer vision model, generates contextual coaching narratives using a large language model, and stores the resulting clip library in a structured local database.

The MVP targets one user, runs entirely on-premises via Minikube on Ubuntu, and produces a browsable film library requiring zero manual footage review. It is designed from the ground up to scale to a small coaching audience via schema-safe migrations and containerized service boundaries, without requiring architectural changes.

> **Design Principle:** GRAPPL handles the homework. It gives the practitioner specific, clip-level evidence to bring to their coach — accelerating the coach-athlete feedback loop rather than replacing it.

---

## 2. Problem Statement

### 2.1 The Gap

Serious grappling practitioners record their training sessions and competition footage, but deriving actionable insight from that footage requires hours of manual scrubbing — rewinding, tagging, and annotating events by hand. Most practitioners abandon the practice entirely or rely on incomplete memory of what happened on the mat.

### 2.2 The Consequence

Without structured film review, practitioners carry vague impressions of their game into coaching conversations ("I feel like I'm getting submitted a lot") rather than specific, evidence-backed questions ("Here are the three back-take sequences from this week — I can't figure out the pattern"). The coaching relationship suffers from a lack of shared, concrete reference points.

### 2.3 The Opportunity

Modern computer vision and large language models make it possible to automate the detection and annotation layer entirely — turning raw footage into a structured, searchable library with zero practitioner effort beyond dropping a video file into a folder.

> **Target Practitioner:** A hobbyist or competitive BJJ practitioner who trains 3–5 sessions per week, records rounds regularly, and wants to train smarter without adding hours of screen time to an already demanding practice schedule.

---

## 3. Goals & Non-Goals

### 3.1 MVP Goals

- **Fully automated event detection:** zero manual tagging required from the practitioner.
- **Clip-level coaching narrative:** every detected event receives an AI-generated contextual note.
- **Personal film library:** all clips, tags, timestamps, and summaries accessible from a single UI.
- **End-to-end local execution:** the entire pipeline runs on Minikube with no external cloud dependency.
- **Scalable data model:** schema designed from day one for future multi-athlete extension via OpenRewrite migrations.

### 3.2 Non-Goals (MVP)

- Multi-user authentication or team management
- Real-time video streaming or live session processing
- Mobile application or native client
- External cloud hosting or SaaS infrastructure
- Sigstore artifact signing *(post-MVP)*
- OpenRewrite schema migrations *(post-MVP, though schema is designed for it)*
- Leg lock or wrestling-specific detection classes *(post-MVP model expansion)*

---

## 4. User Stories

### US-01 — Video Ingest
As a practitioner, I want to drop a video file into a watched folder and have the pipeline start automatically, so that I never have to manually trigger processing.

### US-02 — Event Detection
As a practitioner, I want the system to detect submission attempts and positional events in my footage without any configuration or tagging on my part, so that I can get insight without doing the work myself.

### US-03 — Auto-Clipping
As a practitioner, I want each detected event to be automatically clipped into a short video segment, so that I can review specific moments without scrubbing through full footage.

### US-04 — AI Coaching Note
As a practitioner, I want each clip to have a plain-language coaching note that explains what happened, what led to it, and what I should focus on, so that I have a starting point for self-correction even without a coach present.

### US-05 — Film Library
As a practitioner, I want to browse all my processed clips by session, event type, position, and date, so that I can find specific moments quickly without remembering which video file they were in.

### US-06 — Session Summary
As a practitioner, I want a session-level summary after each processed video that calls out the most significant patterns detected — not just a list of events — so that I have a single coaching narrative to review before my next session.

### US-07 — Confidence Visibility
As a practitioner, I want to see the confidence score for each detection, so that I can calibrate how much weight to give any given clip and flag low-confidence events for review.

---

## 5. Functional Requirements

### 5.1 Video Ingest Service

- **FR-01:** The system SHALL watch a designated input folder for new video files.
- **FR-02:** Supported formats: MP4, MOV, AVI. Additional formats are post-MVP.
- **FR-03:** On detection of a new file, the system SHALL create a session record in the database and enqueue the file for processing.
- **FR-04:** Processing state (`queued`, `processing`, `complete`, `error`) SHALL be persisted and visible in the UI.

### 5.2 Vision Inference Service

- **FR-05:** The service SHALL run a Roboflow-hosted custom model against each ingested video.
- **FR-06:** MVP detection classes: Guard, Mount, Side Control, Back Control, Turtle, Triangle Attempt, Armbar Attempt, Rear Naked Choke Attempt, Guard Pass, Back Take.
- **FR-07:** Each detection SHALL include: class label, timestamp range (start/end), confidence score (0–1), bounding box data.
- **FR-08:** Detections with confidence below 0.60 SHALL be stored but flagged as low-confidence in the UI.

### 5.3 Auto-Clip Service

- **FR-09:** For each detection event, the service SHALL extract a video clip using FFmpeg.
- **FR-10:** Clip boundaries SHALL include a 3-second pre-event buffer and a 5-second post-event buffer.
- **FR-11:** Clips SHALL be stored locally in a configured output directory and referenced in the database.
- **FR-12:** Clips SHALL be named with a deterministic pattern: `{session_id}_{event_type}_{timestamp_ms}.mp4`.

### 5.4 AI Analysis Service (LangChain)

- **FR-13:** For each clip, the service SHALL generate a coaching note using LangChain with the Claude API.
- **FR-14:** The prompt context SHALL include: detected event type, timestamp, adjacent events in the session (±60 seconds), and session-level detection history.
- **FR-15:** Each coaching note SHALL address: what happened, what preceded it, and one specific corrective focus.
- **FR-16:** After all clips in a session are annotated, the service SHALL generate a session-level summary identifying the top 2–3 patterns.
- **FR-17:** All AI-generated content SHALL be stored in the database alongside the clip record.

### 5.5 Data Storage (Supabase / PostgreSQL)

- **FR-18:** The system SHALL use Supabase (local instance) as the primary data store.
- **FR-19:** Core tables: `sessions`, `events`, `clips`, `coaching_notes`, `session_summaries`.
- **FR-20:** The schema SHALL include a `practitioner_id` foreign key on all core tables to support future multi-athlete extension without a structural migration.
- **FR-21:** Event taxonomy SHALL be stored in a separate `event_types` table to allow vocabulary extension without application code changes.

### 5.6 Film Library UI

- **FR-22:** The UI SHALL provide a browsable library of all processed clips.
- **FR-23:** Filter controls SHALL include: session date, event type, confidence level, position class.
- **FR-24:** Each clip card SHALL display: thumbnail (first frame), event type tag, timestamp, confidence score, and coaching note preview.
- **FR-25:** Clicking a clip SHALL open a detail view with the full clip player, complete coaching note, and event timeline for the surrounding session window.
- **FR-26:** A session view SHALL show all events in chronological order for a single session, with the session summary at the top.
- **FR-27:** A position frequency heatmap SHALL be displayed at the session and library level.

---

## 6. Non-Functional Requirements

### 6.1 Performance

- **NFR-01:** Processing time for a 10-minute video SHALL complete within 20 minutes on consumer-grade hardware (i7 / 16 GB RAM).
- **NFR-02:** The UI SHALL load the full clip library within 2 seconds for a library of up to 500 clips.

### 6.2 Reliability

- **NFR-03:** If the inference service fails on a video, the session SHALL be marked as `error` state and retriable without data loss.
- **NFR-04:** Partial processing (ingest complete, inference failed) SHALL be recoverable from the point of failure.

### 6.3 Extensibility

- **NFR-05:** Each pipeline stage SHALL run as an independent Kubernetes service, allowing individual services to be updated without redeploying the full stack.
- **NFR-06:** The database schema SHALL be OpenRewrite-ready: all tables include version metadata fields and the event taxonomy is externalized to enable safe schema migrations as detection vocabulary grows.

### 6.4 Security

- **NFR-07:** All API keys (Roboflow, Claude) SHALL be injected via Kubernetes secrets, never hardcoded.
- **NFR-08:** Supabase row-level security SHALL be enabled from day one, scoped to the single practitioner record.

---

## 7. System Architecture

### 7.1 Deployment Environment

The MVP runs entirely on a local Ubuntu machine using Minikube as the Kubernetes runtime. All services are containerized using Chainguard free-tier base images. A local Supabase instance serves as the data layer. No external cloud services are required except the Roboflow inference API and the Anthropic Claude API.

### 7.2 Services

| Service | Status | Notes |
|---|---|---|
| Ingest Watcher | MVP | File system watcher; Go + Kubernetes Deployment |
| Inference Service | MVP | Calls Roboflow hosted model API; Go service |
| Clip Service | MVP | FFmpeg wrapper; Go service |
| Analysis Service | MVP | LangChain + Claude API; Python service |
| API Gateway | MVP | Go + Gin; exposes REST endpoints to the UI |
| UI | MVP | Vanilla JS, served by Nginx |
| Supabase (local) | MVP | PostgreSQL + Storage; local instance |
| Sigstore Signing | Post-MVP | Artifact signing for processed clips and inference results |
| OpenRewrite Runner | Post-MVP | Schema migration automation as detection vocabulary grows |

### 7.3 Pipeline Flow

The following sequence describes the end-to-end processing pipeline for a single video file:

1. Practitioner drops a video file into the watched input folder.
2. Ingest Watcher detects the new file and creates a session record in Supabase (`status: queued`).
3. Ingest Watcher publishes a processing job to the internal queue.
4. Inference Service picks up the job, runs the Roboflow model against the video, and writes detection events to Supabase (`status: inference_complete`).
5. Clip Service reads all events for the session and generates FFmpeg clip commands; clips are written to local storage and paths recorded in Supabase (`status: clips_ready`).
6. Analysis Service reads all clips and their detection context, calls the LangChain pipeline for each, and writes coaching notes and session summary to Supabase (`status: complete`).
7. UI polling detects the status change and makes the session available in the film library.

---

## 8. Data Model

### 8.1 Core Tables

| Table | Purpose |
|---|---|
| `practitioners` | Single-row in MVP; holds practitioner identity. Enables future multi-athlete extension. |
| `sessions` | One record per ingested video file. Tracks file path, processing status, and timestamps. |
| `event_types` | Lookup table for detection classes (e.g., `rear_naked_choke`, `back_take`). Extensible without code changes. |
| `events` | One record per detection. References session, event_type, timestamps, confidence, and bounding box. |
| `clips` | One record per generated video clip. References the parent event and local file path. |
| `coaching_notes` | AI-generated note per clip. References clip and stores raw LangChain output and prompt version. |
| `session_summaries` | AI-generated session-level summary. References session; stores top patterns and corrective focus areas. |

### 8.2 Schema Design Principles

- **`practitioner_id` on all core tables:** enables row-level security now; enables multi-athlete extension without structural migration later.
- **Externalized event taxonomy:** detection classes are data, not enums. New positions or submissions are added to `event_types` without a schema change.
- **`prompt_version` on `coaching_notes`:** tracks which prompt version generated each note, enabling re-generation comparisons as prompts improve.
- **`schema_version` on `sessions`:** OpenRewrite-compatibility marker; enables automated migration tooling to identify records generated under each schema version.

### 8.3 Schema Sketch

```sql
-- Practitioners
CREATE TABLE practitioners (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Sessions
CREATE TABLE sessions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  practitioner_id  UUID REFERENCES practitioners(id),
  file_path        TEXT NOT NULL,
  status           TEXT NOT NULL DEFAULT 'queued',
  schema_version   INTEGER NOT NULL DEFAULT 1,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

-- Event Types (lookup)
CREATE TABLE event_types (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug      TEXT UNIQUE NOT NULL,  -- e.g. 'rear_naked_choke'
  label     TEXT NOT NULL,         -- e.g. 'Rear Naked Choke'
  category  TEXT NOT NULL          -- 'position' | 'transition' | 'submission'
);

-- Events
CREATE TABLE events (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id       UUID REFERENCES sessions(id),
  practitioner_id  UUID REFERENCES practitioners(id),
  event_type_id    UUID REFERENCES event_types(id),
  start_ms         INTEGER NOT NULL,
  end_ms           INTEGER NOT NULL,
  confidence       NUMERIC(4,3) NOT NULL,
  bounding_box     JSONB,
  low_confidence   BOOLEAN GENERATED ALWAYS AS (confidence < 0.60) STORED,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- Clips
CREATE TABLE clips (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id         UUID REFERENCES events(id),
  practitioner_id  UUID REFERENCES practitioners(id),
  file_path        TEXT NOT NULL,
  thumbnail_path   TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- Coaching Notes
CREATE TABLE coaching_notes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clip_id         UUID REFERENCES clips(id),
  content         TEXT NOT NULL,
  prompt_version  INTEGER NOT NULL DEFAULT 1,
  model           TEXT NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- Session Summaries
CREATE TABLE session_summaries (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID REFERENCES sessions(id),
  content         TEXT NOT NULL,
  prompt_version  INTEGER NOT NULL DEFAULT 1,
  model           TEXT NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

---

## 9. Detection Model Strategy

### 9.1 Model Training Approach

The Roboflow custom model will be trained on labeled BJJ footage using a two-phase strategy:

- **Phase 1 — Bootstrap (MVP):** Label a minimum of 500 frames covering the 10 MVP detection classes. Prioritize diversity over volume: multiple practitioners, angles, gi and no-gi.
- **Phase 2 — Iteration (post-MVP):** Use model confidence logs from real sessions to identify high-error classes and add targeted training data. Leg locks, wrestling sequences, and escapes are planned expansion classes.

### 9.2 MVP Detection Classes

| Class | Category |
|---|---|
| Guard | Position |
| Half Guard | Position |
| Mount | Position |
| Side Control | Position |
| Back Control | Position |
| Turtle | Position |
| Back Take | Transition |
| Guard Pass | Transition |
| Triangle Attempt | Submission |
| Armbar Attempt | Submission |
| Rear Naked Choke (RNC) | Submission |

### 9.3 Labeling Guidelines

- Label at 1–2 frames per second for position classes; label the start and peak frames for submissions.
- Include both gi and no-gi footage from the first labeling session.
- Do not over-label any single practitioner — model generalization requires diverse body types and movement styles.
- Use Roboflow's smart polygon tool for bounding boxes; body-level boxes are sufficient for MVP (not joint-level).

> **Training Note:** 500 labeled frames is the minimum viable starting point. The first model version will have meaningful gaps. Treat the model as a living artifact that improves with each session's data — not a one-time deliverable.

---

## 10. AI Coaching Pipeline

### 10.1 LangChain Architecture

The analysis service uses LangChain to orchestrate two prompt chains:

- **Clip-level chain:** takes a single event and its ±60-second detection context as input. Outputs a coaching note (3–5 sentences) addressing what happened, what preceded it, and one corrective focus.
- **Session-level chain:** takes all clip-level coaching notes for a session as input. Identifies the top 2–3 patterns across the session and outputs a consolidated summary with prioritized corrective focus areas.

### 10.2 Prompt Constraints

- Coaching notes SHALL NOT use jargon the practitioner hasn't introduced via their own session tags.
- The session summary SHALL identify patterns across events, not repeat individual clip notes.
- Tone SHALL be direct and specific — observations over encouragement.
- No submission or position SHALL be described as definitive without a confidence score above 0.80.

### 10.3 Model Configuration

| Parameter | Value |
|---|---|
| Model | `claude-sonnet-4-20250514` |
| Max tokens | 600 (clip note) / 1000 (session summary) |
| Temperature | 0.3 (coaching notes) / 0.5 (session summary) |
| Prompt version | Tracked in `coaching_notes.prompt_version` |

### 10.4 Example Coaching Note

> **Detected:** Rear Naked Choke — Back Control (1:42–2:00) — Confidence: 0.94
>
> *"You gave up the back at 1:42 after a failed single leg. You transitioned to turtle position and were finished with an RNC 18 seconds later. Your chin was not tucked on the initial back take — drilling defensive chin tuck under fatigue conditions should be your immediate priority."*

---

## 11. MVP Feature Matrix

| Feature | Status | Notes |
|---|---|---|
| Folder-based video ingest | MVP | Watched directory; Go file watcher |
| MP4 / MOV / AVI support | MVP | FFmpeg format detection |
| Roboflow inference (11 classes) | MVP | Hosted API; custom-trained model |
| Auto-clip generation (FFmpeg) | MVP | 3s pre / 5s post event buffer |
| LangChain clip-level coaching note | MVP | Claude API; prompt v1 |
| LangChain session summary | MVP | Cross-clip pattern synthesis |
| Supabase local data store | MVP | PostgreSQL + Storage |
| Film library UI | MVP | Vanilla JS / Nginx |
| Session view + event timeline | MVP | Chronological event list |
| Position frequency heatmap | MVP | Session and library level |
| Confidence score display | MVP | Per clip; flagged below 0.60 |
| Processing status tracking | MVP | queued → complete / error |
| Sigstore artifact signing | Post-MVP | Clip and inference provenance |
| OpenRewrite schema migrations | Post-MVP | As detection vocabulary expands |
| Leg lock detection classes | Post-MVP | Phase 2 model expansion |
| Multi-athlete support | Post-MVP | Schema ready; app layer not |
| Cloud deployment | Post-MVP | Minikube → managed K8s |
| Mobile client | Post-MVP | Web-first MVP |

---

## 12. Build Plan

### 12.1 Phase Overview

| Phase | Description |
|---|---|
| Phase 1 — Infrastructure | Minikube cluster setup, Supabase local instance, base container images, service scaffolding, Nginx UI shell. |
| Phase 2 — Ingest + Inference | File watcher service, Roboflow model training (500 frames), inference service, event storage. |
| Phase 3 — Clip + Analysis | FFmpeg clip service, LangChain coaching pipeline, session summary chain. |
| Phase 4 — UI | Film library, clip cards, session view, event timeline, position heatmap, filter controls. |
| Phase 5 — Validation | End-to-end test with real footage, error handling, confidence calibration, performance check. |

### 12.2 Time Estimate

Based on a solo developer using Claude Code and Cursor (Plan Mode), working approximately 10 hours per week:

| Phase | Estimated Hours |
|---|---|
| Phase 1 — Infrastructure | 8–12 hrs |
| Phase 2 — Ingest + Inference | 28–40 hrs *(includes model labeling)* |
| Phase 3 — Clip + Analysis | 18–24 hrs |
| Phase 4 — UI | 10–15 hrs |
| Phase 5 — Validation | 8–12 hrs |
| **Total** | **72–103 hrs (~2–3 months at 10 hrs/week)** |

> **Critical Path Warning:** Roboflow model labeling is the highest-risk phase. Set a hard timebox of 2 weeks for initial labeling (500 frames). Do not block pipeline development on a perfect model — a functional but imperfect model unblocks the rest of the build.

---

## 13. Learning Objectives

GRAPPL is designed as a learning vehicle as much as a product. Each component is intentionally chosen to develop proficiency across the following areas:

| Technology | What You'll Learn |
|---|---|
| Kubernetes / Minikube | Service decomposition, deployment manifests, service discovery, resource limits, rolling updates. |
| Roboflow | Dataset curation, model training, inference API integration, confidence calibration, iterative model improvement. |
| LangChain | Prompt chain design, context window management, multi-step reasoning, output parsing, temperature tuning. |
| Supabase / PostgreSQL | Schema design, row-level security, query optimization, local instance management, migrations. |
| FFmpeg | Video processing, segment extraction, format handling, stream manipulation. |
| OpenRewrite | Schema evolution strategy, recipe authoring, automated migration — post-MVP but designed for from day one. |
| Sigstore | Artifact signing, keyless verification, supply chain provenance — post-MVP. |
| Go (Gin) | Service scaffolding, REST API design, concurrent processing, Kubernetes-native patterns. |
| Containers | Chainguard base images, multi-stage builds, local registry, image provenance. |

---

## 14. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Model accuracy insufficient for useful detections | High | Timebox labeling; treat first model as v0; build pipeline around the model, not after it. |
| Kubernetes complexity blocks pipeline progress | Medium | Use simple Deployments before exploring advanced patterns; Cursor + Claude Code for manifest generation. |
| LangChain coaching notes are generic / unhelpful | Medium | Iterate prompts with real detection data early; store `prompt_version` to compare generations. |
| Roboflow API costs spike with volume | Low | MVP processes footage in batch, not real-time. Monitor usage and cache inference results. |
| Local Supabase instance instability | Low | Use Docker-based local Supabase; script backup/restore from day one. |
| FFmpeg clip extraction misaligns with events | Low | Buffer windows (3s pre / 5s post) absorb timestamp imprecision; tune based on real footage. |

---

## 15. MVP Success Criteria

The MVP is considered complete when all of the following are true:

1. A raw video file dropped into the input folder is processed end-to-end without manual intervention.
2. At least 8 of the 11 MVP detection classes are detected with >75% precision on held-out footage.
3. Every detected event has an auto-generated clip and a coaching note.
4. A session summary is generated that identifies at least one cross-clip pattern from the session.
5. All clips and metadata are browsable in the film library UI with functional filter controls.
6. The full pipeline runs stably in Minikube for at least 5 consecutive sessions without manual intervention.
7. Processing a 10-minute video completes within 20 minutes on the development machine.

---

## 16. Post-MVP Roadmap

### V1.1 — Expanded Detection
- Leg lock detection classes (heel hook, kneebar, ankle lock)
- Wrestling-specific transitions (double leg, single leg, sprawl)
- Escape sequences (bridge and roll, elbow-knee, shrimping series)

### V1.2 — Artifact Integrity
- Sigstore signing on all processed clips and inference result sets
- Supabase audit log for all detection and coaching note records
- OpenRewrite recipes for schema migrations as detection vocabulary expands

### V2.0 — Multi-Athlete (Commercial Pivot)
- Coach-facing dashboard with athlete roster management
- Per-athlete film libraries with shared session view
- Subscription infrastructure (Stripe) and cloud deployment
- Team comparison analytics — positional frequency across the roster

> **Scaling Note:** The `practitioner_id` key structure, externalized event taxonomy, and OpenRewrite-ready schema mean the data model built in MVP Phase 1 requires zero structural migration to support a multi-athlete V2.0. The scale point is the application layer, not the database.

---

## Appendix — Technology Reference

| Component | Technology |
|---|---|
| Backend services | Go 1.22+ with Gin framework |
| AI analysis service | Python 3.12+ with LangChain |
| Container runtime | Minikube (local Kubernetes) |
| Base images | Chainguard free-tier (Go, Python, Nginx) |
| Database | Supabase (local) — PostgreSQL 15+ |
| Vision model | Roboflow hosted custom model |
| LLM | Anthropic Claude (`claude-sonnet-4-20250514`) |
| Video processing | FFmpeg 6+ |
| UI stack | Vanilla JavaScript, served by Nginx |
| IDE / AI tooling | Cursor (Plan Mode) + Claude Code |
| Schema migration | OpenRewrite (post-MVP) |
| Artifact signing | Sigstore / Cosign (post-MVP) |
| Host OS | Ubuntu 22.04 LTS |

---

*GRAPPL — MVP PRD v1.0 — Confidential*
