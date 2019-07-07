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
    Market,
    Trader
  }

  alias Decimal, as: D

  @mt_delta D.new("0.4")
  @mt_n D.new("5")
  @mt_k D.new("0.001")

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
    GenServer.cast(via_tuple(id), {:actuate})
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
    # Uncomment for a constant random seed
    # :rand.seed(:exsplus, {1, 2, 3})
    trader = init_trader(id)
    {:ok, %{trader: trader}}
  end

  @impl true
  def handle_cast({:actuate}, state) do
    trader = momentum_trader(state)
    Market.ack(trader.trader_id)
    {:noreply, %{state | trader: trader}}
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

  @impl true
  def terminate(_reason, %{trader: trader}) do
    Market.ack(trader.trader_id)
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
    vol = D.abs(roc) |> D.mult(cash) |> D.round(0, :half_up) |> D.to_integer()

    if D.lt?(rand(), @mt_delta) do
      cost = momentum_trader_place_order(venue, ticker, tid, vol, roc)
      cash = cash |> D.sub(cost) |> D.max("0")

      %{trader | cash: cash}
      |> momentum_trader_update_lag_price(counter, p, p1)
    else
      momentum_trader_update_lag_price(trader, counter, p, p1)
    end
  end

  defp momentum_trader_place_order(venue, ticker, tid, vol, roc) do
    cond do
      D.gt?(roc, @mt_k) or D.eq?(roc, @mt_k) ->
        momentum_trader_place_order(venue, ticker, tid, vol, roc, :gt)

      D.lt?(roc, D.minus(@mt_k)) or D.eq?(roc, D.minus(@mt_k)) ->
        momentum_trader_place_order(venue, ticker, tid, vol, roc, :lt)

      true ->
        D.new("0")
    end
  end

  defp momentum_trader_place_order(venue, ticker, tid, vol, _roc, :gt) do
    cost = Exchange.ask_price(venue, ticker) |> D.mult(vol)
    Exchange.buy_market_order(venue, ticker, tid, vol)
    cost
  end

  defp momentum_trader_place_order(venue, ticker, tid, vol, _roc, :lt) do
    cost = Exchange.bid_price(venue, ticker) |> D.mult(vol)
    Exchange.sell_market_order(venue, ticker, tid, vol)
    cost
  end

  defp momentum_trader_update_lag_price(trader, counter, p, p1) do
    if D.gt?(counter, @mt_n) do
      %{trader | lag_price: {p, D.new("0")}}
    else
      %{trader | lag_price: {p1, D.add(counter, 1)}}
    end
  end

  defp rate_of_change(p, p1) do
    numer = D.sub(p, p1)
    D.div(numer, p1)
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :momentum_trader,
      cash: D.new("20000000"),
      outstanding_orders: []
    }
  end

  defp rand() do
    D.from_float(:rand.uniform())
  end
end
