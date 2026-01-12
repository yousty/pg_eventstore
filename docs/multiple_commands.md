# Multiple commands

`pg_eventstore` implements the `#multiple` method to allow you to make several different commands atomic. Internally it executes the given block within PostgreSQL transaction. Example:

```ruby
PgEventstore.client.multiple do
  unless PgEventstore.client.read(stream3, options: { max_count: 1, direction: 'Backwards' }).last&.type == 'Removed'
    PgEventstore.client.append_to_stream(stream1, event1)
    PgEventstore.client.append_to_stream(stream2, event2)
  end  
end
```

Optionally, you can provide `read_only: true` argument to run the transaction in read-only mode. This, however, will raise `PG::ReadOnlySqlTransaction` exception if any mutating query is executed within the block. Example:

```ruby
# Good
PgEventstore.client.multiple(read_only: true) do
  PgEventstore.client.read(stream1)
  PgEventstore.client.read(stream2)
end
# Bad. Will raise error
PgEventstore.client.multiple(read_only: true) do
  PgEventstore.client.append_to_stream(stream, event)
end
```


All commands inside a `multiple` block either all succeed or all fail. This allows you to easily implement complex business rules. However, it comes with a price of performance. The more you put in a single block, the higher the chance it will have conflicts with other commands run in parallel, increasing overall time to complete. **Because of this performance implications, do not put more events than needed in a `multple` block.** You may still want to use it though as it could simplify your implementation.

**Please take into account that due to concurrency of parallel commands, a block of code may be re-run several times before succeeding.** So, if you put any piece of code besides `pg_evenstore`'s commands - make sure it is ready for re-runs. A good and a bad examples:

## Bad

```ruby
PgEventstore.client.multiple do
  old_email = PgEventstore.client.read(user_stream, options: { filter: { event_types: ['UserEmailChanged'] }, max_count: 1, direction: 'Backwards' }).first&.data&.dig('email')
  # Email hasn't changed - prevent publishing unnecessary changes
  next if old_email == user.email
  
  PgEventstore.client.append_to_stream(user_stream, UserEmailChanged.new(data: { email: user.email }))
  # This is the mistake. UserMailer.notify_email_changed may be triggered several times
  UserMailer.notify_email_changed(user.id, old_email: old_email, new_email: user.email).deliver_later
end
```

## Good

```ruby
old_email =
  PgEventstore.client.multiple do
    old_email = PgEventstore.client.read(user_stream, options: { filter: { event_types: ['UserEmailChanged'] }, max_count: 1, direction: 'Backwards' }).first&.data&.dig('email')
    # Email hasn't changed - prevent publishing unnecessary changes
    next if old_email == user.email

    PgEventstore.client.append_to_stream(user_stream, UserEmailChanged.new(data: { email: user.email }))
    old_email
  end
# Sending email outside multiple block to prevent potential re-triggering of it 
UserMailer.notify_email_changed(user.id, old_email: old_email, new_email: user.email).deliver_later
```

## Side effect of internal implementation

Please note that when publishing an event with a type as part of a `multiple` block that does not yet exist in the database, the block will run twice as the first attempt to publish will always fail due to the way `append_to_stream` is implemented. Consider this when writing expectations in your tests for example.
