defmodule APXR.TraderSupervisor do
  # See https://hexdocs.pm/elixir/Supervisor.html
  # for other strategies and supported options

  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init([
        %{
          liquidity_consumers: lcs,
          market_makers: mms,
          mean_reversion_traders: mrts,
          momentum_traders: mmts,
          noise_traders: nts,
          my_traders: myts
        }
      ])
      when is_integer(lcs) and is_integer(mms) and is_integer(mrts) and is_integer(mmts) and
             is_integer(nts) and is_integer(myts) do
    children =
      liquidity_consumers(lcs) ++
        market_makers(mms) ++
        mean_reversion_traders(mrts) ++
        momentum_traders(mmts) ++ noise_traders(nts) ++ my_traders(myts)

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private

  defp liquidity_consumers(liquidity_consumers) do
    for id <- 1..liquidity_consumers,
        do: Supervisor.child_spec({APXR.LiquidityConsumer, id}, id: {:liquidity_consumer, id})
  end

  defp market_makers(market_makers) do
    for id <- 1..market_makers,
        do: Supervisor.child_spec({APXR.MarketMaker, id}, id: {:market_maker, id})
  end

  defp mean_reversion_traders(mean_reversion_traders) do
    for id <- 1..mean_reversion_traders,
        do:
          Supervisor.child_spec({APXR.MeanReversionTrader, id}, id: {:mean_reversion_trader, id})
  end

  defp momentum_traders(momentum_traders) do
    for id <- 1..momentum_traders,
        do: Supervisor.child_spec({APXR.MomentumTrader, id}, id: {:momentum_trader, id})
  end

  defp noise_traders(noise_traders) do
    for id <- 1..noise_traders,
        do: Supervisor.child_spec({APXR.NoiseTrader, id}, id: {:noise_trader, id})
  end

  defp my_traders(my_traders) do
    for id <- 1..my_traders, do: Supervisor.child_spec({APXR.MyTrader, id}, id: {:my_trader, id})
  end
end
