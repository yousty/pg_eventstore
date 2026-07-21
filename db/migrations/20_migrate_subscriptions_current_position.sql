update subscriptions
set current_position = (select subscription_position
                        from event_subscription_positions
                        where global_position <= subscriptions.current_position
                        order by global_position desc
                        limit 1)
where current_position is not null;

update subscriptions
set options = jsonb_set(
    options,
    '{from_position}',
    to_jsonb(coalesce((select subscription_position
                       from event_subscription_positions
                       where global_position <= (subscriptions.options ->> 'from_position')::bigint
                       order by global_position desc
                       limit 1), 0))
)
where options ? 'from_position';
