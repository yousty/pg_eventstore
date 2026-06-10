ALTER TABLE public.partitions ADD COLUMN parent_stream_name_partition_id bigint;
ALTER TABLE public.partitions ADD COLUMN parent_context_partition_id bigint;

UPDATE partitions p SET parent_context_partition_id = (SELECT id FROM partitions WHERE context = p.context AND stream_name IS NULL AND event_type IS NULL) WHERE stream_name IS NOT NULL;
UPDATE partitions p SET parent_stream_name_partition_id = (SELECT id FROM partitions WHERE context = p.context AND stream_name = p.stream_name AND event_type IS NULL) WHERE event_type IS NOT NULL;
