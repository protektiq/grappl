-- 005_create_events.sql
-- Create events table, low-confidence generated column, and indexes.

CREATE TABLE IF NOT EXISTS public.events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  practitioner_id UUID NOT NULL REFERENCES public.practitioners(id),
  event_type_id UUID NOT NULL REFERENCES public.event_types(id),
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  confidence NUMERIC(4,3) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  bounding_box JSONB,
  low_confidence BOOLEAN GENERATED ALWAYS AS (confidence < 0.60) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_events_session_start_ms
  ON public.events (session_id, start_ms);

CREATE INDEX IF NOT EXISTS idx_events_practitioner_event_type
  ON public.events (practitioner_id, event_type_id);
