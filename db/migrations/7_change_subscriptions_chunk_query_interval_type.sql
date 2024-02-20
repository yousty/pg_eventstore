ALTER TABLE public.subscriptions ALTER COLUMN chunk_query_interval SET DATA TYPE float4;
ALTER TABLE public.subscriptions ALTER COLUMN chunk_query_interval SET DEFAULT 1.0;
