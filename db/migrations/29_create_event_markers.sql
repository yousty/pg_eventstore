CREATE TABLE public.event_markers
(
    id   bigserial NOT NULL,
    name text      NOT NULL
);

CREATE UNIQUE INDEX idx_event_markers_on_name ON public.event_markers
    USING btree (name) INCLUDE (id);

CREATE INDEX idx_event_markers_on_id ON public.event_markers
    USING btree (id) INCLUDE (name);

CREATE TABLE public.event_markers_index
(
    marker_id               bigint NOT NULL,
    streams_global_index_id bigint NOT NULL,
    event_type_partition_id bigint NOT NULL,
    global_position         bigint NOT NULL,
    stream_revision         bigint NOT NULL
);

CREATE UNIQUE INDEX idx_event_markers_index_on_marker_N_stream_N_rev ON public.event_markers_index
    USING btree (marker_id, streams_global_index_id, stream_revision) INCLUDE (global_position, event_type_partition_id);

CREATE INDEX idx_event_markers_index_on_marker_N_stream_N_partition_N_rev ON public.event_markers_index
    USING btree (marker_id, streams_global_index_id, event_type_partition_id, stream_revision) INCLUDE (global_position);

CREATE INDEX idx_event_markers_index_on_marker_N_pos ON public.event_markers_index
    USING btree (marker_id, global_position) INCLUDE (event_type_partition_id);

CREATE INDEX idx_event_markers_index_on_marker_N_partition_N_pos ON public.event_markers_index
    USING btree (marker_id, event_type_partition_id, global_position);
