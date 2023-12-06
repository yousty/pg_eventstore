# Multiple commands

`pg_eventstore` implements `#multiple` method to allow you to make several different commands atomic. Example:

```ruby
PgEventstore.client.multiple do
  unless PgEventstore.client.read(stream3, options: { max_count: 1, direction: 'Backwards' }).last&.type == 'Removed'
    PgEventstore.client.append_to_stream(stream1, event1)
    PgEventstore.client.append_to_stream(stream2, event2)
  end  
end
```

All commands inside a block either all succeed or all fail. This allows you to easily implement complex business rules. This, however, comes with a price of performance. The more you put in a single block - the higher chance it will have conflicts with other commands that come in parallel, thus increasing overall time to complete. **Thus, do not put more than needed in there.** You may still want to use it though as it could simplify your implementation.

**Please take into account, due to concurrency of parallel commands - a block of code may be re-run several times before succeed.** Thus, if you put any piece of code besides `pg_evenstore`'s commands - make sure it returns the correct result during re-runs. A simple example:

```ruby
class PaymentService
  def initialize
    @gateway = MyPaymentGateway.new
  end

  def pay_for(order)
    stream1 = PgEventstore::Stream.new(context: 'User', stream_name: 'Order', id: order.id)
    stream2 = PgEventstore::Stream.new(context: 'User', stream_name: 'InternalTransfer', id: order.user_id)
    
    PgEventstore.client.multiple do
      payment = @gateway.pay_for(order)
      PgEventstore.client.append_to_stream(stream1, OrderPayed.new(data: { order_id: order.id }))
      PgEventstore.client.append_to_stream(
        stream2, 
        DepositReceived.new(data: { amount: payment.amount, user_id: order.user_id, payment_id: payment.id })
      )      
    end
  end
end
```

In this particular example `amount = @gateway.pay_for(order)` line must return the same result(meaning it must not produce another payment) when run again with same argument. Thus, those steps - payment request, appending of first event and appending of second event either all succeed or all fail.
