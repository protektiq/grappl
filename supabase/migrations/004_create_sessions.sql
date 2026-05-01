-- 004_create_sessions.sql
-- Create sessions table and required indexes.

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  practitioner_id UUID NOT NULL REFERENCES public.practitioners(id),
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'processing', 'inference_complete', 'clips_ready', 'complete', 'error')),
  error_message TEXT,
  schema_version INTEGER NOT NULL DEFAULT 1,
  duration_seconds INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sessions_practitioner_created_at
  ON public.sessions (practitioner_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sessions_status
  ON public.sessions (status);
