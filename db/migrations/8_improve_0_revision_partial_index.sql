DROP INDEX IF EXISTS idx_events_0_stream_revision_global_position;
CREATE INDEX idx_events_0_stream_revision_global_position ON events USING btree (global_position) WHERE stream_revision = 0;
