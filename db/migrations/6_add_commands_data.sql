ALTER TABLE subscription_commands ADD COLUMN data jsonb DEFAULT '{}'::jsonb;
ALTER TABLE subscriptions_set_commands ADD COLUMN data jsonb DEFAULT '{}'::jsonb;
