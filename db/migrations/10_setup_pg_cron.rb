# frozen_string_literal: true

PgEventstore.connection(:_postgres_db_connection).with do |conn|
  conn.exec(<<~SQL)
    CREATE EXTENSION IF NOT EXISTS pg_cron
  SQL
  conn.exec_params(<<~SQL, ["prune_#{PgEventstore::MigrationHelpers.db_name}_events_horizon", PgEventstore::MigrationHelpers.db_name])
    SELECT cron.schedule_in_database(
      $1,
      '*/10 * * * *',
      $$DELETE FROM events_horizon WHERE xact_id <= (SELECT xact_id FROM events_horizon ORDER BY xact_id DESC OFFSET 100 LIMIT 1)$$,
      $2
     )
  SQL
  # Store information about finished cron jobs for 1 day
  conn.exec(<<~SQL)
    SELECT cron.schedule(
      'delete-job-run-details',
      '0 12 * * *',
      $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '1 day'$$
    );
  SQL
end
