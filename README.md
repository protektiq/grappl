# GRAPPL

GRAPPL is an AI-powered grappling film review platform built as a local-first monorepo MVP.

## Monorepo Layout

- `docs/` product and build planning documentation
- `services/` backend services (`ingest`, `inference`, `clip`, `analysis`, `gateway`)
- `ui/` vanilla JavaScript frontend served by Nginx
- `infra/k8s/` Kubernetes namespace, secret templates, and deployment scaffolds
- `infra/supabase/migrations/` numbered SQL migration files
- `scripts/` setup and utility scripts

## Documentation

- `docs/GRAPPL_PRD_MVP_v1.0.md`
- `docs/GRAPPL_Build_Plan_v1.0.md`
- `DATA_FLOW_DIAGRAM.md`
