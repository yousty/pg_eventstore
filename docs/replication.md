# Database replication

pg_eventstore can be replicated, but for different purposes you should choose different replication strategies. This is
related to the complex architecture of pg_eventstore database(some tables are partitioned) and to the neediness to have
only certain tables list in your replica node. For example, such tables as `subscriptions`, `subscriptions_set`, 
`event_subscription_positions_unprocessed`, `subscription_commands`, `subscriptions_set_commands` must not present in
the replica, because they are node-specific.

Let's review a simple example and, based on it, we build a replica setup. So, let's say we have distributed
architecture, and we target three regions - EU, US and Asia. We then want to have primary node along with two replica
nodes of two other regions per region. We want to have a hot standby replica per region in case of emergency as well. We
can summarize this description as follows:

## EU Region

- **EU primary**
    - Replicates to: **EU hot standby**
    - Replicates to: **US replica node**
    - Replicates to: **Asia replica node**

- **US replica**
    - Source: async replication from **US primary**

- **Asia replica**
    - Source: async replication from **Asia primary**

- **EU read models** built from:
    - EU primary
    - US replica
    - Asia replica

## US Region

- **US primary**
    - Replicates to: **US hot standby**
    - Replicates to: **EU replica node**
    - Replicates to: **Asia replica node** 

- **EU replica**
    - Source: async replication from **EU primary**

- **Asia replica**
    - Source: async replication from **Asia primary**

- **US read models** built from:
    - US primary
    - EU replica
    - Asia replica

## Asia Region

- **Asia primary**
    - Replicates to: **Asia hot standby**
    - Replicates to: **US replica node**
    - Replicates to: **EU replica node**

- **EU replica**
    - Source: async replication from **EU primary**

- **US replica**
    - Source: async replication from **US primary**

- **Asia read models** built from:
    - Asia primary
    - EU replica
    - US replica

From the example above:
- applications, connecting to primary node should have `:primary` [role](configuration.md#eventstore-role)
- applications, connecting to replica node should have `:replica` [role](configuration.md#eventstore-role)
- hot standby replica should utilize [streaming WAL](https://www.postgresql.org/docs/current/warm-standby.html#STREAMING-REPLICATION) replication. This will be a full copy of region's primary node
- region replicas should utilize pg_eventstore replication via `#create_replication`. Example (from the perspective of
  US region primary node):
```ruby
# config.rb
PgEventstore.configure do |config|
  config.pg_uri = 'postgresql://postgres:postgres@localhost:6432/eventstore_us'
  config.eventstore_role = :primary
end

PgEventstore.configure(name: :eu_replica) do |config|
  config.pg_uri = 'postgresql://postgres:postgres@localhost:6432/eventstore_us'
  config.eventstore_role = :replica
end

PgEventstore.configure(name: :asia_replica) do |config|
  config.pg_uri = 'postgresql://postgres:postgres@localhost:6432/eventstore_us'
  config.eventstore_role = :replica
end

# subscriptions
subscriptions_manager = PgEventstore.subscriptions_manager(subscription_set: "Replications")
# Replicates US pg_eventstore into EU region pg_eventstore
subscriptions_manager.create_replication('EU', :eu_replica)
# Replicates US pg_eventstore into Asia region pg_eventstore
subscriptions_manager.create_replication('Asia', :asia_replica)

subscriptions_manager.start
```
