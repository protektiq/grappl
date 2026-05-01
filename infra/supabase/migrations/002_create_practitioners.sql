-- 002_create_practitioners.sql
-- Create practitioners table and seed the single MVP practitioner.

CREATE TABLE IF NOT EXISTS public.practitioners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.practitioners (id, name)
VALUES ('8c0b7c54-f9cb-4ea8-8f2e-3ac40ae20e9d', 'default')
ON CONFLICT (id) DO NOTHING;
