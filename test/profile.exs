:ets.update_counter(:run_number, :number, 1, {0, 0})
:ets.update_counter(:timestep, :step, 1, {0, 0})

for _ <- 0..1000 do
  APXR.Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
  APXR.Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, 100.0, 100)
end
