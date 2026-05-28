# Querying events

## Intro

This document describes how pg_eventstore reads events in different situations. Basically, there are two main purposes:
- read events as a part of subscription pulling process
- read events using Read API(`Client#read` and `Client#read_paginated` methods)

Additionally, we differentiate a query to index table and a query to `events` table. There are two index tables:
- `events_global_index` table which holds summary about events
- `streams_global_index` table which holds summary about event streams

## Building a query

The intention behind different approaches is to have predictable SQL query plan for billions of records while covering all possible filtering cases and not depend on data distribution inside the database.

For subscription queries we chose simplicity. It may result in not ideal query plan, but it allows to accept filters of any size(e.g. let's say you need to build a projection, based on 1000 event types). Which is why every subscription query range is limited with `global_position >= $1 and global_position <= $1`. It is totally acceptable during catch-up phase, when a subscription starts from zero position and walks through entire database. Such limitation does not affect much when processing events on the edge of its position, too. Thus, even if PostgreSQL decides to fall back to seq scan - it is additionally limited by the `global_position` range we provide.

For Read API queries we chose the best possible plan for the cost of complexity of a query. Opposed to subscription queries - Read API queries are not supposed to handle complex filters with thousands of filter options. Instead, its purpose is to provide fast access to events to ensure the business logic rules.

### Reading from specific stream without events filter

#### For subscription

Not supported

#### For Read API

```sql
select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $1 and stream_revision >= $2 
                                  order by stream_revision 
                                  limit $3
```

### Reading from specific stream with events filter

#### For subscription 

Not supported

#### For Read API

```sql
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $1 and event_type_partition_id = $2 and stream_revision >= $3 order by stream_revision limit $4)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $1 and event_type_partition_id = $5 and stream_revision >= $3 order by stream_revision limit $4)
order by stream_revision
limit $4
```

### Reading from $all stream without any filters

#### For subscription

```sql
select global_position, event_type_partition_id from events_global_index where global_position >= $1 and global_position <= $2 order by global_position limit $3
```

#### For Read API

```sql
select global_position, event_type_partition_id from events_global_index where global_position >= $1 order by global_position limit $2;
```

### Reading from $all stream with specific event types filter

Example:

```ruby
{
  options:
    { filter:
        {
          event_types: %w[Foo Bar]
        }
    }
}
```

#### For subscription

```sql
select global_position, event_type_partition_id from events_global_index where event_type_partition_id in ($1) and global_position >= $2 and 
                                        global_position <= $3 
                                  order by global_position 
                                  limit $4
```

#### For Read API

```sql
(select global_position, event_type_partition_id from events_global_index where event_type_partition_id = $1 and global_position >= $2 order by global_position limit $4)
union all
(select global_position, event_type_partition_id from events_global_index where event_type_partition_id = $3 and global_position >= $2 order by global_position limit $4)
order by global_position
limit $4
```

### Reading from $all stream with context filter

Example:

```ruby
{
  options:
    { filter:
        {
          streams: [
            { context: 'FooCtx' },
            { context: 'BazCtx' }
          ]
        }
    }
}
```

#### For subscription

```sql
select global_position, event_type_partition_id from events_global_index where context_partition_id in ($1) and global_position >= $2 and 
                                        global_position <= $3 
                                  order by global_position 
                                  limit $4
```

#### For Read API

```sql
(select global_position, event_type_partition_id from events_global_index where context_partition_id = $1 order by global_position limit $3)
union all
(select global_position, event_type_partition_id from events_global_index where context_partition_id = $2 order by global_position limit $3)
order by global_position
limit $3
```

### Reading from $all stream with context & stream name filter

Example:

```ruby
{
  options:
    { filter:
        {
          streams: [
            { context: 'FooCtx', stream_name: 'Foo' },
            { context: 'BazCtx', stream_name: 'Bar' }
          ]
        }
    }
}
```

#### For subscription

Note: context constraint is already a part of stream name constraint

```sql
select global_position, event_type_partition_id from events_global_index where stream_name_partition_id in ($1) and global_position >= $2 and 
                                        global_position <= $3 
                                  order by global_position 
                                  limit $4
```

#### For Read API

```sql
(select global_position, event_type_partition_id from events_global_index where stream_name_partition_id = $1 order by global_position limit $3)
union all
(select global_position, event_type_partition_id from events_global_index where stream_name_partition_id = $2 order by global_position limit $3)
order by global_position
limit $3
```

### Reading from $all stream with specific stream filter(s) and another context filter(s)

Example:

```ruby
{
  options:
    { filter:
        {
          streams: [
            { context: 'FooCtx' },
            { context: 'BazCtx' },
            { context: 'BarCtx', stream_name: 'Bar', stream_id: '1' }
          ]
        }
    }
}
```

#### For subscription

```sql
select global_position, event_type_partition_id from events_global_index where (context_partition_id in ($1) or streams_global_index_id in ($2)) and 
                                        global_position >= $3 and global_position <= $4 
                                  order by global_position 
                                  limit $5
```

#### For Read API


```sql
(select global_position, event_type_partition_id from events_global_index where context_partition_id = $1 order by global_position limit $4)
union all
(select global_position, event_type_partition_id from events_global_index where context_partition_id = $2 order by global_position limit $4)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $3 order by global_position limit $4)
order by global_position
limit $4
```

### Reading from $all stream with specific stream filter(s) and another context & stream name filter(s)

Example:

```ruby
{
  options:
    { filter:
        {
          streams: [
            { context: 'FooCtx', stream_name: 'Foo' },
            { context: 'FooCtx', stream_name: 'Baz' },
            { context: 'BarCtx', stream_name: 'Bar', stream_id: '1' }
          ]
        }
    }
}
```

#### For subscription

Note: context constraint is already a part of stream name constraint

```sql
select global_position, event_type_partition_id from events_global_index where (stream_name_partition_id in ($1) or streams_global_index_id in ($2)) and 
                                        global_position >= $3 and global_position <= $4 
                                  order by global_position 
                                  limit $5
```

#### For Read API

```sql
(select global_position, event_type_partition_id from events_global_index where stream_name_partition_id = $1 order by global_position limit $4)
union all
(select global_position, event_type_partition_id from events_global_index where stream_name_partition_id = $2 order by global_position limit $4)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $3 order by global_position limit $4)
order by global_position
limit $4
```

### Reading from $all stream with specific stream filter(s) and another event type filter(s)

Example:

```ruby
{
  options:
    { filter:
        {
          streams: [
            { context: 'BarCtx', stream_name: 'Bar', stream_id: '1' },
            { context: 'BarCtx', stream_name: 'Bar', stream_id: '2' }
          ],
          event_types: %w[Foo Bar]
        }
    }
}
```

#### For subscription

```sql
select global_position, event_type_partition_id from events_global_index where event_type_partition_id in ($1) and streams_global_index_id in ($2) and 
                                        global_position >= $3 and global_position <= $4 
                                  order by global_position 
                                  limit $5
```

#### For Read API

We have to expand each combination of stream and event type into a separate query and union them:

```sql
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $1 and event_type_partition_id = $2 order by global_position limit $3)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $1 and event_type_partition_id = $4 order by global_position limit $3)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $5 and event_type_partition_id = $2 order by global_position limit $3)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $5 and event_type_partition_id = $4 order by global_position limit $3)
order by global_position
limit $3
```

### Reading from $all stream with specific stream filter(s) and context filter and event type filter(s)

Example:

```ruby
{
  options:
    { filter:
        {
          streams: [
            { context: 'FooCtx' }, 
            { context: 'BarCtx', stream_name: 'Bar', stream_id: '1' },
            { context: 'BarCtx', stream_name: 'Bar', stream_id: '2' }
          ],
          event_types: %w[Foo Bar]
        }
    }
}
```

#### For subscription

Note, that in case with `{ context: 'FooCtx' }` and `event_types: %w[Foo Bar]` we simply replace it with events partitions list `$3`

```sql
select global_position, event_type_partition_id from events_global_index where (
        (event_type_partition_id in ($1) and streams_global_index_id in ($2)) or event_type_partition_id in ($3)
    ) and global_position >= $4 and global_position <= $5 order by global_position limit $6
```

#### For Read API

```sql
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $1 and event_type_partition_id = $2 order by global_position limit $3)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $1 and event_type_partition_id = $4 order by global_position limit $3)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $5 and event_type_partition_id = $2 order by global_position limit $3)
union all
(select global_position, event_type_partition_id from events_global_index where streams_global_index_id = $5 and event_type_partition_id = $4 order by global_position limit $3)
order by global_position
limit $3
```
