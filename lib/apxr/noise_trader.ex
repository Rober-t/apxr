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
    :rand.seed(:exsplus)
    trader = init_trader(id)
    {:ok, %{trader: trader}}
  end

  @impl true
  def handle_call({:actuate}, _from, state) do
    trader = noise_trader(state)
    {:reply, :ok, %{state | trader: trader}}
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

  defp nt_l do
    @nt_m + @nt_l
  end

  defp nt_crs do
    @nt_crs
  end

  defp nt_inspr do
    @nt_crs + @nt_inspr
  end

  defp nt_spr do
    @nt_crs + @nt_inspr + @nt_spr
  end

  defp noise_trader(%{
         trader:
           %Trader{trader_id: tid, cash: cash, outstanding_orders: outstanding_orders} = trader
       }) do
    venue = :apxr
    ticker = :apxr

    action = rand()
    lo = rand()

    type = order_side()

    bid_price = Exchange.bid_price(venue, ticker)
    ask_price = Exchange.ask_price(venue, ticker)

    spread = max(ask_price - bid_price, @tick_size)

    off_sprd_amnt = off_sprd_amnt(@nt_xmin, @nt_beta) + spread

    in_spr_price = Enum.random(round(bid_price * 100)..round(ask_price * 100)) / 100

    maybe_populate_orderbook(venue, ticker, tid, bid_price, ask_price)

    if rand() < @nt_delta do
      cond do
        action < @nt_m ->
          cost = noise_trader_market_order(venue, ticker, type, tid)
          cash = max(cash - cost, 0.0) |> Float.round(2)

          %{trader | cash: cash}

        action < nt_l() ->
          {cost, orders} =
            cond do
              lo < nt_crs() ->
                noise_trader_limit_order(type, venue, ticker, tid, ask_price, bid_price)

              lo < nt_inspr() ->
                noise_trader_limit_order(type, venue, ticker, tid, in_spr_price, in_spr_price)

              lo < nt_spr() ->
                noise_trader_limit_order(type, venue, ticker, tid, bid_price, ask_price)

              true ->
                noise_trader_limit_order(
                  type,
                  venue,
                  ticker,
                  tid,
                  bid_price,
                  ask_price,
                  off_sprd_amnt
                )
            end

          cash = max(cash - cost, 0.0) |> Float.round(2)
          orders = Enum.reject(orders, fn order -> order == :rejected end)

          %{trader | cash: cash, outstanding_orders: outstanding_orders ++ orders}

        true ->
          outstanding_orders = maybe_cancel_order(venue, ticker, outstanding_orders)

          %{trader | outstanding_orders: outstanding_orders}
      end
    else
      trader
    end
  end

  defp maybe_cancel_order(venue, ticker, outstanding_orders)
       when is_list(outstanding_orders) and length(outstanding_orders) > 0 do
    {orders, [order]} = Enum.split(outstanding_orders, -1)

    Exchange.cancel_order(venue, ticker, order)

    orders
  end

  defp maybe_cancel_order(_venue, _ticker, outstanding_orders) do
    outstanding_orders
  end

  defp noise_trader_market_order(venue, ticker, :buy, tid) do
    vol =
      min(
        Enum.sum(Exchange.lowest_ask_prices(venue, ticker)),
        :math.exp(@nt_mu_mo + @nt_sigma_mo * rand())
      )

    Exchange.buy_market_order(venue, ticker, tid, vol)

    vol * Exchange.ask_price(venue, ticker)
  end

  defp noise_trader_market_order(venue, ticker, :sell, tid) do
    vol =
      min(
        Enum.sum(Exchange.highest_bid_prices(venue, ticker)),
        :math.exp(@nt_mu_mo + @nt_sigma_mo * rand())
      )

    Exchange.sell_market_order(venue, ticker, tid, vol)

    vol * Exchange.bid_price(venue, ticker)
  end

  defp noise_trader_limit_order(:buy, venue, ticker, tid, price1, _price2) do
    vol = :math.exp(@nt_mu_lo + @nt_sigma_lo * rand()) |> round()

    order = Exchange.buy_limit_order(venue, ticker, tid, price1, vol)
    cost = vol * price1

    {cost, [order]}
  end

  defp noise_trader_limit_order(:sell, venue, ticker, tid, _price1, price2) do
    vol = :math.exp(@nt_mu_lo + @nt_sigma_lo * rand()) |> round()

    order = Exchange.sell_limit_order(venue, ticker, tid, price2, vol)
    cost = vol * price2

    {cost, [order]}
  end

  defp noise_trader_limit_order(:buy, venue, ticker, tid, bid_price, _ask_price, off_sprd_amnt) do
    vol = :math.exp(@nt_mu_lo + @nt_sigma_lo * rand()) |> round()

    price = bid_price - off_sprd_amnt
    order = Exchange.buy_limit_order(venue, ticker, tid, price, vol)

    cost = vol * price

    {cost, [order]}
  end

  defp noise_trader_limit_order(:sell, venue, ticker, tid, _bid_price, ask_price, off_sprd_amnt) do
    vol = :math.exp(@nt_mu_lo + @nt_sigma_lo * rand()) |> round()

    price = ask_price + off_sprd_amnt
    order = Exchange.sell_limit_order(venue, ticker, tid, price, vol)

    cost = vol * price

    {cost, [order]}
  end

  defp off_sprd_amnt(xmin, beta) do
    u = :rand.uniform()

    pow = 1 / (beta - 1) * -1
    num = 1 - u

    xmin * :math.pow(num, pow)
  end

  defp order_side do
    if rand() < 0.5 do
      :buy
    else
      :sell
    end
  end

  defp maybe_populate_orderbook(venue, ticker, tid, bid_price, ask_price) do
    cond do
      Exchange.highest_bid_prices(venue, ticker) == [] and
          Exchange.lowest_ask_prices(venue, ticker) == [] ->
        noise_trader_limit_order(:buy, venue, ticker, tid, @default_price, @default_price)

        noise_trader_limit_order(
          :sell,
          venue,
          ticker,
          tid,
          @default_price,
          @default_price + @default_spread
        )

      Exchange.highest_bid_prices(venue, ticker) == [] ->
        noise_trader_limit_order(
          :buy,
          venue,
          ticker,
          tid,
          ask_price - @default_spread,
          @default_price
        )

      Exchange.lowest_ask_prices(venue, ticker) == [] ->
        noise_trader_limit_order(
          :sell,
          venue,
          ticker,
          tid,
          @default_price,
          bid_price + @default_spread
        )

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

  defp rand() do
    :rand.uniform()
  end
end
