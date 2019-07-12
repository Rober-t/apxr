defmodule APXR.RunSupervisor do
  # See https://hexdocs.pm/elixir/Supervisor.html
  # for other strategies and supported options

  @moduledoc false

  use Supervisor

  @init_price 100.0
  @init_vol 1

  # How many of each type of trader to initialize
  @liquidity_consumers 10
  @market_makers 10
  @mean_reversion_traders 40
  @momentum_traders 40
  @noise_traders 75
  @my_traders 1

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
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
    opts = [strategy: :one_for_all, name: APXR.RunSupervisor]
    Supervisor.init(children, opts)
  end

  # Private

  defp trader_config do
    [
      %{
        lcs: @liquidity_consumers,
        mms: @market_makers,
        mrts: @mean_reversion_traders,
        mmts: @momentum_traders,
        nts: @noise_traders,
        myts: @my_traders
      }
    ]
  end
end
