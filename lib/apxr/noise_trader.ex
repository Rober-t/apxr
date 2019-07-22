defmodule APXR.NoiseTrader do
  @moduledoc """
  Noise traders defined so as to capture all other market activity. The noise
  traders are randomly assigned whether to submit a buy or sell order in each
  period with equal probability. Once assigned, they then randomly place either
  a market or limit order or cancel an existing order. To prevent spurious
  price processes, noise traders market orders are limited in volume such that
  they cannot consume more than half of the total opposing side’s available
  volume. Another restriction is that noise traders will make sure that no side
  of the order book is empty and place limit orders appropriately. 
  """

  @behaviour APXR.Trader

  use GenServer

  alias APXR.{
    Exchange,
    Order,
    Trader
  }

  @tick_size Exchange.tick_size(:apxr, :apxr)

  @default_spread 0.05
  @default_price 100

  @nt_delta 0.75
  @nt_m 0.03
  @nt_l 0.54
  @nt_mu_mo 7
  @nt_mu_lo 8
  @nt_sigma_mo 0.1
  @nt_sigma_lo 0.7
  @nt_crs 0.003
  @nt_inspr 0.098
  @nt_spr 0.173
  @nt_xmin 0.005
  @nt_beta 2.72

  ## Client API

  @doc """
  Starts a NoiseTrader trader.
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
    trader = init_trader(id)
    {:ok, %{trader: trader}}
  end

  @impl true
  def handle_call({:actuate}, _from, state) do
    state = action(state)
    {:reply, :ok, state}
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

  defp action(
         %{trader: %Trader{trader_id: tid, cash: cash, outstanding_orders: outstanding} = trader} =
           state
       ) do
    venue = :apxr
    ticker = :apxr
    type = order_side()
    bid_price = Exchange.bid_price(venue, ticker)
    ask_price = Exchange.ask_price(venue, ticker)
    spread = max(ask_price - bid_price, @tick_size)
    off_sprd_amnt = off_sprd_amnt(@nt_xmin, @nt_beta) + spread
    in_spr_price = Enum.random(round(bid_price * 100)..round(ask_price * 100)) / 100

    if Exchange.highest_bid_prices(venue, ticker) == [] or
         Exchange.lowest_ask_prices(venue, ticker) == [] do
      {cost, orders} = populate_orderbook(venue, ticker, tid, bid_price, ask_price)
      cash = max(cash - cost, 0.0) |> Float.round(2)
      orders = Enum.reject(orders, fn order -> order == :rejected end)
      trader = %{trader | cash: cash, outstanding_orders: outstanding ++ orders}
      %{state | trader: trader}
    else
      if :rand.uniform() < @nt_delta do
        case :rand.uniform() do
          action when action < @nt_m ->
            cost = market_order(venue, ticker, type, tid)
            cash = max(cash - cost, 0.0) |> Float.round(2)
            trader = %{trader | cash: cash}
            %{state | trader: trader}

          action when action < @nt_m + @nt_l ->
            {cost, orders} =
              case :rand.uniform() do
                lo when lo < @nt_crs ->
                  limit_order(type, venue, ticker, tid, ask_price, bid_price)

                lo when lo < @nt_crs + @nt_inspr ->
                  limit_order(type, venue, ticker, tid, in_spr_price, in_spr_price)

                lo when lo < @nt_crs + @nt_inspr + @nt_spr ->
                  limit_order(type, venue, ticker, tid, bid_price, ask_price)

                _ ->
                  limit_order(type, venue, ticker, tid, bid_price, ask_price, off_sprd_amnt)
              end

            cash = max(cash - cost, 0.0) |> Float.round(2)
            orders = Enum.reject(orders, fn order -> order == :rejected end)
            trader = %{trader | cash: cash, outstanding_orders: outstanding ++ orders}
            %{state | trader: trader}

          _ ->
            outstanding = maybe_cancel_order(venue, ticker, outstanding)
            trader = %{trader | outstanding_orders: outstanding}
            %{state | trader: trader}
        end
      else
        state
      end
    end
  end

  defp maybe_cancel_order(venue, ticker, orders) when is_list(orders) and length(orders) > 0 do
    {orders, [order]} = Enum.split(orders, -1)
    Exchange.cancel_order(venue, ticker, order)
    orders
  end

  defp maybe_cancel_order(_venue, _ticker, orders) do
    orders
  end

  defp market_order(venue, ticker, :buy, tid) do
    vol =
      min(
        Enum.sum(Exchange.lowest_ask_prices(venue, ticker)),
        :math.exp(@nt_mu_mo + @nt_sigma_mo * :rand.uniform())
      )

    Exchange.buy_market_order(venue, ticker, tid, vol)
    vol * Exchange.ask_price(venue, ticker)
  end

  defp market_order(venue, ticker, :sell, tid) do
    vol =
      min(
        Enum.sum(Exchange.highest_bid_prices(venue, ticker)),
        :math.exp(@nt_mu_mo + @nt_sigma_mo * :rand.uniform())
      )

    Exchange.sell_market_order(venue, ticker, tid, vol)
    vol * Exchange.bid_price(venue, ticker)
  end

  defp limit_order(:buy, venue, ticker, tid, price1, _price2) do
    vol = limit_order_vol()
    order = Exchange.buy_limit_order(venue, ticker, tid, price1, vol)
    cost = vol * price1
    {cost, [order]}
  end

  defp limit_order(:sell, venue, ticker, tid, _price1, price2) do
    vol = limit_order_vol()
    order = Exchange.sell_limit_order(venue, ticker, tid, price2, vol)
    cost = vol * price2
    {cost, [order]}
  end

  defp limit_order(:buy, venue, ticker, tid, bid_price, _ask_price, off_sprd_amnt) do
    vol = limit_order_vol()
    price = bid_price + off_sprd_amnt
    order = Exchange.buy_limit_order(venue, ticker, tid, price, vol)
    cost = vol * price
    {cost, [order]}
  end

  defp limit_order(:sell, venue, ticker, tid, _bid_price, ask_price, off_sprd_amnt) do
    vol = limit_order_vol()
    price = ask_price - off_sprd_amnt
    order = Exchange.sell_limit_order(venue, ticker, tid, price, vol)
    cost = vol * price
    {cost, [order]}
  end

  defp limit_order_vol() do
    :math.exp(@nt_mu_lo + @nt_sigma_lo * :rand.uniform()) |> round()
  end

  defp off_sprd_amnt(xmin, beta) do
    pow = 1 / (beta - 1) * -1
    num = 1 - :rand.uniform()
    xmin * :math.pow(num, pow)
  end

  defp order_side do
    if :rand.uniform() < 0.5 do
      :buy
    else
      :sell
    end
  end

  defp populate_orderbook(venue, ticker, tid, bid_price, ask_price) do
    cond do
      Exchange.highest_bid_prices(venue, ticker) == [] and
          Exchange.lowest_ask_prices(venue, ticker) == [] ->
        limit_order(:buy, venue, ticker, tid, @default_price, @default_price)
        limit_order(:sell, venue, ticker, tid, @default_price, @default_price + @default_spread)

      Exchange.highest_bid_prices(venue, ticker) == [] ->
        limit_order(:buy, venue, ticker, tid, ask_price - @default_spread, @default_price)

      Exchange.lowest_ask_prices(venue, ticker) == [] ->
        limit_order(:sell, venue, ticker, tid, @default_price, bid_price + @default_spread)

      true ->
        :ok
    end
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :noise_trader,
      cash: 20_000_000.0,
      outstanding_orders: []
    }
  end
end
