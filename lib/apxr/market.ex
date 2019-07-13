defmodule APXR.Market do
  @moduledoc """
  Coordinates the market participants, for example, summoning the traders to
  act each timestep.
  """

  use GenServer

  alias APXR.{
    Exchange,
    LiquidityConsumer,
    MarketMaker,
    MeanReversionTrader,
    MomentumTrader,
    MyTrader,
    NoiseTrader,
    ProgressBar,
    ReportingService,
    Simulation
  }

  @timesteps 10000

  ## Client API

  @doc """
  Starts a Market.
  """
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers a new simulation run. E.g. One day run of the market. 
  """
  def open(run_number) do
    GenServer.cast(__MODULE__, {:open, run_number})
  end

  ## Server callbacks

  @impl true
  def init([%{lcs: lcs, mms: mms, mrts: mrts, mmts: mmts, nts: nts, myts: myts}]) do
    :ets.new(:timestep, [:public, :named_table, read_concurrency: true])
    traders = init_traders(lcs, mms, mrts, mmts, nts, myts)
    {:ok, %{traders: traders}}
  end

  @impl true
  def handle_cast({:open, run_number}, state) do
    do_open(run_number, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private

  defp do_open(run_number, %{traders: traders}) do
    ReportingService.prep(run_number)
    call_to_action(traders)
  end

  defp call_to_action(traders) when is_list(traders) do
    IO.puts("\nMARKET OPEN")
    :ets.update_counter(:timestep, :step, 1, {0, 0})
    call_to_action(traders, 0, @timesteps)
  end

  defp call_to_action(_traders, i, 0) do
    ProgressBar.print(i, @timesteps)
    IO.puts("\nMARKET CLOSED")
    Simulation.run_over()
  end

  defp call_to_action(traders, i, timsteps_left) do
    if rem(i, 100) == 0, do: ProgressBar.print(i, @timesteps)

    maybe_populate_orderbook()

    for {type, id} <- traders do
      case type do
        MarketMaker ->
          MarketMaker.actuate({type, id})

        LiquidityConsumer ->
          LiquidityConsumer.actuate({type, id})

        MomentumTrader ->
          MomentumTrader.actuate({type, id})

        MeanReversionTrader ->
          MeanReversionTrader.actuate({type, id})

        NoiseTrader ->
          NoiseTrader.actuate({type, id})

        MyTrader ->
          MyTrader.actuate({type, id})
      end
    end

    Exchange.mid_price(:apxr, :apxr)
    |> ReportingService.push_mid_price(i + 1)

    :ets.update_counter(:timestep, :step, 1)

    Enum.shuffle(traders) |> call_to_action(i + 1, timsteps_left - 1)
  end

  defp maybe_populate_orderbook() do
    if Exchange.highest_bid_prices(:apxr, :apxr) == [] or
         Exchange.lowest_ask_prices(:apxr, :apxr) == [] do
      NoiseTrader.actuate({NoiseTrader, 1})
    end
  end

  defp init_traders(lcs, mms, mrts, mmts, nts, myts) do
    lcs = for id <- 1..lcs, do: {APXR.LiquidityConsumer, id}
    mms = for id <- 1..mms, do: {APXR.MarketMaker, id}
    mrts = for id <- 1..mrts, do: {APXR.MeanReversionTrader, id}
    mmts = for id <- 1..mmts, do: {APXR.MomentumTrader, id}
    nts = for id <- 1..nts, do: {APXR.NoiseTrader, id}
    myts = for id <- 1..myts, do: {APXR.MyTrader, id}

    lcs ++ mms ++ mrts ++ mmts ++ nts ++ myts
  end
end
