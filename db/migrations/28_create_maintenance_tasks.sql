CREATE TABLE public.maintenance_tasks
(
    task_name    character varying COLLATE "POSIX" NOT NULL,
    locked_at    timestamp without time zone,
    performed_at timestamp without time zone
);

CREATE UNIQUE INDEX idx_maintenance_tasks_task_name ON maintenance_tasks USING btree (task_name);
