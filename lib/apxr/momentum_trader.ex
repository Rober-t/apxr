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
    OrderbookEvent,
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
    {:ok, _} = Registry.register(APXR.ReportingServiceRegistry, "orderbook_event", [])
    trader = init_trader(id)
    price = Exchange.last_price(:apxr, :apxr)
    {:ok, %{price_history: [price], roc: 0.0, trader: trader}}
  end

  @impl true
  def handle_call({:actuate}, _from, state) do
    state = action(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(
        {:broadcast, %OrderbookEvent{price: price, transaction: true, type: type}},
        state
      )
      when type in [
             :full_fill_buy_order,
             :full_fill_sell_order,
             :partial_fill_buy_order,
             :partial_fill_sell_order
           ] do
    state = update_roc(price, state)
    {:noreply, state}
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

  defp action(%{trader: %Trader{cash: 0.0}} = state) do
    state
  end

  defp action(%{roc: roc, trader: %Trader{trader_id: tid, cash: cash} = trader} = state) do
    venue = :apxr
    ticker = :apxr
    vol = round(roc * cash)

    if :rand.uniform() < @mt_delta do
      cost = place_order(venue, ticker, tid, vol, roc)
      cash = max(cash - cost, 0.0) |> Float.round(2)
      trader = %{trader | cash: cash}
      %{state | trader: trader}
    else
      state
    end
  end

  defp place_order(venue, ticker, tid, vol, roc) do
    cond do
      roc >= @mt_k ->
        place_order(venue, ticker, tid, vol, roc, :gt)

      roc <= @mt_k * -1 ->
        place_order(venue, ticker, tid, vol, roc, :lt)

      true ->
        0.0
    end
  end

  defp place_order(venue, ticker, tid, vol, _roc, :gt) do
    cost = Exchange.ask_price(venue, ticker) * vol
    Exchange.buy_market_order(venue, ticker, tid, vol)
    cost
  end

  defp place_order(venue, ticker, tid, vol, _roc, :lt) do
    cost = Exchange.bid_price(venue, ticker) * vol
    Exchange.sell_market_order(venue, ticker, tid, vol)
    cost
  end

  defp update_roc(price, %{price_history: price_history} = state) do
    [price_prev] = Enum.take(price_history, -1)
    roc = rate_of_change(price, price_prev)
    price_history = price_history(price, price_history)
    %{state | roc: roc, price_history: price_history}
  end

  defp price_history(price, price_history) do
    if length(price_history) < @mt_n do
      [price | price_history]
    else
      price_history = Enum.drop(price_history, -1)
      [price | price_history]
    end
  end

  defp rate_of_change(price, prive_prev) do
    abs((price - prive_prev) / prive_prev)
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :momentum_trader,
      cash: 20_000_000.0,
      outstanding_orders: []
    }
  end
end
