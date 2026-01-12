CREATE UNLOGGED TABLE events_horizon
(
    global_position bigint not null,
    xact_id         xid8 not null default pg_current_xact_id()
);
CREATE INDEX idx_xact_id_and_created_at_and_global_position ON events_horizon USING btree(xact_id, global_position);
COMMENT ON TABLE events_horizon IS 'Internal use only. Data is limited to the PostgreSQL cluster in which it was created. DO NOT INCLUDE ITS DATA INTO YOUR DUMP.';

CREATE OR REPLACE FUNCTION log_events_horizon()
    RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO events_horizon(global_position)
    VALUES (NEW.global_position);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER log_events_horizon
    AFTER INSERT ON events
    FOR EACH ROW
EXECUTE FUNCTION log_events_horizon();
