defmodule APXR.LiquidityConsumer do
  @moduledoc """
  Liquidity consumers represent large slower moving funds that make long term
  trading decisions based on the re-balancing of portfolios. In real world
  markets, these are likely to be large institutional investors. These agents
  are either buying or selling a large order of stock over the course of a day
  for which they hope to minimize price impact and trading costs. Whether these
  agents are buying or selling is assigned with equal probability.
  """

  @behaviour APXR.Trader

  use GenServer

  alias APXR.{
    Exchange,
    Trader
  }

  @lc_delta 0.1
  @lc_max_vol 100_000

  ## Client API

  @doc """
  Starts a LiquidityConsumer trader.
  """
  def start_link(id) when is_integer(id) do
    name = via_tuple({__MODULE__, id})
    GenServer.start_link(__MODULE__, id, name: name)
  end

  @doc """
  Call to action.

  Returns `{:ok, :done}`.
  """
  @impl Trader
  def actuate(id) do
    GenServer.call(via_tuple(id), {:actuate}, 30000)
  end

  @doc """
  Update from Exchange concerning an order.
  """
  @impl true
  def execution_report(id, order, msg) do
    GenServer.cast(via_tuple(id), {:execution_report, order, msg})
  end

  ## Server callbacks

  @impl true
  def init(id) do
    :rand.seed(:exsplus)
    trader = init_trader(id)
    {:ok, %{trader: trader}}
  end

  @impl true
  def handle_call({:actuate}, _from, state) do
    trader = liquidity_consumer(state)
    {:reply, :ok, %{state | trader: trader}}
  end

  @impl true
  def handle_cast({:execution_report, _order, _msg}, state) do
    # Do nothing
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private

  defp via_tuple(id) do
    {:via, Registry, {APXR.TraderRegistry, id}}
  end

  defp liquidity_consumer(%{trader: %Trader{vol_to_fill: 0} = trader}) do
    trader
  end

  defp liquidity_consumer(%{
         trader: %Trader{trader_id: tid, cash: cash, side: side, vol_to_fill: vol} = trader
       }) do
    venue = :apxr
    ticker = :apxr

    current_vol_avbl = vol_avbl_opp_best_price(venue, ticker, side)

    if rand() < @lc_delta do
      cost = liquidity_consumer_place_order(venue, ticker, tid, vol, current_vol_avbl, side)
      cash = max(cash - cost, 0.0) |> Float.round(2)

      trader = %{trader | cash: cash}
      update_vol_to_fill(vol, current_vol_avbl, trader)
    else
      update_vol_to_fill(vol, current_vol_avbl, trader)
    end
  end

  defp liquidity_consumer_place_order(venue, ticker, tid, vol, current_vol_avbl, :buy)
       when vol <= current_vol_avbl do
    cost = Exchange.ask_price(venue, ticker) * vol
    Exchange.buy_market_order(venue, ticker, tid, vol)
    cost
  end

  defp liquidity_consumer_place_order(venue, ticker, tid, _vol, current_vol_avbl, :buy) do
    cost = Exchange.ask_price(venue, ticker) * current_vol_avbl
    Exchange.buy_market_order(venue, ticker, tid, current_vol_avbl)
    cost
  end

  defp liquidity_consumer_place_order(venue, ticker, tid, vol, current_vol_avbl, :sell)
       when vol <= current_vol_avbl do
    cost = Exchange.bid_price(venue, ticker) * vol
    Exchange.sell_market_order(venue, ticker, tid, vol)
    cost
  end

  defp liquidity_consumer_place_order(venue, ticker, tid, _vol, current_vol_avbl, :sell) do
    cost = Exchange.bid_price(venue, ticker) * current_vol_avbl
    Exchange.sell_market_order(venue, ticker, tid, current_vol_avbl)
    cost
  end

  defp update_vol_to_fill(vol, vol_avbl, trader) when vol <= vol_avbl do
    %{trader | vol_to_fill: 0}
  end

  defp update_vol_to_fill(vol, vol_avbl, trader) do
    %{trader | vol_to_fill: vol - vol_avbl}
  end

  defp order_side do
    if rand() < 0.5 do
      :buy
    else
      :sell
    end
  end

  defp vol_avbl_opp_best_price(venue, ticker, :buy) do
    Exchange.ask_size(venue, ticker)
  end

  defp vol_avbl_opp_best_price(venue, ticker, :sell) do
    Exchange.bid_size(venue, ticker)
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :liquidity_consumer,
      cash: 20_000_000.0,
      outstanding_orders: [],
      side: order_side(),
      vol_to_fill: :rand.uniform(@lc_max_vol)
    }
  end

  defp rand() do
    :rand.uniform()
  end
end
