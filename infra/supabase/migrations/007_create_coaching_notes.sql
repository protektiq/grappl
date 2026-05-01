-- 007_create_coaching_notes.sql
-- Create coaching_notes table.

CREATE TABLE IF NOT EXISTS public.coaching_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clip_id UUID NOT NULL REFERENCES public.clips(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  prompt_version INTEGER NOT NULL DEFAULT 1,
  model TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
