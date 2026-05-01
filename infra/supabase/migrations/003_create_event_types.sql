-- 003_create_event_types.sql
-- Create event_types lookup and seed all 11 MVP classes.

CREATE TABLE IF NOT EXISTS public.event_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT UNIQUE NOT NULL,
  label TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('position', 'transition', 'submission'))
);

INSERT INTO public.event_types (slug, label, category)
VALUES
  ('guard', 'Guard', 'position'),
  ('half_guard', 'Half Guard', 'position'),
  ('mount', 'Mount', 'position'),
  ('side_control', 'Side Control', 'position'),
  ('back_control', 'Back Control', 'position'),
  ('turtle', 'Turtle', 'position'),
  ('back_take', 'Back Take', 'transition'),
  ('guard_pass', 'Guard Pass', 'transition'),
  ('triangle_attempt', 'Triangle Attempt', 'submission'),
  ('armbar_attempt', 'Armbar Attempt', 'submission'),
  ('rear_naked_choke_attempt', 'Rear Naked Choke (RNC)', 'submission')
ON CONFLICT (slug) DO NOTHING;
