:ets.update_counter(:run_index, :iteration, 1, {0, 0})

Benchee.run(%{
  "insert and cancel a buy order": fn ->
    order1 = APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    APXR.Exchange.cancel_order(:apxr, :apxr, order1)
  end,
  "insert and cancel a sell order": fn ->
    order2 = APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    APXR.Exchange.cancel_order(:apxr, :apxr, order2)
  end
})

Benchee.run(%{
  "insert a buy market order": fn ->
    APXR.Exchange.buy_market_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100)
  end
})

Benchee.run(%{
  "insert a sell market order": fn ->
    APXR.Exchange.sell_market_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100)
  end
})

Benchee.run(%{
  "insert a buy limit order": fn ->
    APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
  end,
  "insert a sell limit order": fn ->
    APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
  end,
  "insert a buy then sell limit order": fn ->
    APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
  end,
  "insert 10 sell limit order": fn ->
    for _ <- 0..10 do
      APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end,
  "insert 10 buy limit order": fn ->
    for _ <- 0..10 do
      APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end,
  "insert 10 matching orders": fn ->
    for _ <- 0..10 do
      APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
      APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end,
  "insert 100 sell limit order": fn ->
    for _ <- 0..100 do
      APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end,
  "insert 100 buy limit order": fn ->
    for _ <- 0..100 do
      APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end,
  "insert 100 matching orders": fn ->
    for _ <- 0..100 do
      APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
      APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end,
  "insert 1000 sell limit order": fn ->
    for _ <- 0..1000 do
      APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end,
  "insert 1000 buy limit order": fn ->
    for _ <- 0..1000 do
      APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end,
  "insert 1000 matching orders": fn ->
    for _ <- 0..1000 do
      APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
      APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
    end
  end
})

Benchee.run(%{
  "get bid_price": fn ->
    APXR.Exchange.bid_price(:apxr, :apxr)
  end,
  "get ask_price": fn ->
    APXR.Exchange.ask_price(:apxr, :apxr)
  end
})
