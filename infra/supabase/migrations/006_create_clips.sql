-- 006_create_clips.sql
-- Create clips table and event index.

CREATE TABLE IF NOT EXISTS public.clips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  practitioner_id UUID NOT NULL REFERENCES public.practitioners(id),
  file_path TEXT NOT NULL,
  thumbnail_path TEXT,
  duration_seconds NUMERIC(6,2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_clips_event_id
  ON public.clips (event_id);
