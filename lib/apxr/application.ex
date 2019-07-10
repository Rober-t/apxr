defmodule APXR.Application do
  @moduledoc """
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications
  """

  use Application

  @init_price 100.0
  @init_vol 1

  # How many of each type of trader to initialize
  @liquidity_consumers 5
  @market_makers 5
  @mean_reversion_traders 20
  @momentum_traders 20
  @noise_traders 40
  @my_traders 1

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      Supervisor.child_spec(
        {Registry,
         [
           keys: :duplicate,
           name: APXR.ReportingServiceRegistry,
           partitions: System.schedulers_online()
         ]},
        id: :reporting_service
      ),
      Supervisor.child_spec(
        {Registry,
         [
           keys: :unique,
           name: APXR.ExchangeRegistry,
           partitions: System.schedulers_online()
         ]},
        id: :exchange_registry
      ),
      Supervisor.child_spec(
        {Registry,
         [
           keys: :unique,
           name: APXR.TraderRegistry,
           partitions: System.schedulers_online()
         ]},
        id: :trader_registry
      ),
      APXR.ReportingService,
      {APXR.Exchange, [:apxr, :apxr, @init_price, @init_vol]},
      {APXR.TraderSupervisor, trader_config()},
      {APXR.Market, trader_config()}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_all, name: APXR.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp trader_config do
    [
      %{
        liquidity_consumers: @liquidity_consumers,
        market_makers: @market_makers,
        mean_reversion_traders: @mean_reversion_traders,
        momentum_traders: @momentum_traders,
        noise_traders: @noise_traders,
        my_traders: @my_traders
      }
    ]
  end
end
