update subscriptions
set current_position = (select subscription_position
                        from event_subscription_positions
                        where global_position <= subscriptions.current_position
                        order by global_position desc
                        limit 1)
where current_position is not null
