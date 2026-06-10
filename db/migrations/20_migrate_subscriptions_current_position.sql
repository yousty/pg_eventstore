update subscriptions
set current_position = (select subscription_position
                        from public.events_global_index
                        where global_position >= subscriptions.current_position
                        order by global_position
                        limit 1)
where current_position is not null
