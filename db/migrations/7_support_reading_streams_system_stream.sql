CREATE INDEX idx_events_0_stream_revision_global_position ON events USING btree (stream_revision, global_position) WHERE stream_revision = 0;
CREATE VIEW "$streams" AS SELECT * FROM events WHERE stream_revision = 0;
