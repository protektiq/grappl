-- 010_updated_at_trigger.sql
-- Maintain sessions.updated_at automatically on row updates.

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = clock_timestamp();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sessions_set_updated_at ON public.sessions;

CREATE TRIGGER trg_sessions_set_updated_at
BEFORE UPDATE ON public.sessions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
