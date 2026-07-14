CREATE FUNCTION public.create_context_partition_table()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format(
        'CREATE TABLE public.%I PARTITION OF public.events FOR VALUES IN (%L) PARTITION BY LIST (stream_name)',
        NEW.table_name,
        NEW.context
    );

    EXECUTE format(
        'COMMENT ON TABLE public.%I IS %L',
        NEW.table_name,
        format('''%s'' context partition', NEW.context)
    );

    RETURN NEW;
END;
$$;

CREATE FUNCTION public.create_stream_name_partition_table()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    context_partition_name public.partitions.table_name%TYPE;
BEGIN
    SELECT table_name
    INTO STRICT context_partition_name
    FROM public.partitions
    WHERE id = NEW.parent_context_partition_id;

    EXECUTE format(
        'CREATE TABLE public.%I PARTITION OF public.%I FOR VALUES IN (%L) PARTITION BY LIST (type)',
        NEW.table_name,
        context_partition_name,
        NEW.stream_name
    );

    EXECUTE format(
        'COMMENT ON TABLE public.%I IS %L',
        NEW.table_name,
        format('''%s'' context and ''%s'' stream name partition', NEW.context, NEW.stream_name)
    );

    RETURN NEW;
END;
$$;

CREATE FUNCTION public.create_event_type_partition_table()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    stream_name_partition_name public.partitions.table_name%TYPE;
BEGIN
    SELECT table_name
    INTO STRICT stream_name_partition_name
    FROM public.partitions
    WHERE id = NEW.parent_stream_name_partition_id;

    EXECUTE format(
        'CREATE TABLE public.%I PARTITION OF public.%I FOR VALUES IN (%L)',
        NEW.table_name,
        stream_name_partition_name,
        NEW.event_type
    );

    EXECUTE format(
        'COMMENT ON TABLE public.%I IS %L',
        NEW.table_name,
        format(
            '''%s'' context and ''%s'' stream name and ''%s'' event type partition',
            NEW.context,
            NEW.stream_name,
            NEW.event_type
        )
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER create_context_partition_table
AFTER INSERT ON public.partitions
FOR EACH ROW
WHEN (NEW.stream_name IS NULL AND NEW.event_type IS NULL)
EXECUTE FUNCTION public.create_context_partition_table();

CREATE TRIGGER create_stream_name_partition_table
AFTER INSERT ON public.partitions
FOR EACH ROW
WHEN (NEW.stream_name IS NOT NULL AND NEW.event_type IS NULL)
EXECUTE FUNCTION public.create_stream_name_partition_table();

CREATE TRIGGER create_event_type_partition_table
AFTER INSERT ON public.partitions
FOR EACH ROW
WHEN (NEW.event_type IS NOT NULL)
EXECUTE FUNCTION public.create_event_type_partition_table();
