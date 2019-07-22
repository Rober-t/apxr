defmodule APXR.MeanReversionTrader do
  @moduledoc """
  Mean reversion traders believe that asset prices tend to revert towards their
  historical average (though this may be a very short term average). They
  attempt to generate profit by taking long positions when the market price
  is below the historical average price, and short positions when it is above.
  Specifically, we define agents that, when chosen to trade, compare the
  current price to an exponential moving average of the asset price
  """

  @behaviour APXR.Trader

  use GenServer

  alias APXR.{
    Exchange,
    OrderbookEvent,
    Trader
  }

  @tick_size Exchange.tick_size(:apxr, :apxr)

  @mrt_delta 0.4
  @mrt_vol 1
  @mrt_k 1
  @mrt_a 0.94

  ## Client API

  @doc """
  Starts a MeanReversionTrader trader.
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
    last_price = Exchange.last_price(:apxr, :apxr)
    {:ok, %{n: 0, std_dev: 0.0, ema: last_price, trader: trader}}
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
    state = update_stats(price, state)
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

  defp action(
         %{ema: ema, std_dev: std_dev, trader: %Trader{trader_id: tid, cash: cash} = trader} =
           state
       ) do
    venue = :apxr
    ticker = :apxr
    bid_price = Exchange.bid_price(venue, ticker)
    ask_price = Exchange.ask_price(venue, ticker)
    price = Exchange.last_price(venue, ticker)

    if :rand.uniform() < @mrt_delta do
      cost = place_order(venue, ticker, tid, ask_price, bid_price, price, ema, std_dev)
      cash = max(cash - cost, 0.0) |> Float.round(2)
      trader = %{trader | cash: cash}
      %{state | trader: trader}
    else
      state
    end
  end

  defp place_order(venue, ticker, tid, ask_price, bid_price, p, ema, std_dev) do
    cond do
      p - ema >= @mrt_k * std_dev ->
        price = ask_price - @tick_size
        Exchange.sell_limit_order(venue, ticker, tid, price, @mrt_vol)
        price * @mrt_vol

      ema - p >= @mrt_k * std_dev ->
        price = bid_price + @tick_size
        Exchange.buy_limit_order(venue, ticker, tid, price, @mrt_vol)
        price * @mrt_vol

      true ->
        0.0
    end
  end

  defp update_stats(price, %{n: n, m: m, s: s, ema: ema} = state) do
    {n1, m1, s1} = running_stat(n, price, m, s)
    std_dev = std_dev(n, s)
    ema = ema + @mrt_a * (price - ema)
    %{state | n: n1, m: m1, s: s1, std_dev: std_dev, ema: ema}
  end

  defp running_stat(n, x, prev_m, prev_s) do
    n1 = n + 1

    if n1 == 1 do
      {n1, x, 0}
    else
      m = prev_m + (x - prev_m) / n
      s = prev_s + (x - prev_m) * (x - m)
      {n1, m, s}
    end
  end

  defp std_dev(n, s) do
    var(n, s) |> :math.sqrt()
  end

  defp var(n, s) do
    if n > 1 do
      abs(s / (n - 1))
    else
      0.0
    end
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :mean_reversion_trader,
      cash: 20_000_000.0,
      outstanding_orders: []
    }
  end
end
