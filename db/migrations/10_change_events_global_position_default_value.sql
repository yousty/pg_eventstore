ALTER TABLE events ALTER COLUMN global_position SET DEFAULT nextval_with_xact_lock('public.events_global_position_seq'::regclass);
