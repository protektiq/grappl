# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is GRAPPL

GRAPPL is an AI-powered BJJ (Brazilian Jiu-Jitsu) film review platform. It ingests raw training footage, detects and classifies grappling events using a custom Roboflow computer vision model, extracts per-event video clips via FFmpeg, generates clip-level coaching notes and session summaries using LangChain + Claude, and surfaces the resulting library through a vanilla JS UI. The entire stack runs locally on Minikube.

## Build Commands

Each Go service is built independently from its directory:

```bash
# Build a single Go service
cd services/{ingest|inference|clip|gateway} && go build ./...

# Run tests for a Go service (most require DATABASE_URL to be set)
cd services/shared && go test ./...

# Build all Docker images targeting Minikube's registry
bash scripts/build-images.sh   # runs eval $(minikube docker-env) internally

# Rebuild and redeploy a single service after code changes
docker build -t grappl/{service}:local services/{service}/
kubectl rollout restart deployment/{service} -n grappl

# Python analysis service
cd services/analysis && pip install -r requirements.txt
python main.py
```

## Infrastructure Commands

```bash
# Initial setup (run once)
bash scripts/setup-minikube.sh    # starts Minikube with docker driver, 4 CPU, 8GB RAM
bash scripts/setup-supabase.sh    # starts local Supabase, writes .env.local
bash scripts/create-secrets.sh    # pushes .env.local into Kubernetes grappl-secrets
bash scripts/run-migrations.sh    # applies all infra/supabase/migrations/ in order

# Deploy all services to Minikube
bash scripts/deploy.sh            # applies manifests: namespace → pvc → configmap → secrets → deployments → ingress

# Get /etc/hosts entry to reach grappl.local
bash scripts/add-hosts.sh

# Validation
bash scripts/smoke-test.sh        # end-to-end pipeline test
bash scripts/benchmark.sh         # NFR performance checks
python3 scripts/confidence-report.py  # Roboflow detection calibration report
```

## Architecture & Data Flow

The pipeline is strictly sequential — each service hands off to the next via an internal HTTP POST:

```
InputVideo (dropped into /data/input)
  → ingest  (Go, :8081)  — watches folder, creates session row, moves file to /data/processing/
  → inference (Go, :8082) — extracts frames via FFmpeg, calls Roboflow API, writes events to DB
  → clip    (Go, :8083)  — runs FFmpeg per event to cut clips + thumbnails into /data/output/clips/
  → analysis (Python, :8084) — LangChain + Claude generates coaching_notes per clip, then session_summary
  → Supabase DB
  → gateway (Go, :8080)  — REST API consumed by UI
  → UI      (Nginx, :80) — vanilla JS, served at http://grappl.local
```

All Go services share `services/shared/` (module `github.com/grappl/shared`) for DB access via `pgx/v5`. Each Go service's `go.mod` uses a `replace` directive pointing to `../shared`.

## Key Environment Variables

All secrets live in `.env.local` (gitignored) and are injected into Kubernetes via the `grappl-secrets` Secret. Non-sensitive config is in `infra/k8s/configmap.yaml` as `grappl-config`.

Required keys: `ROBOFLOW_API_KEY`, `ROBOFLOW_MODEL_ID`, `ROBOFLOW_MODEL_VERSION`, `ANTHROPIC_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_URL`. See `.env.example` for all variables with placeholder values.

## Database

Supabase (local Docker instance). Migrations are numbered SQL files in `infra/supabase/migrations/` applied via `supabase db push`. The schema is: `practitioners → sessions → events → clips → coaching_notes` and `sessions → session_summaries`. Session status flows: `queued → processing → inference_complete → clips_ready → complete` (or `error` at any stage).

## Service Ports

| Service  | Port |
|----------|------|
| gateway  | 8080 |
| ingest   | 8081 |
| inference| 8082 |
| clip     | 8083 |
| analysis | 8084 |
| UI/Nginx | 80   |

All services expose `/health` (liveness) and `/readyz` (readiness, returns 503 until DB is confirmed).

## Go Module Structure

```
services/
  shared/    # github.com/grappl/shared — DB client, structs, repository functions
  ingest/    # github.com/grappl/ingest
  inference/ # github.com/grappl/inference
  clip/      # github.com/grappl/clip
  gateway/   # github.com/grappl/gateway — Gin REST API
```

## UI

Vanilla JS + CSS in `ui/`. No build step — files are copied directly into the Nginx Docker image. The UI talks only to the gateway at `/api/*`. Thumbnails and clip files are served at `/media/*` by the gateway's static file handler pointing to `OUTPUT_FOLDER`.

## Kubernetes

All manifests live under `infra/k8s/`. The namespace is `grappl`. All deployments mount the `grappl-data` PVC (50Gi, ReadWriteMany) at `/data` for shared video/clip storage. Never hardcode secrets in YAML — all secrets come from `grappl-secrets`, config from `grappl-config`.

## Build Plan Reference

The sequential build plan is in `docs/GRAPPL_Build_Plan_v1.0.md`. Tasks are numbered (1.1–5.5) and must be completed in order — each has a validation gate that must pass before proceeding.
