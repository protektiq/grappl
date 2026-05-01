-- 009_row_level_security.sql
-- Enable RLS on all tables and allow service_role full access for single-user MVP.

ALTER TABLE public.practitioners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_summaries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS practitioners_service_role_all ON public.practitioners;
CREATE POLICY practitioners_service_role_all
  ON public.practitioners
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS event_types_service_role_all ON public.event_types;
CREATE POLICY event_types_service_role_all
  ON public.event_types
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS sessions_service_role_all ON public.sessions;
CREATE POLICY sessions_service_role_all
  ON public.sessions
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS events_service_role_all ON public.events;
CREATE POLICY events_service_role_all
  ON public.events
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS clips_service_role_all ON public.clips;
CREATE POLICY clips_service_role_all
  ON public.clips
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS coaching_notes_service_role_all ON public.coaching_notes;
CREATE POLICY coaching_notes_service_role_all
  ON public.coaching_notes
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS session_summaries_service_role_all ON public.session_summaries;
CREATE POLICY session_summaries_service_role_all
  ON public.session_summaries
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
