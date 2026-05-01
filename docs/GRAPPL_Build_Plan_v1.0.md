# GRAPPL — Cursor Plan Mode Build Plan
## MVP v1.0 — Sequential Task Guide

> **How to use this file:**
> Each task below is a self-contained prompt written to be pasted directly into Cursor's Plan Mode. Tasks are strictly sequential — do not begin a task until the validation gate for the previous task passes. Tasks marked `[MANUAL]` require hands-on work outside Cursor before proceeding.
>
> **Reference files available in your repo:**
> - `docs/GRAPPL_PRD_MVP_v1.0.md` — full product requirements
> - `docs/bjj-film-platform.html` — UI reference mockup

---

## Phase 1 — Infrastructure

### Task 1.1 — Repo Structure & Monorepo Scaffold

```
Using docs/GRAPPL_PRD_MVP_v1.0.md as the source of truth for services and stack,
scaffold the full monorepo directory structure for the GRAPPL project.

Create the following top-level layout:

grappl/
├── docs/                         # already exists
├── services/
│   ├── ingest/                   # Go — file watcher
│   ├── inference/                # Go — Roboflow API client
│   ├── clip/                     # Go — FFmpeg wrapper
│   ├── analysis/                 # Python — LangChain pipeline
│   └── gateway/                  # Go + Gin — REST API
├── ui/                           # Vanilla JS + Nginx
├── infra/
│   ├── k8s/                      # Kubernetes manifests
│   │   ├── namespace.yaml
│   │   ├── secrets/              # secret manifest templates (no real values)
│   │   └── deployments/          # one folder per service
│   └── supabase/
│       └── migrations/           # numbered SQL migration files
├── scripts/                      # setup and utility shell scripts
├── .env.example                  # all required env vars with placeholder values
├── .gitignore                    # Go, Python, Node, .env, kubeconfig
└── README.md                     # project overview linking to docs/

For each Go service directory, create:
- main.go (package main stub)
- go.mod (module name: github.com/grappl/{service})
- Dockerfile (empty stub, will be filled in Task 1.4)
- README.md (one-line description of the service)

For the analysis/ Python service, create:
- main.py (stub)
- requirements.txt (empty)
- Dockerfile (stub)
- README.md

For ui/, create:
- index.html (HTML5 boilerplate only)
- app.js (empty)
- styles.css (empty)
- nginx.conf (basic static file server config on port 80)
- Dockerfile (stub)

Do not write any application logic yet. This task is structure only.
```

**Validation gate:** `find . -type f | sort` shows the complete tree above with no missing directories. All Go modules initialize without error (`go mod verify` in each service dir).

---

### Task 1.2 — Minikube Setup Script

```
Create scripts/setup-minikube.sh — a fully commented bash script that:

IMPORTANT: GRAPPL runs in a dedicated minikube profile named 'grappl'
(--profile=grappl / -p grappl) to avoid interfering with any other
applications using the default 'minikube' profile on this machine.
Every minikube command in this script and in all other GRAPPL scripts
must include --profile=grappl (or the short form -p grappl).
Set MINIKUBE_PROFILE="grappl" at the top of the script and reference it
throughout. The kubeconfig context name will also be 'grappl'; pass
--context=grappl to kubectl commands where needed.

Resource flags (--cpus, --memory, --disk-size) only apply on first
cluster creation. Re-running the script on an existing profile is safe.
To change resources, delete the profile first: minikube delete -p grappl

1. Checks for minikube, kubectl, and docker. Exits with a clear error message
   if any are missing, telling the user what to install.

2. Starts minikube with the following config:
   - Profile: grappl  (--profile=grappl)
   - Driver: docker
   - CPUs: 4
   - Memory: 8192mb
   - Disk: 40000mb
   - Kubernetes version: stable

3. Enables the following minikube addons (all with --profile=grappl):
   - ingress
   - metrics-server
   - dashboard
   Do NOT enable the registry addon — it is unreliable with the Docker
   driver and is not needed. All images are built directly into the
   cluster's Docker daemon via eval $(minikube docker-env -p grappl).

4. Prints a note explaining the image build strategy:
   eval $(minikube docker-env -p grappl)
   docker build -t grappl/<service>:local services/<service>/
   Images built this way are immediately available to Kubernetes pods
   with no push or registry step required.

5. Configures the local docker daemon to use the minikube daemon
   by running: eval $(minikube docker-env -p grappl)
   Then prints a reminder that this eval must be re-run in any new terminal.

6. Creates the grappl Kubernetes namespace:
   kubectl apply -f infra/k8s/namespace.yaml --context=grappl

7. Prints a final status summary:
   - minikube status -p grappl
   - kubectl get nodes --context=grappl
   - minikube addons list -p grappl (filtered to only show enabled addons)
   - Reminder: minikube profile grappl  (to set as active profile)

Also create infra/k8s/namespace.yaml:

apiVersion: v1
kind: Namespace
metadata:
  name: grappl
  labels:
    app: grappl
    env: local

Make the script idempotent — running it twice should not produce errors.
```

**Validation gate:** Running `bash scripts/setup-minikube.sh` completes without errors. `kubectl get nodes --context=grappl` shows a Ready node. `kubectl get namespace grappl --context=grappl` exists. `minikube status -p grappl` shows Running. The default 'minikube' profile (if present) is unaffected.

---

### Task 1.3 — Supabase Local Instance Setup Script

```
Create scripts/setup-supabase.sh — a bash script that:

1. Checks for the Supabase CLI (supabase). Exits with install instructions
   if not found (https://supabase.com/docs/guides/cli).

2. Runs `supabase init` in the project root if a supabase/ config dir
   doesn't already exist.

3. After init (and before starting), patch supabase/config.toml to use
   non-default ports so this project can run alongside other local Supabase
   projects without port conflicts. Set the following in config.toml:

   [api]
   port = 54331

   [db]
   port = 54332

   [studio]
   port = 54333

   [inbucket]
   port = 54334

   [analytics]
   port = 54337

   Use sed or a config-aware tool to set these values. Skip this step if
   the ports are already set to the correct values (idempotent).

4. Runs `supabase start` and captures the output.

5. Parses and prints the following values from supabase start output:
   - API URL
   - anon key
   - service_role key
   - DB URL
   - Studio URL

6. Writes these values to .env.local (gitignored) in the format:
   SUPABASE_URL=...
   SUPABASE_ANON_KEY=...
   SUPABASE_SERVICE_ROLE_KEY=...
   DATABASE_URL=...

7. Prints: "Supabase Studio is available at: http://localhost:54333"

Also update .env.example to reflect the non-default ports:
   SUPABASE_URL=http://127.0.0.1:54331
   SUPABASE_DB_URL=postgresql://postgres:postgres@127.0.0.1:54332/postgres
Include a comment explaining where to find the real values after running
setup-supabase.sh.

Make the script idempotent — if supabase is already running, print
its current status instead of erroring.
```

**Validation gate:** `supabase status` shows all services running. Supabase Studio is reachable at `http://localhost:54333`. `.env.local` exists with all four values populated. Running the script a second time does not error.

---

### Task 1.4 — Chainguard Dockerfiles for All Services

```
Write production-grade Dockerfiles for all five services using Chainguard
free-tier base images. Refer to docs/GRAPPL_PRD_MVP_v1.0.md (Appendix)
for the confirmed stack per service.

Requirements for all Dockerfiles:
- Use multi-stage builds
- Final image must use a Chainguard distroless base (cgr.dev/chainguard/...)
- Run as non-root user
- No shell in the final stage
- COPY only the compiled binary or required runtime files

Services and their base images:

1. services/ingest/Dockerfile
   Builder:  cgr.dev/chainguard/go:latest
   Final:    cgr.dev/chainguard/static:latest
   Binary:   /ingest

2. services/inference/Dockerfile
   Builder:  cgr.dev/chainguard/go:latest
   Final:    cgr.dev/chainguard/static:latest
   Binary:   /inference

3. services/clip/Dockerfile
   Builder:  cgr.dev/chainguard/go:latest
   Final:    cgr.dev/chainguard/glibc-dynamic:latest
   Note:     The clip service needs FFmpeg. Install ffmpeg in the final stage
             using the Chainguard wolfi package (apk add ffmpeg).
             Use cgr.dev/chainguard/wolfi-base as the final stage instead
             of static, since we need a package manager.
   Binary:   /clip

4. services/analysis/Dockerfile
   Builder:  cgr.dev/chainguard/python:latest-dev
   Final:    cgr.dev/chainguard/python:latest
   Note:     Install requirements.txt in builder stage, copy site-packages
             to final stage.
   Entrypoint: python main.py

5. services/gateway/Dockerfile
   Builder:  cgr.dev/chainguard/go:latest
   Final:    cgr.dev/chainguard/static:latest
   Binary:   /gateway

6. ui/Dockerfile
   Builder:  (none needed — static files only)
   Final:    cgr.dev/chainguard/nginx:latest
   COPY:     index.html, app.js, styles.css to /usr/share/nginx/html/
   COPY:     ui/nginx.conf to /etc/nginx/conf.d/default.conf

Also create scripts/build-images.sh that:
- Runs eval $(minikube docker-env -p grappl) to target the grappl cluster's
  Docker daemon (images built this way are immediately available to Kubernetes
  without a push step)
- Builds all six images with tags: grappl/{service}:local
- Prints build success/failure for each image
```

**Validation gate:** `bash scripts/build-images.sh` completes. `docker images | grep grappl` shows all six images. Each image runs without error when launched with `docker run --rm grappl/{service}:local` (they will exit immediately since logic is stubbed, but must not panic or produce image errors).

---

### Task 1.5 — Kubernetes Secret Manifests & Config

```
Create the Kubernetes secrets infrastructure for GRAPPL. All API keys
and credentials must be injected via Kubernetes secrets — never hardcoded.

1. Create infra/k8s/secrets/secrets.yaml.example:
   A template showing the structure of all required secrets with
   placeholder base64 values and comments explaining each one.
   Include secrets for:
   - ROBOFLOW_API_KEY
   - ANTHROPIC_API_KEY
   - SUPABASE_URL
   - SUPABASE_SERVICE_ROLE_KEY
   - DATABASE_URL

2. Create scripts/create-secrets.sh:
   A script that reads from .env.local and creates the Kubernetes
   secret in the grappl namespace:

   kubectl create secret generic grappl-secrets \
     --from-env-file=.env.local \
     --namespace=grappl \
     --dry-run=client -o yaml | kubectl apply -f -

   The --dry-run + apply pattern makes it idempotent (updates if exists).

3. Create infra/k8s/configmap.yaml:
   A ConfigMap for non-sensitive config shared across services:
   - INPUT_FOLDER: /data/input
   - OUTPUT_FOLDER: /data/clips
   - CONFIDENCE_THRESHOLD: "0.60"
   - CLIP_PRE_BUFFER_SECONDS: "3"
   - CLIP_POST_BUFFER_SECONDS: "5"
   - MAX_TOKENS_CLIP_NOTE: "600"
   - MAX_TOKENS_SESSION_SUMMARY: "1000"
   - ANALYSIS_MODEL: claude-sonnet-4-20250514

4. Create infra/k8s/pvc.yaml:
   A PersistentVolumeClaim for shared video/clip storage:
   - Name: grappl-data
   - AccessMode: ReadWriteMany
   - Storage: 50Gi
   - StorageClassName: standard (minikube default)

Add secrets.yaml and .env.local to .gitignore.
```

**Validation gate:** `bash scripts/create-secrets.sh` runs without error. `kubectl get secret grappl-secrets -n grappl` exists. `kubectl get configmap grappl-config -n grappl` exists. `kubectl get pvc grappl-data -n grappl` is Bound.

---

### Task 1.6 — Nginx UI Shell & Kubernetes Deployment

```
Build out the initial UI shell and deploy it to Minikube so we have
a running endpoint to build against from Phase 4.

1. Update ui/index.html:
   A minimal but styled HTML page using the design language from
   docs/bjj-film-platform.html (black background #080808, white text
   #F5F5F0, scarlet accent #C1121F, Bebas Neue + Cormorant Garamond fonts
   via Google Fonts CDN).

   The shell should include:
   - A top nav bar with the GRAPPL logo and placeholder nav links
   - A centered "Pipeline initializing..." status message
   - A footer with the stack label
   No real data or API calls yet — this is a visual placeholder only.

2. Update ui/nginx.conf to:
   - Serve static files from /usr/share/nginx/html
   - Return index.html for any unmatched route (SPA fallback)
   - Set correct MIME types for .js and .css
   - Add a /health endpoint that returns 200 OK with body "ok"

3. Create infra/k8s/deployments/ui.yaml:
   - Deployment: 1 replica, image grappl/ui:local
   - Resources: requests 50m CPU / 64Mi memory, limits 100m / 128Mi
   - Liveness probe: GET /health every 10s
   - Service: ClusterIP on port 80
   - ConfigMap and secret env vars injected

4. Create infra/k8s/ingress.yaml:
   - Expose the UI service at host: grappl.local
   - Path: / → ui service port 80

5. Create scripts/add-hosts.sh:
   Prints the minikube IP and the /etc/hosts entry to add:
   $(minikube ip -p grappl)  grappl.local
   (Do not auto-edit /etc/hosts — just print the line for the user.)

6. Create scripts/deploy.sh:
   Applies all manifests in infra/k8s/ in the correct order:
   namespace → pvc → configmap → secrets → deployments → ingress
   Uses kubectl apply -f with --namespace=grappl.
   Prints rollout status for each deployment after applying.
```

**Validation gate:** `bash scripts/deploy.sh` applies cleanly. `kubectl get pods -n grappl` shows the UI pod Running. After adding the hosts entry, `curl http://grappl.local` returns the HTML shell. `curl http://grappl.local/health` returns `ok`.

---

## Phase 2 — Ingest + Inference

### Task 2.1 — Database Schema (Supabase Migrations)

```
Create the complete GRAPPL database schema as numbered Supabase migration files
in infra/supabase/migrations/. Reference docs/GRAPPL_PRD_MVP_v1.0.md
section 8 (Data Model) as the authoritative schema spec.

Migration files (run in order):

001_enable_extensions.sql
  - Enable: uuid-ossp, pgcrypto

002_create_practitioners.sql
  CREATE TABLE practitioners (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  INSERT a single default practitioner row:
    id: a fixed UUID (use gen_random_uuid() once and hardcode it)
    name: 'default'
  This single row is the anchor for all MVP data.

003_create_event_types.sql
  CREATE TABLE event_types (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug      TEXT UNIQUE NOT NULL,
    label     TEXT NOT NULL,
    category  TEXT NOT NULL CHECK (category IN ('position','transition','submission'))
  );
  Seed all 11 MVP detection classes from PRD section 9.2.

004_create_sessions.sql
  CREATE TABLE sessions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    practitioner_id  UUID NOT NULL REFERENCES practitioners(id),
    file_name        TEXT NOT NULL,
    file_path        TEXT NOT NULL,
    status           TEXT NOT NULL DEFAULT 'queued'
                       CHECK (status IN ('queued','processing','inference_complete',
                                         'clips_ready','complete','error')),
    error_message    TEXT,
    schema_version   INTEGER NOT NULL DEFAULT 1,
    duration_seconds INTEGER,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ON sessions(practitioner_id, created_at DESC);
  CREATE INDEX ON sessions(status);

005_create_events.sql
  CREATE TABLE events (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id       UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    practitioner_id  UUID NOT NULL REFERENCES practitioners(id),
    event_type_id    UUID NOT NULL REFERENCES event_types(id),
    start_ms         INTEGER NOT NULL,
    end_ms           INTEGER NOT NULL,
    confidence       NUMERIC(4,3) NOT NULL,
    bounding_box     JSONB,
    low_confidence   BOOLEAN GENERATED ALWAYS AS (confidence < 0.60) STORED,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ON events(session_id, start_ms);
  CREATE INDEX ON events(practitioner_id, event_type_id);

006_create_clips.sql
  CREATE TABLE clips (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id         UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    practitioner_id  UUID NOT NULL REFERENCES practitioners(id),
    file_path        TEXT NOT NULL,
    thumbnail_path   TEXT,
    duration_seconds NUMERIC(6,2),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ON clips(event_id);

007_create_coaching_notes.sql
  CREATE TABLE coaching_notes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clip_id         UUID NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    prompt_version  INTEGER NOT NULL DEFAULT 1,
    model           TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  );

008_create_session_summaries.sql
  CREATE TABLE session_summaries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    prompt_version  INTEGER NOT NULL DEFAULT 1,
    model           TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  );

009_row_level_security.sql
  Enable RLS on all tables and add a permissive policy for the single-user
  MVP (allow all operations from the service role).
  We will tighten this in post-MVP when multi-user auth is added.

010_updated_at_trigger.sql
  Create a trigger function that auto-updates updated_at on sessions
  whenever a row is modified. Apply it to the sessions table.

Create scripts/run-migrations.sh:
  Runs all migration files in order using the Supabase CLI:
  supabase db push
  Then prints row counts for each table to confirm seeding.
```

**Validation gate:** `bash scripts/run-migrations.sh` applies all 10 migrations without error. `SELECT slug FROM event_types ORDER BY slug;` returns all 11 MVP classes. `SELECT * FROM practitioners;` returns 1 row.

---

### Task 2.2 — Shared Go Database Client Package

```
Create a shared Go package at services/shared/db/ that all Go services
will import for database access. This avoids duplicating Supabase/PostgreSQL
connection logic across the ingest, inference, clip, and gateway services.

The package must:

1. Use the pgx/v5 driver (github.com/jackc/pgx/v5).

2. Expose a Connect(ctx) function that:
   - Reads DATABASE_URL from environment
   - Returns a *pgxpool.Pool with connection pooling configured:
     MaxConns: 10
     MinConns: 2
     HealthCheckPeriod: 1 minute
   - Retries connection up to 5 times with exponential backoff
     before returning an error

3. Define Go structs matching every database table:
   - Practitioner
   - Session (include all status constants as typed string consts)
   - EventType
   - Event
   - Clip
   - CoachingNote
   - SessionSummary

4. Expose typed repository functions (not a full ORM — simple functions):
   - GetDefaultPractitioner(ctx, pool) (*Practitioner, error)
   - CreateSession(ctx, pool, filePath string) (*Session, error)
   - UpdateSessionStatus(ctx, pool, id UUID, status SessionStatus, errMsg string) error
   - GetEventTypeBySlug(ctx, pool, slug string) (*EventType, error)
   - CreateEvent(ctx, pool, event Event) (*Event, error)
   - GetEventsBySession(ctx, pool, sessionID UUID) ([]Event, error)
   - CreateClip(ctx, pool, clip Clip) (*Clip, error)
   - CreateCoachingNote(ctx, pool, note CoachingNote) (*CoachingNote, error)
   - CreateSessionSummary(ctx, pool, summary SessionSummary) (*SessionSummary, error)

5. Create a go.mod at services/shared/ with module name:
   github.com/grappl/shared

6. Update each Go service's go.mod to replace the shared module with
   the local path:
   replace github.com/grappl/shared => ../shared

Write a test file services/shared/db/db_test.go that:
- Skips if DATABASE_URL is not set
- Tests Connect(), GetDefaultPractitioner(), and CreateSession()
```

**Validation gate:** `cd services/shared && go test ./...` passes (or skips cleanly if DB not available). `go build ./...` in each Go service directory succeeds after the replace directive is added.

---

### Task 2.3 — Ingest Watcher Service

```
Implement the ingest watcher service at services/ingest/main.go.
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-01 through FR-04.

This service watches a folder for new video files and creates session
records in the database. It is the entry point of the entire pipeline.

Requirements:

1. On startup:
   - Connect to the database using the shared db package
   - Read INPUT_FOLDER from environment (default: /data/input)
   - Create the input folder if it doesn't exist
   - Log the watched path and confirm DB connection

2. Use github.com/fsnotify/fsnotify to watch INPUT_FOLDER recursively.
   On a Create or Write event for a file with extension
   .mp4, .mov, or .avi (case-insensitive):
   - Wait 2 seconds (file may still be copying)
   - Re-stat the file to confirm it is complete (size stable)
   - Call CreateSession(ctx, pool, filePath)
   - Log: "Session created: {session_id} for file: {filename}"
   - Move the file from INPUT_FOLDER to /data/processing/{session_id}/
     (create the directory first)
   - Call UpdateSessionStatus to 'processing'
   - POST to the inference service internal endpoint:
     http://inference.grappl.svc.cluster.local/process
     Body: { "session_id": "...", "file_path": "..." }
   - If the POST fails, update status to 'error' with the error message

3. Handle shutdown gracefully via SIGTERM/SIGINT:
   - Stop the watcher
   - Close the DB pool
   - Log "Ingest watcher shutting down"

4. Structured logging throughout using log/slog (stdlib, Go 1.21+).
   Log format: JSON. Include session_id and file_path in all relevant logs.

5. Add a /health HTTP endpoint on port 8080 returning 200 JSON:
   { "status": "ok", "watching": "/data/input" }

Create infra/k8s/deployments/ingest.yaml:
- Deployment with 1 replica
- Mount the grappl-data PVC at /data
- Inject grappl-secrets and grappl-config
- Liveness probe: GET :8080/health
- Resources: 50m CPU / 64Mi memory requests; 200m / 256Mi limits
```

**Validation gate:** Build the image (`docker build -t grappl/ingest:local services/ingest/`). Deploy to Minikube. `kubectl logs -n grappl deployment/ingest` shows "watching /data/input". Copying a test `.mp4` into the input folder via `kubectl cp` creates a session row in Supabase and logs the session ID.

---

### `[MANUAL]` Task 2.4 — Roboflow Dataset Creation & Labeling

> This task cannot be automated. Complete it before starting Task 2.5.

**Steps:**

1. Create a free account at [roboflow.com](https://roboflow.com).
2. Create a new project: **Object Detection**, name it `grappl-bjj`.
3. Upload your BJJ training footage. Roboflow can extract frames automatically — use **1 frame per second** for position classes, **2 frames per second** for submission sequences.
4. Label a minimum of **500 frames** covering all 11 MVP detection classes from PRD section 9.2. Use these guidelines:
   - Draw bounding boxes at the **body level** — full torso of the practitioner in the dominant position
   - For submissions, label the **aggressor's body** in the class frame
   - Include both gi and no-gi footage if available
   - Include different camera angles if available
5. Apply the Roboflow **Auto-Label** tool to accelerate labeling after the first 100 manual frames.
6. Add the following augmentations in the dataset version:
   - Flip: Horizontal
   - Rotation: ±15°
   - Brightness: ±25%
   - Blur: up to 1.5px
7. Generate a dataset version and **train using Roboflow's hosted training** (YOLOv8 recommended). Wait for training to complete.
8. Note your **Model ID**, **API Key**, and **Workspace slug** — you will need them in Task 2.5.

**Target metrics before proceeding:** mAP > 40% on held-out validation set. Lower is acceptable for MVP — the pipeline must be built around a functional but imperfect model.

---

### Task 2.5 — Inference Service

```
Implement the inference service at services/inference/main.go.
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-05 through FR-08.

This service receives a session job, runs the Roboflow model against
the video, and writes detection events to the database.

Requirements:

1. Expose a POST /process endpoint on port 8081:
   Request body: { "session_id": "uuid", "file_path": "/data/processing/..." }
   
   On receipt:
   - Validate the session exists and is in 'processing' status
   - Run inference (see step 2)
   - Write all events to the database
   - Update session status to 'inference_complete'
   - POST to clip service: http://clip.grappl.svc.cluster.local/process
     Body: { "session_id": "..." }
   - If anything fails, update session status to 'error'

2. Roboflow inference strategy:
   Roboflow does not natively accept full video files for batch inference.
   Use the following approach:
   a. Use ffmpeg (via exec.Command) to extract frames from the video
      at 2 fps into a temp directory: /tmp/{session_id}/frames/
      Command: ffmpeg -i {file_path} -vf fps=2 /tmp/{session_id}/frames/frame_%05d.jpg
   b. For each frame file, POST it to the Roboflow inference API:
      POST https://detect.roboflow.com/{ROBOFLOW_MODEL_ID}/{ROBOFLOW_VERSION}
      ?api_key={ROBOFLOW_API_KEY}
      Content-Type: multipart/form-data (file upload)
   c. Parse the JSON response predictions array:
      Each prediction: { class, confidence, x, y, width, height }
   d. Convert frame number back to millisecond timestamp:
      frame_number / 2 fps * 1000 = start_ms
      Use a fixed window of 1000ms for end_ms (one frame duration at 2fps)

3. Event deduplication:
   Consecutive frames with the same class label and overlapping bounding
   boxes (IoU > 0.5) should be merged into a single event with:
   - start_ms = first frame's timestamp
   - end_ms = last frame's timestamp  
   - confidence = max confidence across the merged frames

4. For each deduplicated event:
   - Look up event_type_id from event_types table using the class slug
     (normalize class names: lowercase, spaces → underscores)
   - Call CreateEvent() from the shared db package

5. Clean up temp frame directory after processing.

6. Add GET /health on port 8081.

7. Read from environment:
   ROBOFLOW_API_KEY, ROBOFLOW_MODEL_ID, ROBOFLOW_VERSION, DATABASE_URL

Create infra/k8s/deployments/inference.yaml:
- Deployment: 1 replica
- Mount grappl-data PVC at /data
- Resources: 200m CPU / 256Mi requests; 1000m / 1Gi limits
  (inference is the most CPU-intensive service)
- Inject secrets and configmap
```

**Validation gate:** Deploy to Minikube. Drop a test video into the input folder. After the ingest watcher fires, `kubectl logs -n grappl deployment/inference` shows frame extraction and Roboflow API calls. `SELECT COUNT(*) FROM events WHERE session_id = '{id}';` returns > 0. Session status updates to `inference_complete`.

---

## Phase 3 — Clip + Analysis

### Task 3.1 — Clip Service

```
Implement the clip service at services/clip/main.go.
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-09 through FR-12.

This service reads detection events for a session, generates a short
video clip for each event using FFmpeg, extracts a thumbnail, and
records clip file paths in the database.

Requirements:

1. Expose POST /process on port 8082:
   Request body: { "session_id": "uuid" }

   On receipt:
   - Fetch all events for this session using GetEventsBySession()
   - For each event, run FFmpeg clip extraction (see step 2)
   - Create a clip record in the database
   - After all clips are created, update session status to 'clips_ready'
   - POST to analysis service:
     http://analysis.grappl.svc.cluster.local/process
     Body: { "session_id": "..." }
   - If anything fails: update session to 'error'

2. FFmpeg clip extraction for each event:
   a. Determine source video path from the session record
   b. Calculate clip window:
      clip_start = max(0, event.start_ms - 3000) / 1000.0  (seconds, float)
      clip_end   = (event.end_ms + 5000) / 1000.0
   c. Build output path:
      OUTPUT_FOLDER/{session_id}/{event_id}.mp4
      Create the directory if it doesn't exist.
   d. Run FFmpeg:
      ffmpeg -ss {clip_start} -to {clip_end} -i {source_path}
             -c:v libx264 -crf 23 -preset fast
             -c:a aac -b:a 128k
             -movflags +faststart
             {output_path}
   e. Clip filename convention (FR-12):
      {session_id}_{event_type_slug}_{start_ms}.mp4
      Rename the output file to match this convention.

3. Thumbnail extraction:
   After each clip is created, extract a single frame at the midpoint:
   ffmpeg -ss {midpoint} -i {clip_path} -frames:v 1 -q:v 2
          {output_folder}/{event_id}_thumb.jpg
   Store thumbnail_path in the clip record.

4. Calculate clip duration_seconds and include it in the CreateClip() call.

5. Run clip extractions concurrently using a worker pool of 3 goroutines.
   Use a semaphore pattern (buffered channel) to limit concurrency.

6. Add GET /health on port 8082.

7. Structured JSON logging. Log FFmpeg commands before executing them
   (useful for debugging clip boundary issues).

Create infra/k8s/deployments/clip.yaml:
- Resources: 500m CPU / 512Mi requests; 2000m / 2Gi limits
  (FFmpeg is CPU and memory intensive)
- Mount grappl-data PVC
- Inject secrets and configmap
```

**Validation gate:** After inference completes on a test session, `kubectl logs -n grappl deployment/clip` shows FFmpeg commands executing. `SELECT COUNT(*) FROM clips WHERE session_id = '{id}';` matches event count. Clip files exist at the expected output paths. Each clip has a thumbnail. Session status is `clips_ready`.

---

### Task 3.2 — Analysis Service: Clip-Level Coaching Notes

```
Implement the first half of the analysis service at services/analysis/main.py.
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-13 through FR-15 and section 10.

This service generates per-clip coaching notes using LangChain + Claude API.

Requirements:

1. Use FastAPI for the HTTP layer (add to requirements.txt).
   Expose POST /process on port 8083.
   Request body: { "session_id": "uuid" }

2. Dependencies (requirements.txt):
   fastapi
   uvicorn
   langchain
   langchain-anthropic
   anthropic
   psycopg[binary]
   python-dotenv
   pydantic

3. On POST /process:
   a. Fetch all clips for this session, joined with their events and
      event_types. Include adjacent events (±60 seconds from each clip's
      event) for context. Use a raw SQL query via psycopg.
   b. For each clip, call generate_coaching_note() (see step 4)
   c. Write the result to coaching_notes table
   d. After all clips are done, call generate_session_summary() (Task 3.3)
   e. Update session status to 'complete'
   f. If anything fails: update session to 'error'

4. generate_coaching_note(clip, adjacent_events, model) function:

   Build a LangChain chain using ChatAnthropic with:
   - model: read ANALYSIS_MODEL from env
   - temperature: 0.3
   - max_tokens: 600

   System prompt:
   ---
   You are a BJJ coaching assistant. You analyze grappling footage detection
   data and write specific, direct coaching notes. Never use encouragement
   or generic praise. Focus only on what happened, what caused it, and one
   concrete corrective action. Write 3-5 sentences maximum.
   If confidence is below 0.80, qualify your observation accordingly.
   ---

   Human prompt template:
   ---
   Session event detected:
   - Position/submission: {event_type_label}
   - Category: {event_category}
   - Timestamp: {start_time} to {end_time}
   - Detection confidence: {confidence}

   Events in the 60 seconds before this detection:
   {adjacent_events_formatted}

   Write a coaching note for this clip.
   ---

   Use LangChain's PromptTemplate and LLMChain. Return the string output.

5. Wrap the LangChain call in a retry with exponential backoff
   (max 3 retries) for Anthropic API rate limit errors (429).

6. Add GET /health on port 8083.
   Startup: test DB connection and Anthropic API key validity.

Create infra/k8s/deployments/analysis.yaml:
- Resources: 100m CPU / 256Mi requests; 500m / 1Gi limits
- Inject ANTHROPIC_API_KEY and DATABASE_URL from grappl-secrets
- Inject ANALYSIS_MODEL and MAX_TOKENS_* from configmap
```

**Validation gate:** After clip service completes, `kubectl logs -n grappl deployment/analysis` shows LangChain calls. `SELECT content FROM coaching_notes LIMIT 3;` returns non-empty coaching notes. Each note is 3–5 sentences. Session status remains at `clips_ready` until this task's session summary (Task 3.3) is complete.

---

### Task 3.3 — Analysis Service: Session Summary Chain

```
Extend services/analysis/main.py with the session summary chain.
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-16 and section 10.1.

Add the generate_session_summary() function called after all
clip-level coaching notes are written.

Requirements:

1. generate_session_summary(session_id, coaching_notes, model) function:

   Build a second LangChain chain using ChatAnthropic with:
   - model: read ANALYSIS_MODEL from env
   - temperature: 0.5
   - max_tokens: 1000

   System prompt:
   ---
   You are a BJJ coaching assistant reviewing a full training session.
   You receive individual clip coaching notes and identify 2-3 patterns
   across the session. Do not repeat the individual notes. Synthesize them.
   Focus on structural weaknesses that appear in multiple clips.
   Be specific about positions, transitions, and timing. 3-5 sentences max.
   ---

   Human prompt template:
   ---
   The following coaching notes were generated from a single training session.
   Each note corresponds to a detected grappling event.

   {coaching_notes_formatted}

   Identify the 2-3 most significant patterns across this session
   and write a session summary with prioritized corrective focus areas.
   ---

   coaching_notes_formatted: numbered list of note content with the
   event type label prepended to each:
   "1. [Rear Naked Choke] You gave up the back at..."

2. After generating the summary:
   - Write to session_summaries table via CreateSessionSummary()
   - Update session status to 'complete'
   - Log: "Session {session_id} complete — summary generated"

3. Add error handling: if fewer than 2 coaching notes exist for the
   session, write a summary that says:
   "Insufficient events detected in this session to identify patterns.
   Check model confidence and consider re-processing with lower threshold."
   Still write this to session_summaries and mark session complete.

4. Add a GET /session/{session_id}/summary endpoint that returns
   the session summary JSON for later use by the gateway/UI.
```

**Validation gate:** Full pipeline test — drop a video, wait for all stages to complete. `SELECT content FROM session_summaries WHERE session_id = '{id}';` returns a multi-sentence summary identifying at least one cross-clip pattern. `SELECT status FROM sessions WHERE id = '{id}';` returns `complete`.

---

## Phase 4 — UI

### Task 4.1 — API Gateway

```
Implement the REST API gateway at services/gateway/main.go using Go + Gin.
This is the only service the UI communicates with directly.
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-22 through FR-27.

Endpoints required by the UI:

GET  /api/health
  Returns: { "status": "ok" }

GET  /api/sessions
  Returns: array of sessions ordered by created_at DESC
  Each session includes: id, file_name, status, created_at, event_count
  (event_count via subquery)

GET  /api/sessions/:id
  Returns: full session detail including session_summary content

GET  /api/sessions/:id/events
  Returns: all events for the session with event_type joined,
  ordered by start_ms ASC

GET  /api/clips
  Query params: session_id, event_type_slug, min_confidence, max_confidence
  Returns: paginated clip list (default page_size: 24)
  Each clip includes: id, event_type (joined), confidence, start_ms,
  thumbnail_path, coaching_note preview (first 120 chars), session date

GET  /api/clips/:id
  Returns: full clip detail including complete coaching note,
  event data, and adjacent session events (±60s window)

GET  /api/stats/positions
  Returns: position frequency counts grouped by event_type_slug
  for the default practitioner, optionally filtered by session_id

GET  /api/stats/sessions
  Returns: aggregate stats — total sessions, total events,
  total submissions, avg confidence per session

Implementation notes:
- Use github.com/gin-gonic/gin
- Use github.com/jackc/pgx/v5 with the shared db package
- Enable CORS for localhost and grappl.local origins
- All responses are JSON
- Thumbnail paths should be served as: /media/thumbnails/{filename}
  Add a static file handler for /media/ pointing to OUTPUT_FOLDER
- Use structured logging (log/slog)
- Add pagination support (page, page_size query params) on /api/clips

Create infra/k8s/deployments/gateway.yaml:
- Service: ClusterIP on port 8090
- Mount grappl-data PVC at /data (for serving media files)
- Inject secrets and configmap
- Update infra/k8s/ingress.yaml to add:
  /api/* → gateway service :8090
  /media/* → gateway service :8090
```

**Validation gate:** `curl http://grappl.local/api/health` returns `{"status":"ok"}`. After a completed session, `curl http://grappl.local/api/sessions` returns the session. `curl http://grappl.local/api/clips` returns clip records with thumbnail paths. Thumbnail images load at `/media/thumbnails/{filename}`.

---

### Task 4.2 — Film Library: Clip Grid & Filter Bar

```
Build the primary view of the GRAPPL film library UI.
Reference docs/bjj-film-platform.html for the complete visual design —
specifically the clip grid, toolbar filter bar, and clip cards.
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-22 through FR-24.

Design system (match docs/bjj-film-platform.html exactly):
- Background: #080808
- Text: #F5F5F0
- Accent: #C1121F (scarlet)
- Fonts: Bebas Neue (headings/display), Cormorant Garamond (body/italic),
  DM Mono (labels, metadata, timestamps)
- Load all three fonts from Google Fonts CDN

Update ui/index.html, ui/app.js, and ui/styles.css:

1. Top navigation bar:
   - GRAPPL logo (Bebas Neue, scarlet dot accent)
   - Nav links: Film Library, Sessions, Analysis, Settings (inactive stubs)
   - A "Processing" indicator that shows count of in-progress sessions

2. Ticker bar (below nav):
   - Auto-scrolling horizontal ticker showing the most recent 20 detection
     events from GET /api/stats/positions — format:
     "● {event_type_label} — {timestamp}"
   - CSS animation only, no JS animation library

3. Filter toolbar:
   - Filter buttons: All | Submissions | Positions | Transitions
     (filter by event_type category)
   - Confidence filter: All | High (≥0.80) | Low (<0.60)
   - Session date dropdown: populated from GET /api/sessions
   - Search input: client-side filter on clip event type label

4. Clip grid:
   - CSS Grid: 2 columns on desktop, 1 on mobile
   - First clip in the list spans full width (featured clip)
   - Each clip card:
     * Thumbnail image (from thumbnail_path via /media/)
     * If thumbnail fails to load: show a gradient placeholder matching
       the event type category (red for submission, blue for position)
     * Play button overlay (centered, shows GRAPPL scarlet on hover)
     * Event type tag (scarlet pill for submission, grey outline for position)
     * Duration badge (bottom right of thumbnail)
     * Clip title: "{Event Type Label} — {context from adjacent event}"
     * Meta row: date · timestamp · session number
     * Confidence bar: thin horizontal bar, scarlet fill, % label

5. API integration (ui/app.js):
   - On load: GET /api/clips?page=1&page_size=24
   - On filter change: re-fetch with updated query params
   - Infinite scroll: fetch next page when user reaches bottom
   - Show skeleton loading cards while fetching

6. Polling:
   - Every 10 seconds, GET /api/sessions?status=processing
   - If count > 0, show the processing indicator in the nav
   - When a session transitions to 'complete', show a toast notification:
     "New session ready — {file_name}"
```

**Validation gate:** `http://grappl.local` loads the film library. Clips from completed sessions display with thumbnails (or gradient fallbacks). Filter buttons re-fetch correctly. The confidence bar renders for each card. The ticker scrolls.

---

### Task 4.3 — Clip Detail View

```
Build the clip detail view that opens when a clip card is clicked.
Reference docs/bjj-film-platform.html for the right-panel design
(AI coaching note, event timeline, confidence display).
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-25.

Implement as a slide-in drawer panel (not a separate page).
The clip grid remains visible behind the drawer.

Drawer contents (top to bottom):

1. Close button (top right, × in DM Mono)

2. Video player:
   - Native HTML5 <video> element with controls
   - Source: served from /media/clips/{filename}
   - Autoplay on drawer open
   - 16:9 aspect ratio enforced via CSS

3. Event header:
   - Event type tag (styled as in clip cards)
   - Timestamp range: "1:42 – 2:00"
   - Confidence badge: "{value}% confidence" in scarlet if ≥0.80,
     grey if <0.80, with a warning icon if <0.60

4. AI Coaching Note section:
   - Label: "AI COACHING NOTE" in DM Mono scarlet
   - Left border: 2px scarlet rule
   - Background: slightly lighter than page (#111)
   - Content: full coaching_note.content in Cormorant Garamond italic
   - Bold key terms (position/submission names) using client-side
     regex replacement wrapping known terms in <strong>

5. Event Timeline section:
   - Label: "SESSION TIMELINE" in DM Mono grey
   - Scrollable list of all events in the session (from GET /api/sessions/:id/events)
   - Each timeline item: timestamp (scarlet DM Mono) · event label
   - Currently viewed event: highlighted with scarlet left border
   - Clicking another timeline item: navigates the video player to
     that event's start time within the clip (if within the clip window)
     or opens that clip's detail view

6. Data fetching:
   - On clip card click: GET /api/clips/:id
   - Show skeleton while loading
   - Preload the next and previous clips in the grid for instant navigation

7. Keyboard navigation:
   - Escape: close drawer
   - Arrow left/right: navigate to previous/next clip
```

**Validation gate:** Clicking any clip card opens the drawer. The video plays. The coaching note displays. The timeline shows all session events with the current one highlighted. Keyboard navigation works. Clicking timeline items seeks the player.

---

### Task 4.4 — Session View & Event Timeline

```
Build the session view — a chronological breakdown of a full training
session. Accessible by clicking a session in a sessions list view.
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-26.

Add a "Sessions" view to the app (show when "Sessions" nav link is clicked):

1. Sessions list (left panel or top section):
   - List of all sessions from GET /api/sessions
   - Each session row: file_name, date, status badge, event count
   - Status badge colors:
     complete → green dot
     processing / inference_complete / clips_ready → amber dot + spinner
     error → red dot
     queued → grey dot
   - Click a session row to load its detail

2. Session detail (main area):
   a. Session summary card at the top:
      - Label: "SESSION SUMMARY" in DM Mono scarlet
      - Content: session_summary.content in Cormorant Garamond italic
      - If no summary: show "Analysis in progress..."

   b. Aggregate stats row (4 tiles, matching the dashboard in the mockup):
      - Total events
      - Submission count
      - Average confidence
      - Number of rolls (sessions detected — use heuristic: count gaps
        > 60s between events as new "rounds")

   c. Chronological event timeline:
      - All events from GET /api/sessions/:id/events ordered by start_ms
      - Each event row: timestamp · event type label · confidence badge
      - Submission events: scarlet text
      - Position/transition events: grey text
      - Click any event row → open clip detail drawer for that clip
      - If no clip exists for an event (rare edge case): show a
        "No clip available" state instead of opening the drawer

3. Session filtering:
   - If sessions are still in progress (status ≠ complete),
     show a progress indicator: "Processing — inference running..."
     with the current status label
   - Auto-refresh the session detail every 15 seconds if status ≠ complete
```

**Validation gate:** Clicking "Sessions" nav shows the sessions list. Clicking a completed session shows the summary, stats, and event timeline. Clicking an event row opens the clip drawer. In-progress sessions show the correct status badge and auto-refresh.

---

### Task 4.5 — Position Frequency Heatmap

```
Build the position frequency heatmap component shown in
docs/bjj-film-platform.html (right panel, bottom section).
Reference docs/GRAPPL_PRD_MVP_v1.0.md FR-27.

Implement as a reusable component rendered in two places:
1. In the session detail view (Task 4.4), showing frequency for
   the selected session only.
2. In a new "Analysis" view (accessible from the nav), showing
   cumulative frequency across all sessions.

Heatmap data source:
  GET /api/stats/positions?session_id={id}  (session-level)
  GET /api/stats/positions                  (all-time)

Heatmap rendering:
- An 8-cell grid (2 rows × 4 columns) using CSS Grid
- Each cell represents one position/submission class
- Cell background: rgba(193, 18, 31, {opacity})
  where opacity = (count / max_count) scaled between 0.05 and 0.85
- Cell content:
  - Large number (count) in Bebas Neue
  - Small label (event type label) in DM Mono
- Cells are sorted by count descending (highest frequency top-left)
- Cells with count 0: render with opacity 0.03 and dashed border
- Hover: tooltip showing exact count and percentage of total events

Analysis view (new page — "Analysis" nav link):
- Two-column layout:
  Left: cumulative position heatmap (all-time)
  Right: a line chart showing event counts per session over time
         (use plain SVG — no chart library; plot as a simple polyline
         with dots, x-axis = session date, y-axis = event count,
         one line per top-4 position class)
- Below: a table showing:
  Position | Total Count | Avg Confidence | Sessions Appeared In
  Sorted by total count DESC

Fetch data for the chart:
  GET /api/sessions → iterate and GET /api/stats/positions?session_id=
  for each completed session (batch these calls with Promise.all)
```

**Validation gate:** Heatmap renders in both session detail and analysis views. Cell opacity correctly reflects relative frequency. The SVG line chart renders with at least one line per completed session. The stats table populates correctly.

---

## Phase 5 — Validation

### Task 5.1 — End-to-End Pipeline Smoke Test Script

```
Create scripts/smoke-test.sh — a fully automated end-to-end validation
script that exercises the entire GRAPPL pipeline.

The script must:

1. Pre-flight checks:
   - Verify the grappl minikube profile is running:
     minikube status -p grappl | grep -q "Running"
   - Verify all 6 pods are in Running state in the grappl namespace:
     kubectl get pods -n grappl --context=grappl
   - Verify Supabase is reachable
   - Verify GET http://grappl.local/api/health returns 200

2. Test video setup:
   - Download a short public-domain test video (max 60 seconds)
     using curl if a test video doesn't already exist at
     scripts/test-assets/test_roll.mp4
     Suggested source: any royalty-free MP4 from archive.org
   - Alternatively: use ffmpeg to generate a synthetic test video:
     ffmpeg -f lavfi -i color=c=black:s=1280x720:d=30 -c:v libx264
     scripts/test-assets/test_roll.mp4
     (A black video is enough to test the pipeline mechanics —
     the model won't detect anything meaningful, but the pipeline
     should complete without error.)

3. Ingest the test video:
   - Copy test_roll.mp4 into the watched input folder via kubectl cp:
     kubectl cp scripts/test-assets/test_roll.mp4 \
       grappl/{ingest-pod}:/data/input/test_roll_$(date +%s).mp4
   - Record the timestamp

4. Poll for completion:
   - Every 10 seconds, query GET /api/sessions?status=complete
   - If a session created after the recorded timestamp appears: PASS
   - If 10 minutes elapse without completion: FAIL — print logs from
     all four pipeline services

5. Validate database state:
   Run these checks and print PASS/FAIL for each:
   a. sessions table has a row with status='complete'
   b. events table has ≥ 0 rows for the session (0 is valid — synthetic video)
   c. session_summaries table has a row for the session
   d. If events > 0: clips table has rows and coaching_notes table has rows

6. Validate API responses:
   a. GET /api/sessions → returns array including the test session
   b. GET /api/sessions/{id} → returns session with summary
   c. GET /api/clips → returns array (may be empty if no detections)
   d. GET /api/stats/positions → returns position frequency data

7. Print final summary:
   ✓ or ✗ for each check
   Total runtime from ingest to complete
   "SMOKE TEST PASSED" or "SMOKE TEST FAILED — see above"
```

**Validation gate:** `bash scripts/smoke-test.sh` runs to completion and prints `SMOKE TEST PASSED`. All database checks pass. All API endpoint checks pass.

---

### Task 5.2 — Error Handling & Retry Hardening

```
Audit all five services for error handling gaps and implement
consistent retry and recovery behavior.

For each service, apply the following standards:

1. services/ingest:
   - If the POST to inference service fails with a network error:
     retry 3 times with 5s backoff before marking session as 'error'
   - If the file disappears between detection and processing:
     log the error and skip (do not crash)
   - If database is unreachable on startup:
     retry connection every 30 seconds with a log message — do not exit

2. services/inference:
   - If a single frame POST to Roboflow fails (non-429):
     log the error, skip the frame, and continue
   - If the Roboflow API returns 429:
     retry with exponential backoff: 2s, 4s, 8s, 16s (max 4 retries)
   - If ffmpeg frame extraction fails:
     mark session as 'error' immediately (can't proceed without frames)
   - If fewer than 10 frames are extracted: log a warning but continue
   - Clean up /tmp/{session_id}/ in a defer block regardless of outcome

3. services/clip:
   - If an individual FFmpeg clip extraction fails:
     log the error, skip that clip, continue with remaining events
     (partial clip generation is better than total failure)
   - After all clips attempted: if 0 clips succeeded, mark session 'error'
   - If the analysis service POST fails: retry once, then mark 'error'

4. services/analysis:
   - If the Anthropic API returns an error for a single clip note:
     log the error, store a placeholder:
     "Coaching note generation failed for this clip. Re-process to retry."
     Continue with remaining clips — do not block the session.
   - If all coaching notes fail: still generate the session summary
     with the error placeholder notes (the summary will acknowledge
     that note generation failed)
   - Rate limit handling: if 429, retry up to 3 times with backoff
     before using the placeholder

5. services/gateway:
   - Add 404 and 500 error responses in consistent JSON format:
     { "error": "not_found", "message": "..." }
   - Add request timeout middleware: 30 seconds max per request
   - Log all 5xx responses with request ID

6. All services:
   - Add a /readyz endpoint (separate from /health) that returns 503
     until the service has confirmed DB connectivity
   - Update Kubernetes deployment readiness probes to use /readyz
   - Add resource limit annotations to all deployments

Update scripts/smoke-test.sh to include an error path test:
- Submit an unreadable file (0-byte mp4) and verify the session
  reaches 'error' status cleanly without crashing any pod.
```

**Validation gate:** `kubectl get pods -n grappl` shows all pods Running with 0 restarts after the error path test. A zero-byte MP4 results in a session with `status='error'` and a non-null `error_message`. All services remain running after the error.

---

### Task 5.3 — Confidence Calibration Review Tooling

```
Create a confidence calibration review tool that makes it easy to
assess and tune the Roboflow model's detection quality against
real footage after the first end-to-end run.

1. Create scripts/confidence-report.py:
   A Python script (using psycopg and tabulate) that connects to
   the local Supabase DB and prints a calibration report:

   --- GRAPPL Confidence Calibration Report ---

   Detection Summary:
   ┌─────────────────────────┬───────┬──────────┬──────────┬──────────┐
   │ Event Type              │ Count │ Avg Conf │ Min Conf │ Max Conf │
   ├─────────────────────────┼───────┼──────────┼──────────┼──────────┤
   │ rear_naked_choke        │   7   │  0.891   │  0.612   │  0.970   │
   ...

   Confidence Distribution:
   High (≥0.80):  47 events (68%)
   Medium (0.60–0.79): 14 events (20%)
   Low (<0.60):    8 events (12%)  ← flagged in UI

   Low-Confidence Events (review these):
   ┌────────────────┬───────────────────┬──────────┬──────────────┐
   │ Session        │ Event Type        │ Conf     │ Timestamp    │
   ...

   Recommendations:
   - If any class has avg confidence < 0.65:
     print "Consider adding 50+ labeled frames for: {class}"
   - If Low confidence > 25%:
     print "Consider lowering Roboflow confidence threshold from 0.40 to 0.30"

2. Add a /api/admin/confidence-report endpoint to the gateway
   that returns the same data as JSON (for future UI integration).

3. Update the Roboflow inference service to support an environment
   variable ROBOFLOW_CONFIDENCE_THRESHOLD (default: 0.40) that is
   passed as the confidence query param to the Roboflow API.
   This allows threshold tuning without code changes.

4. Update the configmap to include:
   ROBOFLOW_CONFIDENCE_THRESHOLD: "0.40"

5. Document in docs/CALIBRATION.md:
   - How to run the confidence report
   - How to adjust the threshold
   - How to add labeled frames in Roboflow and re-publish the model
   - How to re-process an existing session:
     curl -X POST http://grappl.local/api/sessions/{id}/reprocess
   
   Add the /reprocess endpoint to the gateway:
   - Reset session to 'queued'
   - Delete all events, clips, coaching_notes, session_summaries
     for this session (CASCADE handles most of this)
   - Re-trigger the pipeline from inference
```

**Validation gate:** `python3 scripts/confidence-report.py` runs and prints the calibration table. `curl http://grappl.local/api/admin/confidence-report` returns JSON. `docs/CALIBRATION.md` exists with all four documented procedures.

---

### Task 5.4 — Performance Benchmarking

```
Create scripts/benchmark.sh — a performance benchmarking script that
validates NFR-01 and NFR-02 from docs/GRAPPL_PRD_MVP_v1.0.md.

1. Pipeline throughput benchmark (NFR-01: 10-min video in ≤20 min):
   a. Use ffmpeg to generate a synthetic 10-minute test video:
      ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=600 \
             -c:v libx264 -crf 28 scripts/test-assets/benchmark_10min.mp4
   b. Record start time
   c. Ingest the file via kubectl cp
   d. Poll until session status = 'complete'
   e. Record end time
   f. Print: "Pipeline time for 10-min video: {elapsed}s"
   g. PASS if elapsed ≤ 1200 seconds (20 minutes), FAIL otherwise
   h. Print breakdown by phase using session updated_at transitions:
      - Ingest → inference_complete: {N}s
      - inference_complete → clips_ready: {N}s
      - clips_ready → complete: {N}s

2. UI load benchmark (NFR-02: clip library loads in ≤2s):
   a. Use curl with timing to measure GET /api/clips response time:
      curl -o /dev/null -s -w "API response time: %{time_total}s\n" \
           http://grappl.local/api/clips
   b. Run 5 times and print min/max/avg
   c. PASS if avg < 2.0s, FAIL otherwise
   d. If FAIL: print the EXPLAIN ANALYZE output for the clips query
      (query the DB directly to find the slow part)

3. Resource usage snapshot:
   After the 10-minute benchmark completes, print:
   kubectl top pods -n grappl
   And note which service consumed the most CPU and memory.
   Write this to docs/BENCHMARK_RESULTS.md with the date and
   hardware spec (read from /proc/cpuinfo and /proc/meminfo).

4. Print final summary:
   ✓ or ✗ for NFR-01 and NFR-02
   "PERFORMANCE BENCHMARKS PASSED" or list of failures
```

**Validation gate:** `bash scripts/benchmark.sh` completes. Both NFR-01 and NFR-02 checks print ✓. `docs/BENCHMARK_RESULTS.md` exists with timing data and resource usage.

---

### Task 5.5 — Final Hardening & README

```
Complete the final hardening pass and write the project README.

1. Secrets audit:
   - Search the entire codebase for any hardcoded API keys, tokens,
     or database URLs (use grep -r patterns for common key formats)
   - Confirm .gitignore covers: .env, .env.local, *.env, infra/k8s/secrets/,
     /tmp/, scripts/test-assets/
   - Verify all Kubernetes deployments reference grappl-secrets and
     grappl-config only — no env vars hardcoded in yaml files

2. Kubernetes liveness/readiness probe audit:
   - Confirm all 6 deployments have both liveness (/health) and
     readiness (/readyz) probes configured
   - Confirm resource requests and limits are set on all containers
   - Confirm all containers run as non-root (securityContext.runAsNonRoot: true)

3. Database index audit:
   - Run EXPLAIN ANALYZE on the three most frequent gateway queries:
     GET /api/clips (with filters)
     GET /api/sessions/:id/events
     GET /api/stats/positions
   - If any query shows a Seq Scan on a large table, add the missing index
     in a new migration: infra/supabase/migrations/011_perf_indexes.sql

4. Write README.md at the project root:

   # GRAPPL — BJJ Film Intelligence Platform

   One-paragraph description (non-technical, from the product pitch).

   ## Quick Start
   Step-by-step from clone to first video processed:
   1. Prerequisites (minikube, kubectl, docker, supabase CLI, ffmpeg)
   2. Clone and setup: scripts/setup-minikube.sh, scripts/setup-supabase.sh
      Note: setup-minikube.sh creates a dedicated 'grappl' minikube profile
      isolated from any other applications using the default 'minikube' profile.
      In each new terminal: eval $(minikube docker-env -p grappl)
   3. Add API keys to .env.local (list each key and where to get it)
   4. scripts/create-secrets.sh
   5. scripts/build-images.sh
   6. scripts/deploy.sh
   7. Add /etc/hosts entry (from scripts/add-hosts.sh output)
   8. Open http://grappl.local
   9. Drop a video into the input folder

   ## Architecture
   Link to docs/GRAPPL_PRD_MVP_v1.0.md

   ## Services
   One-line description of each service with its port.

   ## Development
   How to rebuild and redeploy a single service:
   docker build -t grappl/{service}:local services/{service}/
   kubectl rollout restart deployment/{service} -n grappl

   ## Validation
   scripts/smoke-test.sh
   scripts/benchmark.sh
   scripts/confidence-report.py

   ## Calibration
   Link to docs/CALIBRATION.md

5. Run the full smoke test one final time:
   bash scripts/smoke-test.sh
   All checks must pass.
```

**Validation gate:** `grep -r "api_key\|ANTHROPIC_API_KEY\|roboflow" --include="*.go" --include="*.py" --include="*.yaml" | grep -v "secret\|env\|example\|gitignore"` returns no hardcoded secrets. All 6 pods show `0` restarts. `bash scripts/smoke-test.sh` prints `SMOKE TEST PASSED`. `README.md` exists and the Quick Start section is complete.

---

## MVP Complete ✓

When Task 5.5 passes, all seven success criteria from
`docs/GRAPPL_PRD_MVP_v1.0.md` section 15 should be satisfied:

| # | Criterion | Validated By |
|---|---|---|
| 1 | Raw video processed end-to-end without manual intervention | Task 5.1 smoke test |
| 2 | ≥8 of 11 detection classes at >75% precision | Task 5.3 calibration report |
| 3 | Every event has a clip and coaching note | Task 5.1 DB checks |
| 4 | Session summary identifies ≥1 cross-clip pattern | Task 3.3 validation gate |
| 5 | Film library browsable with functional filters | Task 4.2 validation gate |
| 6 | Pipeline stable across ≥5 consecutive sessions | Task 5.2 error hardening |
| 7 | 10-minute video processes in ≤20 minutes | Task 5.4 benchmark |

---

*GRAPPL — Build Plan v1.0 — docs/GRAPPL_Build_Plan_v1.0.md*
