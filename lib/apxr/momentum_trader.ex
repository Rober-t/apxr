defmodule APXR.MomentumTrader do
  @moduledoc """
  Momentum traders invest based on the belief that price changes have inertia
  a strategy known to be widely used. A momentum strategy involves taking a
  long position when prices have been recently rising, and a short position
  when they have recently been falling. Specifically, we implement simple
  momentum trading agents that rely on calculating a rate of change (ROC)
  to detect momentum.
  """

  @behaviour APXR.Trader

  use GenServer

  alias APXR.{
    Exchange,
    Trader
  }

  @mt_delta 0.4
  @mt_n 5
  @mt_k 0.001

  ## Client API

  @doc """
  Starts a MomentumTrader trader.
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
    :rand.seed(:exsplus, :os.timestamp())
    trader = init_trader(id)
    {:ok, %{trader: trader}}
  end

  @impl true
  def handle_call({:actuate}, _from, state) do
    trader = momentum_trader(state)
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

  defp momentum_trader(%{trader: %Trader{trader_id: tid, cash: cash, lag_price: lag_p} = trader})
       when lag_p == nil do
    venue = :apxr
    ticker = :apxr

    p = Exchange.last_price(venue, ticker)
    momentum_trader(venue, ticker, tid, p, p, cash, 0, trader)
  end

  defp momentum_trader(%{
         trader: %Trader{trader_id: tid, cash: cash, lag_price: {p1, counter}} = trader
       }) do
    venue = :apxr
    ticker = :apxr

    p = Exchange.last_price(venue, ticker)
    momentum_trader(venue, ticker, tid, p, p1, cash, counter, trader)
  end

  defp momentum_trader(venue, ticker, tid, p, p1, cash, counter, trader) do
    roc = rate_of_change(p, p1)
    vol = round(abs(roc) * cash)

    if rand() < @mt_delta do
      cost = momentum_trader_place_order(venue, ticker, tid, vol, roc)
      cash = max(cash - cost, 0.0) |> Float.round(2)

      %{trader | cash: cash}
      |> momentum_trader_update_lag_price(counter, p, p1)
    else
      momentum_trader_update_lag_price(trader, counter, p, p1)
    end
  end

  defp momentum_trader_place_order(venue, ticker, tid, vol, roc) do
    cond do
      roc >= @mt_k ->
        momentum_trader_place_order(venue, ticker, tid, vol, roc, :gt)

      roc <= @mt_k * -1 ->
        momentum_trader_place_order(venue, ticker, tid, vol, roc, :lt)

      true ->
        0.0
    end
  end

  defp momentum_trader_place_order(venue, ticker, tid, vol, _roc, :gt) do
    cost = Exchange.ask_price(venue, ticker) * vol
    Exchange.buy_market_order(venue, ticker, tid, vol)
    cost
  end

  defp momentum_trader_place_order(venue, ticker, tid, vol, _roc, :lt) do
    cost = Exchange.bid_price(venue, ticker) * vol
    Exchange.sell_market_order(venue, ticker, tid, vol)
    cost
  end

  defp momentum_trader_update_lag_price(trader, counter, p, p1) do
    if counter > @mt_n do
      %{trader | lag_price: {p, 0}}
    else
      %{trader | lag_price: {p1, counter + 1}}
    end
  end

  defp rate_of_change(p, p1) do
    (p - p1) / p1
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :momentum_trader,
      cash: 20_000_000.0,
      outstanding_orders: []
    }
  end

  defp rand() do
    :rand.uniform()
  end
end
