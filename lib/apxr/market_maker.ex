defmodule APXR.MarketMaker do
  @moduledoc """
  Market makers represent market participants who attempt to earn the spread
  by supplying liquidity on both sides of the LOB. In traditional markets,
  market makers were appointed but in modern electronic exchanges any agent
  is able to follow such a strategy. These agents simultaneously post an order
  on each side of the book, maintaining an approximately neutral position
  throughout the day. They make their income from the difference between
  their bids and asks. If one or both limit orders is executed, it will be
  replaced by a new one the next time the market maker is chosen to trade. 
  """

  @behaviour APXR.Trader

  use GenServer

  alias APXR.{
    Exchange,
    Market,
    Order,
    OrderbookEvent,
    Trader
  }

  alias Decimal, as: D

  @mm_delta D.new("0.1")
  @mm_w 50
  @mm_max_vol 200_000
  @mm_vol 1

  ## Client API

  @doc """
  Starts a MarketMaker trader.
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
    {:ok, _} = Registry.register(APXR.ReportingServiceRegistry, "orderbook_event", [])
    trader = init_trader(id)
    init_side = Enum.random(0..1)
    {:ok, %{order_side_history: [init_side], trader: trader}}
  end

  @impl true
  def handle_cast({:actuate}, state) do
    trader = market_maker(state)
    Market.ack(trader.trader_id)
    {:noreply, %{state | trader: trader}}
  end

  @impl true
  def handle_cast({:broadcast, %OrderbookEvent{type: :new_market_order} = event}, state) do
    state = update_order_side_history(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast, %OrderbookEvent{type: :new_limit_order} = event}, state) do
    state = update_order_side_history(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:execution_report, order, msg}, state) do
    state = update_outstanding_orders(order, state, msg)
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

  defp update_outstanding_orders(
         %Order{order_id: order_id},
         %{trader: %Trader{outstanding_orders: outstanding_orders} = trader} = state,
         msg
       )
       when msg in [:full_fill_buy_order, :full_fill_sell_order] do
    outstanding_orders =
      Enum.reject(outstanding_orders, fn %Order{order_id: id} -> id == order_id end)

    trader = %{trader | outstanding_orders: outstanding_orders}
    %{state | trader: trader}
  end

  defp update_outstanding_orders(
         %Order{order_id: order_id} = order,
         %{trader: %Trader{outstanding_orders: outstanding_orders} = trader} = state,
         msg
       )
       when msg in [:partial_fill_buy_order, :partial_fill_sell_order] do
    outstanding_orders =
      Enum.reject(outstanding_orders, fn %Order{order_id: id} -> id == order_id end)

    trader = %{trader | outstanding_orders: [order | outstanding_orders]}
    %{state | trader: trader}
  end

  defp update_outstanding_orders(
         %Order{order_id: order_id},
         %{trader: %Trader{outstanding_orders: outstanding_orders} = trader} = state,
         :cancelled_order
       ) do
    outstanding_orders =
      Enum.reject(outstanding_orders, fn %Order{order_id: id} -> id == order_id end)

    trader = %{trader | outstanding_orders: outstanding_orders}
    %{state | trader: trader}
  end

  defp market_maker(%{
         order_side_history: order_side_history,
         trader:
           %Trader{trader_id: tid, cash: cash, outstanding_orders: outstanding_orders} = trader
       }) do
    venue = :apxr
    ticker = :apxr

    bid_price = Exchange.bid_price(venue, ticker)
    ask_price = Exchange.ask_price(venue, ticker)

    prediction = simple_moving_avg(order_side_history)

    if D.lt?(rand(), @mm_delta) do
      for order <- outstanding_orders, do: Exchange.cancel_order(venue, ticker, order)

      {cost, orders} =
        market_maker_place_order(venue, ticker, tid, ask_price, bid_price, prediction)

      cash = cash |> D.sub(cost) |> D.max("0")
      %{trader | cash: cash, outstanding_orders: orders}
    else
      trader
    end
  end

  defp market_maker_place_order(venue, ticker, tid, ask_price, bid_price, prediction) do
    if D.lt?(prediction, "0.5") do
      market_maker_place_order(venue, ticker, tid, ask_price, bid_price, prediction, :lt)
    else
      market_maker_place_order(venue, ticker, tid, ask_price, bid_price, prediction, :gt)
    end
  end

  defp market_maker_place_order(venue, ticker, tid, ask_price, bid_price, _prediction, :lt) do
    vol = :rand.uniform(@mm_max_vol)

    order1 = Exchange.sell_limit_order(venue, ticker, tid, ask_price, vol)
    order2 = Exchange.buy_limit_order(venue, ticker, tid, bid_price, @mm_vol)

    orders = Enum.reject([order1, order2], fn order -> order == :rejected end)
    cost = D.add(D.mult(ask_price, vol), D.mult(bid_price, @mm_vol))

    {cost, orders}
  end

  defp market_maker_place_order(venue, ticker, tid, ask_price, bid_price, _prediction, :gt) do
    vol = :rand.uniform(@mm_max_vol)

    order1 = Exchange.buy_limit_order(venue, ticker, tid, bid_price, vol)
    order2 = Exchange.sell_limit_order(venue, ticker, tid, ask_price, @mm_vol)

    orders = Enum.reject([order1, order2], fn order -> order == :rejected end)
    cost = D.add(D.mult(ask_price, @mm_vol), D.mult(bid_price, vol))

    {cost, orders}
  end

  defp simple_moving_avg(items) when is_list(items) do
    Enum.reduce(items, 0, fn x, acc -> D.add(x, acc) end)
    |> D.div(length(items))
  end

  defp update_order_side_history(
         %OrderbookEvent{direction: side},
         %{order_side_history: order_side_history} = state
       ) do
    order_side_history =
      if length(order_side_history) < @mm_w do
        [side | order_side_history]
      else
        [side | Enum.drop(order_side_history, -1)]
      end

    %{state | order_side_history: order_side_history}
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :market_maker,
      cash: D.new("20000000"),
      outstanding_orders: []
    }
  end

  defp rand() do
    D.from_float(:rand.uniform())
  end
end
