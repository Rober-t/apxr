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
    Order,
    OrderbookEvent,
    Trader
  }

  @mm_delta 0.1
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
    init_side = Enum.random(0..1)
    {:ok, %{order_side_history: [init_side], trader: trader}}
  end

  @impl true
  def handle_call({:actuate}, _from, state) do
    trader = market_maker(state)
    {:reply, :ok, %{state | trader: trader}}
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

  ## Private

  defp via_tuple(id) do
    {:via, Registry, {APXR.TraderRegistry, id}}
  end

  defp update_outstanding_orders(
         %Order{order_id: order_id},
         %{trader: %Trader{outstanding_orders: outstanding} = trader} = state,
         msg
       )
       when msg in [:full_fill_buy_order, :full_fill_sell_order] do
    outstanding = Enum.reject(outstanding, fn %Order{order_id: id} -> id == order_id end)
    trader = %{trader | outstanding_orders: outstanding}
    %{state | trader: trader}
  end

  defp update_outstanding_orders(
         %Order{order_id: order_id} = order,
         %{trader: %Trader{outstanding_orders: outstanding} = trader} = state,
         msg
       )
       when msg in [:partial_fill_buy_order, :partial_fill_sell_order] do
    outstanding = Enum.reject(outstanding, fn %Order{order_id: id} -> id == order_id end)
    trader = %{trader | outstanding_orders: [order | outstanding]}
    %{state | trader: trader}
  end

  defp update_outstanding_orders(
         %Order{order_id: order_id},
         %{trader: %Trader{outstanding_orders: outstanding} = trader} = state,
         :cancelled_order
       ) do
    outstanding = Enum.reject(outstanding, fn %Order{order_id: id} -> id == order_id end)
    trader = %{trader | outstanding_orders: outstanding}
    %{state | trader: trader}
  end

  defp market_maker(%{
         order_side_history: order_side_history,
         trader: %Trader{trader_id: tid, cash: cash, outstanding_orders: outstanding} = trader
       }) do
    venue = :apxr
    ticker = :apxr
    bid = Exchange.bid_price(venue, ticker)
    ask = Exchange.ask_price(venue, ticker)
    prediction = simple_moving_avg(order_side_history)

    if :rand.uniform() < @mm_delta do
      for order <- outstanding, do: Exchange.cancel_order(venue, ticker, order)
      {cost, orders} = market_maker_place_order(venue, ticker, tid, ask, bid, prediction)
      cash = max(cash - cost, 0.0) |> Float.round(2)
      %{trader | cash: cash, outstanding_orders: orders}
    else
      trader
    end
  end

  defp market_maker_place_order(venue, ticker, tid, ask_price, bid_price, prediction) do
    if prediction < 0.5 do
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
    cost = ask_price * vol + bid_price * @mm_vol
    {cost, orders}
  end

  defp market_maker_place_order(venue, ticker, tid, ask_price, bid_price, _prediction, :gt) do
    vol = :rand.uniform(@mm_max_vol)
    order1 = Exchange.buy_limit_order(venue, ticker, tid, bid_price, vol)
    order2 = Exchange.sell_limit_order(venue, ticker, tid, ask_price, @mm_vol)
    orders = Enum.reject([order1, order2], fn order -> order == :rejected end)
    cost = ask_price * @mm_vol + bid_price * vol
    {cost, orders}
  end

  defp simple_moving_avg(items) when is_list(items) do
    sum = Enum.reduce(items, 0, fn x, acc -> x + acc end)
    sum / length(items)
  end

  defp update_order_side_history(
         %OrderbookEvent{direction: side},
         %{order_side_history: order_side_history} = state
       ) do
    order_side_history = order_side_history(side, order_side_history)
    %{state | order_side_history: order_side_history}
  end

  defp order_side_history(side, order_side_history) do
    if length(order_side_history) < @mm_w do
      [side | order_side_history]
    else
      [side | Enum.drop(order_side_history, -1)]
    end
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :market_maker,
      cash: 20_000_000.0,
      outstanding_orders: []
    }
  end
end
