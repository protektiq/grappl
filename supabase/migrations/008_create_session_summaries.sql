-- 008_create_session_summaries.sql
-- Create session_summaries table.

CREATE TABLE IF NOT EXISTS public.session_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  prompt_version INTEGER NOT NULL DEFAULT 1,
  model TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
