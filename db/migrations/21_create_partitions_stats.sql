CREATE STATISTICS partition_parts_dep (dependencies) on context, stream_name, event_type FROM public.partitions;
ANALYZE public.partitions;
