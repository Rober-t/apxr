defmodule APXR.Market do
  @moduledoc """
  Coordinates the market participants, for example, summoning the traders to
  act each iteration.
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
    ReportingService
  }

  if Application.get_env(:apxr, :environment) == :test do
    @iterations 100
  else
    @iterations 300_000
  end

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
  def open do
    GenServer.cast(__MODULE__, {:open})
  end

  @doc """
  Handles ack messages from a Trader process.
  """
  def ack(trader_id) do
    GenServer.cast(__MODULE__, {:ack, trader_id})
  end

  ## Server callbacks

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
      ]) do
    :rand.seed(:exsplus)
    # Uncomment for a constant random seed
    # :rand.seed(:exsplus, {1, 2, 3})
    :ets.new(:run_index, [:public, :named_table])
    traders = init_traders(lcs, mms, mrts, mmts, nts, myts)
    {:ok, %{traders: traders, ackd_traders: [], run_index: 0, iterations_left: @iterations}}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:open}, state) do
    open(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:ack, trader_id}, state) do
    state = do_process_ack(trader_id, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private

  defp open(%{traders: traders} = _state) do
    call_to_action(traders)
  end

  defp call_to_action(traders) when is_list(traders) do
    IO.puts("")
    IO.puts("MARKET OPEN")
    IO.puts("")

    :ets.update_counter(:run_index, :iteration, 1, {0, 0})

    call_to_action(traders, 0, @iterations)
  end

  defp call_to_action(_traders, i, 0) do
    ProgressBar.print(i, @iterations)

    IO.puts("\n")
    IO.puts("MARKET CLOSED")
    IO.puts("")

    System.stop(0)
  end

  defp call_to_action(traders, i, _iterations_left) do
    if rem(i, 500) == 0, do: ProgressBar.print(i, @iterations)

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
  end

  defp maybe_populate_orderbook() do
    if Exchange.highest_bid_prices(:apxr, :apxr) == [] or
         Exchange.lowest_ask_prices(:apxr, :apxr) == [] do
      NoiseTrader.actuate({NoiseTrader, 1})
    end
  end

  defp do_process_ack(trader_id, %{
         traders: traders,
         ackd_traders: ackd_traders,
         run_index: i,
         iterations_left: iterations
       }) do
    traders = Enum.reject(traders, fn tid -> tid == trader_id end)
    ackd_traders = [trader_id | ackd_traders]

    if traders == [] do
      Exchange.mid_price(:apxr, :apxr) |> ReportingService.push_mid_price(i + 1)

      :ets.update_counter(:run_index, :iteration, 1)

      Enum.shuffle(ackd_traders) |> call_to_action(i + 1, iterations - 1)

      %{
        traders: ackd_traders,
        ackd_traders: traders,
        run_index: i + 1,
        iterations_left: iterations - 1
      }
    else
      %{traders: traders, ackd_traders: ackd_traders, run_index: i, iterations_left: iterations}
    end
  end

  defp init_traders(lcs, mms, mrts, mmts, nts, myts) do
    liquidity_consumers = for id <- 1..lcs, do: {APXR.LiquidityConsumer, id}
    market_makers = for id <- 1..mms, do: {APXR.MarketMaker, id}
    mean_reversion_traders = for id <- 1..mrts, do: {APXR.MeanReversionTrader, id}
    momentum_traders = for id <- 1..mmts, do: {APXR.MomentumTrader, id}
    noise_traders = for id <- 1..nts, do: {APXR.NoiseTrader, id}
    my_traders = for id <- 1..myts, do: {APXR.MyTrader, id}

    liquidity_consumers ++
      market_makers ++ mean_reversion_traders ++ momentum_traders ++ noise_traders ++ my_traders
  end
end
