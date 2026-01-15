-- We need to drop view which uses link_id and re-create it after we remove link_id column
DROP VIEW "$streams";

ALTER TABLE public.events DROP COLUMN link_id;

CREATE VIEW "$streams" AS SELECT * FROM events WHERE stream_revision = 0;
