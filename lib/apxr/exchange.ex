defmodule APXR.Exchange do
  @moduledoc """
  Limit-order-book and order matching engine.
  Order matching is the process of accepting buy and sell orders for a
  security (or other fungible asset) and matching them to allow trading
  between parties who are otherwise unknown to each other.
  A LOB is the set of all limit orders for a given asset on a given
  platform at time t.
  A LOB can be though of as a pair of queues, each of which consists of a
  set of buy or sell limit orders at a specified price.
  Several different limit orders can reside at the same price at the
  same time. LOBs employ a priority system within each individual price level.
  Price-time priority: for buy/sell limit orders, priority is given to
  the limit orders with the highest/lowest price, and ties are broken by
  selecting the limit order with the earliest submission time t.
  The actions of traders in an LOB can be expressed solely in terms of
  the submission or cancellation of orders.
  Two orders are matched when they have a “compatible price”
  (i.e. a buy order will match any existing cheaper sell order,
  a sell order will match any existing more expensive buy order).
  Each matching generates a transaction, giving birth to three messages:
  one (public) trade, and two private trades (one to be reported to each owner
  of the matched orders).
  Members of the trading facility are connected to the server via two channels,
  one private channel allowing them to send (and receive) messages to the
  server and one public channel:
  - The private connection: the trader will send specific orders to the
    matching engine and receive answers and messages concerning his orders.
  - The public channel, he/she will see (like everyone connected to this
    public feed) the transactions and the state of the orderbook. 
  """

  use GenServer

  alias APXR.{
    Order,
    OrderbookEvent,
    ReportingService
  }

  alias Decimal, as: D

  @tick_size 0.01

  ## Client API

  @doc """
  Starts the exchange.
  """
  def start_link([venue, ticker, init_price, init_vol]) do
    name = via_tuple({venue, ticker})
    GenServer.start_link(__MODULE__, [venue, ticker, init_price, init_vol], name: name)
  end

  @doc ~S"""
  The tick size.

  ## Examples

      iex> APXR.Exchange.tick_size(:apxr, :apxr)
      #Decimal<0.01>

  """
  def tick_size(_venue, _ticker) do
    D.from_float(@tick_size)
  end

  @doc ~S"""
  Level 1 market data.
  The mid_price.

  ## Examples

      iex> APXR.Exchange.mid_price(:apxr, :apxr)
      "100.00"

  """
  def mid_price(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:mid_price})
  end

  @doc ~S"""
  Level 1 market data.
  The highest posted price someone is willing to buy the asset at.

  ## Examples

      iex> APXR.Exchange.bid_price(:apxr, :apxr)
      "99.99"

  """
  def bid_price(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:bid_price})
  end

  @doc ~S"""
  Level 1 market data.
  The volume that people are trying to buy at the bid price.

  ## Examples

      iex> APXR.Exchange.bid_size(:apxr, :apxr)
      100

  """
  def bid_size(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:bid_size})
  end

  @doc ~S"""
  Level 1 market data.
  The lowest posted price someone is willing to sell the asset at.

  ## Examples

      iex> APXR.Exchange.ask_price(:apxr, :apxr)
      "100.01"

  """
  def ask_price(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:ask_price})
  end

  @doc ~S"""
  Level 1 market data.
  The volume being sold at the ask price.

  ## Examples

      iex> APXR.Exchange.ask_size(:apxr, :apxr)
      100

  """
  def ask_size(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:ask_size})
  end

  @doc ~S"""
  Level 1 market data.
  Returns the price at which the last transaction occurred.

  ## Examples

      #iex> APXR.Exchange.last_price(:apxr, :apxr)
      #"75.0"

  """
  def last_price(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:last_price})
  end

  @doc ~S"""
  Level 1 market data.
  Returns the number of shares, etc. involved in the last transaction.

  ## Examples

      iex> APXR.Exchange.last_size(:apxr, :apxr)
      100

  """
  def last_size(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:last_size})
  end

  @doc ~S"""
  Level 2 market data.
  Returns (up to) the highest 15 prices where traders are willing to buy an asset,
  and have placed an order to do so.

  ## Examples

      iex> APXR.Exchange.highest_bid_prices(:apxr, :apxr)
      ["99.99"]

  """
  def highest_bid_prices(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:highest_bid_prices})
  end

  @doc ~S"""
  Level 2 market data.
  Returns the volume that people are trying to buy at each of the
  highest (up to) 15 prices where traders are willing to buy an asset,
  and have placed an order to do so.

  ## Examples

      iex> APXR.Exchange.highest_bid_sizes(:apxr, :apxr)
      [100]

  """
  def highest_bid_sizes(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:highest_bid_sizes})
  end

  @doc ~S"""
  Level 2 market data.
  Returns (up to) the lowest 15 prices where traders are willing to sell an asset,
  and have placed an order to do so.

  ## Examples

      iex> APXR.Exchange.lowest_ask_prices(:apxr, :apxr)
      ["100.01"]

  """
  def lowest_ask_prices(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:lowest_ask_prices})
  end

  @doc ~S"""
  Level 2 market data.
  Returns the volume that people are trying to sell at each of the
  lowest (up to) 15 prices where traders are willing to sell an asset,
  and have placed an order to do so.

  ## Examples

      iex> APXR.Exchange.lowest_ask_sizes(:apxr, :apxr)
      [100]

  """
  def lowest_ask_sizes(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:lowest_ask_sizes})
  end

  @doc """
  Create a buy market order.

  Returns `%Order{} | :rejected`.
  """
  def buy_market_order(_venue, _ticker, _trader, vol) when vol <= 0 do
    :rejected
  end

  def buy_market_order(venue, ticker, trader, vol) do
    GenServer.call(
      via_tuple({venue, ticker}),
      {:market_order, venue, ticker, trader, 0, vol},
      15000
    )
  end

  @doc """
  Create a sell market order.

  Returns `%Order{} | :rejected`.
  """
  def sell_market_order(_venue, _ticker, _trader, vol) when vol <= 0 do
    :rejected
  end

  def sell_market_order(venue, ticker, trader, vol) do
    GenServer.call(
      via_tuple({venue, ticker}),
      {:market_order, venue, ticker, trader, 1, vol},
      15000
    )
  end

  @doc """
  Create a buy limit order.

  Returns `%Order{} | :rejected`.  
  """
  def buy_limit_order(venue, ticker, trader, price, vol) do
    cond do
      normalize_price(price) <= 0.0 ->
        :rejected

      vol <= 0 ->
        :rejected

      true ->
        GenServer.call(
          via_tuple({venue, ticker}),
          {:limit_order, venue, ticker, trader, 0, price, vol},
          15000
        )
    end
  end

  @doc """
  Create a sell limit order.

  Returns `%Order{} | :rejected`.  
  """
  def sell_limit_order(venue, ticker, trader, price, vol) do
    cond do
      normalize_price(price) <= 0.0 ->
        :rejected

      vol <= 0 ->
        :rejected

      true ->
        GenServer.call(
          via_tuple({venue, ticker}),
          {:limit_order, venue, ticker, trader, 1, price, vol},
          15000
        )
    end
  end

  @doc """
  Cancel an order.

  Returns `:ok`.   
  """
  def cancel_order(venue, ticker, order) do
    GenServer.call(via_tuple({venue, ticker}), {:cancel_order, order}, 15000)
  end

  ## Server callbacks

  @impl true
  def init([venue, ticker, init_price, init_vol])
      when is_atom(venue) and is_atom(ticker) and is_float(init_price) and is_integer(init_vol) do
    :rand.seed(:exsplus)
    # Uncomment for a constant random seed
    # :rand.seed(:exsplus, {1, 2, 3})
    :ets.new(:bid_book, [:ordered_set, :named_table])
    :ets.new(:ask_book, [:ordered_set, :named_table])
    {:ok, %{venue: venue, ticker: ticker, last_price: init_price, last_size: init_vol}}
  end

  @impl true
  def handle_call({:bid_price}, _from, state) do
    bid_price = do_bid_price() |> D.from_float() |> D.to_string()
    {:reply, bid_price, state}
  end

  @impl true
  def handle_call({:bid_size}, _from, state) do
    bid_size = do_bid_size()
    {:reply, bid_size, state}
  end

  @impl true
  def handle_call({:ask_price}, _from, state) do
    ask_price = do_ask_price() |> D.from_float() |> D.to_string()
    {:reply, ask_price, state}
  end

  @impl true
  def handle_call({:ask_size}, _from, state) do
    ask_size = do_ask_size()
    {:reply, ask_size, state}
  end

  @impl true
  def handle_call({:last_price}, _from, %{last_price: last_price} = state) do
    last_price = last_price |> D.from_float() |> D.to_string()
    {:reply, last_price, state}
  end

  @impl true
  def handle_call({:last_size}, _from, %{last_size: last_size} = state) do
    {:reply, last_size, state}
  end

  @impl true
  def handle_call({:mid_price}, _from, state) do
    mid_price = do_mid_price() |> D.to_string()
    {:reply, mid_price, state}
  end

  @impl true
  def handle_call({:highest_bid_prices}, _from, state) do
    highest_bid_prices =
      for bid_price <- do_highest_bid_prices(), do: bid_price |> D.from_float() |> D.to_string()

    {:reply, highest_bid_prices, state}
  end

  @impl true
  def handle_call({:highest_bid_sizes}, _from, state) do
    highest_bid_sizes = do_highest_bid_sizes()
    {:reply, highest_bid_sizes, state}
  end

  @impl true
  def handle_call({:lowest_ask_prices}, _from, state) do
    lowest_ask_prices =
      for ask_price <- do_lowest_ask_prices(), do: ask_price |> D.from_float() |> D.to_string()

    {:reply, lowest_ask_prices, state}
  end

  @impl true
  def handle_call({:lowest_ask_sizes}, _from, state) do
    lowest_ask_sizes = do_lowest_ask_sizes()
    {:reply, lowest_ask_sizes, state}
  end

  @impl true
  def handle_call({:market_order, venue, ticker, trader, side, vol}, _from, state) do
    order = order(venue, ticker, trader, side, :undefined, vol)
    {state, order} = do_market_order(order, state)
    {:reply, order, state}
  end

  @impl true
  def handle_call({:limit_order, venue, ticker, trader, side, price, vol}, _from, state) do
    order = order(venue, ticker, trader, side, price, vol)
    {state, order} = do_limit_order(order, state)
    {:reply, order, state}
  end

  @impl true
  def handle_call({:cancel_order, order}, _from, state) do
    do_cancel_order(order)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private

  defp via_tuple(id) do
    {:via, Registry, {APXR.ExchangeRegistry, id}}
  end

  defp do_mid_price() do
    bid_price = do_bid_price() |> D.from_float()
    ask_price = do_ask_price() |> D.from_float()

    D.add(bid_price, ask_price) |> D.div(2) |> D.round(2, :half_down)
  end

  defp do_bid_price do
    case :ets.last(:bid_book) do
      :"$end_of_table" ->
        0.0

      bid_max ->
        bid_max
    end
  end

  defp do_bid_size do
    case :ets.last(:bid_book) do
      :"$end_of_table" ->
        0

      bid_max ->
        [{^bid_max, bid_tree}] = :ets.lookup(:bid_book, bid_max)

        vol = for {_id, order} <- :gb_trees.to_list(bid_tree), order != :empty, do: order.volume
        Enum.sum(vol)
    end
  end

  defp do_ask_price do
    case :ets.first(:ask_book) do
      :"$end_of_table" ->
        0.0

      ask_min ->
        ask_min
    end
  end

  defp do_ask_size do
    case :ets.first(:ask_book) do
      :"$end_of_table" ->
        0

      ask_min ->
        [{^ask_min, ask_tree}] = :ets.lookup(:ask_book, ask_min)

        vol = for {_id, order} <- :gb_trees.to_list(ask_tree), order != :empty, do: order.volume
        Enum.sum(vol)
    end
  end

  defp do_highest_bid_prices do
    case :ets.last(:bid_book) do
      :"$end_of_table" ->
        []

      bid_max ->
        get_highest_bid_prices(bid_max, 1, [])
    end
  end

  defp do_highest_bid_sizes do
    case :ets.last(:bid_book) do
      :"$end_of_table" ->
        0

      bid_max ->
        get_highest_bid_sizes(bid_max, 1, [])
    end
  end

  defp do_lowest_ask_prices do
    case :ets.first(:ask_book) do
      :"$end_of_table" ->
        []

      ask_min ->
        get_lowest_ask_prices(ask_min, 1, [])
    end
  end

  defp do_lowest_ask_sizes do
    case :ets.first(:ask_book) do
      :"$end_of_table" ->
        0

      ask_min ->
        get_lowest_ask_sizes(ask_min, 1, [])
    end
  end

  defp get_highest_bid_prices(:"$end_of_table", _i, acc) do
    acc
  end

  defp get_highest_bid_prices(_price, 15, acc) do
    acc
  end

  defp get_highest_bid_prices(price, i, acc) do
    :ets.prev(:bid_book, price)
    |> get_highest_bid_prices(i + 1, [price | acc])
  end

  defp get_highest_bid_sizes(:"$end_of_table", _i, acc) do
    acc
  end

  defp get_highest_bid_sizes(_price, 15, acc) do
    acc
  end

  defp get_highest_bid_sizes(price, i, acc) do
    previous = :ets.prev(:bid_book, price)
    [{^price, bid_tree}] = :ets.lookup(:bid_book, price)
    vol = for {_id, order} <- :gb_trees.to_list(bid_tree), order != :empty, do: order.volume
    vol = Enum.sum(vol)
    get_highest_bid_sizes(previous, i + 1, [vol | acc])
  end

  defp get_lowest_ask_prices(:"$end_of_table", _i, acc) do
    acc
  end

  defp get_lowest_ask_prices(_price, 15, acc) do
    acc
  end

  defp get_lowest_ask_prices(price, i, acc) do
    :ets.next(:ask_book, price)
    |> get_lowest_ask_prices(i + 1, [price | acc])
  end

  defp get_lowest_ask_sizes(:"$end_of_table", _i, acc) do
    acc
  end

  defp get_lowest_ask_sizes(_price, 15, acc) do
    acc
  end

  defp get_lowest_ask_sizes(price, i, acc) do
    next = :ets.next(:ask_book, price)
    [{^price, ask_tree}] = :ets.lookup(:ask_book, price)
    vol = for {_id, order} <- :gb_trees.to_list(ask_tree), order != :empty, do: order.volume
    vol = Enum.sum(vol)
    get_lowest_ask_sizes(next, i + 1, [vol | acc])
  end

  defp order(venue, ticker, trader, side, price, vol) do
    %Order{
      venue: venue,
      ticker: ticker,
      trader_id: trader,
      side: side,
      price: normalize_price(price),
      volume: normalize_volume(vol),
      acknowledged_at: set_acknowledged_at(),
      order_id: generate_id()
    }
  end

  defp do_market_order(%Order{} = order, state) do
    log_orderbook_event(order, :new_market_order)
    price_time_match(order, state, :market_order)
  end

  defp do_limit_order(%Order{} = order, state) do
    log_orderbook_event(order, :new_limit_order)
    price_time_match(order, state, :limit_order)
  end

  defp do_cancel_order(
         %Order{order_id: order_id, price: price, side: 0, trader_id: {trader, tid}} = order
       ) do
    log_orderbook_event(order, :cancel_limit_order)

    bid_tree(price)
    |> remove_order_from_tree(order_id)
    |> update_bid_book(price)

    trader.execution_report({trader, tid}, order, :cancelled_order)
  end

  defp do_cancel_order(
         %Order{order_id: order_id, price: price, side: 1, trader_id: {trader, tid}} = order
       ) do
    log_orderbook_event(order, :cancel_limit_order)

    ask_tree(price)
    |> remove_order_from_tree(order_id)
    |> update_ask_book(price)

    trader.execution_report({trader, tid}, order, :cancelled_order)
  end

  defp price_time_match(%Order{side: 0, volume: vol} = order, state, :market_order) do
    ask_min = do_ask_price()
    ask_tree = ask_tree(ask_min)

    case :gb_trees.smallest(ask_tree) do
      {:empty, :empty} ->
        {state, order}

      {_key, %Order{volume: matched_vol} = matched_order} ->
        order = %{order | price: ask_min}

        buy_side_match(
          matched_vol,
          matched_order,
          vol,
          ask_tree,
          state,
          ask_min,
          order,
          :market_order
        )
    end
  end

  defp price_time_match(%Order{side: 1, volume: vol} = order, state, :market_order) do
    bid_max = do_bid_price()
    bid_tree = bid_tree(bid_max)

    case :gb_trees.smallest(bid_tree) do
      {:empty, :empty} ->
        {state, order}

      {_value, %Order{volume: matched_vol} = matched_order} ->
        order = %{order | price: bid_max}

        sell_side_match(
          matched_vol,
          matched_order,
          vol,
          bid_tree,
          state,
          bid_max,
          order,
          :market_order
        )
    end
  end

  defp price_time_match(%Order{side: 0, price: price, volume: vol} = order, state, :limit_order) do
    ask_min = do_ask_price()

    cond do
      price >= ask_min ->
        ask_tree = ask_tree(ask_min)

        case :gb_trees.smallest(ask_tree) do
          {:empty, :empty} ->
            try_next_price_point(order, ask_min, state)

          {_key, %Order{volume: matched_vol} = matched_order} ->
            buy_side_match(
              matched_vol,
              matched_order,
              vol,
              ask_tree,
              state,
              ask_min,
              order,
              :limit_order
            )
        end

      true ->
        insert_order_into_tree(order)
        {state, order}
    end
  end

  defp price_time_match(%Order{side: 1, price: price, volume: vol} = order, state, :limit_order) do
    bid_max = do_bid_price()

    cond do
      price <= bid_max ->
        bid_tree = bid_tree(bid_max)

        case :gb_trees.smallest(bid_tree) do
          {:empty, :empty} ->
            try_next_price_point(order, bid_max, state)

          {_value, %Order{volume: matched_vol} = matched_order} ->
            sell_side_match(
              matched_vol,
              matched_order,
              vol,
              bid_tree,
              state,
              bid_max,
              order,
              :limit_order
            )
        end

      true ->
        insert_order_into_tree(order)
        {state, order}
    end
  end

  defp try_next_price_point(%Order{side: 0} = order, bid_max, state) do
    case :ets.prev(:bid_book, bid_max) do
      :"$end_of_table" ->
        insert_order_into_tree(order)
        {state, order}

      next_price ->
        price_time_match(order, next_price, :limit_order)
    end
  end

  defp try_next_price_point(%Order{side: 1} = order, ask_min, state) do
    case :ets.next(:ask_book, ask_min) do
      :"$end_of_table" ->
        insert_order_into_tree(order)
        {state, order}

      next_price ->
        price_time_match(order, next_price, :limit_order)
    end
  end

  defp buy_side_match(
         matched_vol,
         _matched_order,
         order_vol,
         ask_tree,
         state,
         ask_min,
         order,
         order_type
       )
       when matched_vol == order_vol do
    {_key, popped_order, ask_tree} = :gb_trees.take_smallest(ask_tree)
    update_ask_book(ask_tree, ask_min)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        run_index(),
        order.order_id,
        ask_min,
        do_ask_price(),
        order_vol
      )
    end

    post_process_buy_order_match(order, popped_order)
    state = %{state | last_price: ask_min, last_size: matched_vol}
    {state, order}
  end

  defp buy_side_match(
         matched_vol,
         matched_order,
         order_vol,
         ask_tree,
         state,
         ask_min,
         order,
         order_type
       )
       when matched_vol < order_vol do
    post_process_buy_order_match(order, matched_order)
    {_key, _popped_order, ask_tree} = :gb_trees.take_smallest(ask_tree)
    update_ask_book(ask_tree, ask_min)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        run_index(),
        order.order_id,
        ask_min,
        do_ask_price(),
        order_vol
      )
    end

    order = %{order | volume: order_vol - matched_vol}
    state = %{state | last_price: ask_min, last_size: matched_vol}
    price_time_match(order, state, order_type)
  end

  defp buy_side_match(
         matched_vol,
         matched_order,
         order_vol,
         ask_tree,
         state,
         ask_min,
         order,
         order_type
       )
       when matched_vol > order_vol do
    post_process_buy_order_match(order, matched_order)
    {_key, popped_order, ask_tree} = :gb_trees.take_smallest(ask_tree)
    popped_order = %{popped_order | volume: matched_vol - order_vol}
    ask_tree = :gb_trees.enter(popped_order.order_id, popped_order, ask_tree)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        run_index(),
        order.order_id,
        ask_min,
        do_ask_price(),
        order_vol
      )
    end

    state = %{state | last_price: order.price, last_size: order_vol}
    :ets.insert(:ask_book, {ask_min, ask_tree})
    {state, order}
  end

  defp sell_side_match(
         matched_vol,
         _matched_order,
         order_vol,
         bid_tree,
         state,
         bid_max,
         order,
         order_type
       )
       when matched_vol == order_vol do
    {_key, popped_order, bid_tree} = :gb_trees.take_smallest(bid_tree)
    update_bid_book(bid_tree, bid_max)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        run_index(),
        order.order_id,
        bid_max,
        do_bid_price(),
        order_vol
      )
    end

    post_process_sell_order_match(order, popped_order)
    state = %{state | last_price: bid_max, last_size: matched_vol}
    {state, order}
  end

  defp sell_side_match(
         matched_vol,
         matched_order,
         order_vol,
         bid_tree,
         state,
         bid_max,
         order,
         order_type
       )
       when matched_vol < order_vol do
    post_process_sell_order_match(order, matched_order)
    {_key, _popped_order, bid_tree} = :gb_trees.take_smallest(bid_tree)
    update_bid_book(bid_tree, bid_max)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        run_index(),
        order.order_id,
        bid_max,
        do_bid_price(),
        order_vol
      )
    end

    order = %{order | volume: order_vol - matched_vol}
    state = %{state | last_price: bid_max, last_size: matched_vol}
    price_time_match(order, state, order_type)
  end

  defp sell_side_match(
         matched_vol,
         matched_order,
         order_vol,
         bid_tree,
         state,
         bid_max,
         order,
         order_type
       )
       when matched_vol > order_vol do
    post_process_sell_order_match(order, matched_order)
    {_key, popped_order, bid_tree} = :gb_trees.take_smallest(bid_tree)
    popped_order = %{popped_order | volume: matched_vol - order_vol}
    state = %{state | last_price: bid_max, last_size: order_vol}
    bid_tree = :gb_trees.enter(popped_order.order_id, popped_order, bid_tree)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        run_index(),
        order.order_id,
        bid_max,
        do_bid_price(),
        order_vol
      )
    end

    :ets.insert(:bid_book, {bid_max, bid_tree})
    {state, order}
  end

  defp post_process_buy_order_match(
         %Order{volume: vol, trader_id: {t1, tid1}} = order1,
         %Order{volume: matched_vol, price: price, trader_id: {t2, tid2}} = order2
       )
       when vol < matched_vol do
    t1.execution_report({t1, tid1}, order1, :full_fill_buy_order)
    t2.execution_report({t2, tid2}, order2, :partial_fill_buy_order)
    log_orderbook_event(order1, vol, price, :full_fill_buy_order, true)
  end

  defp post_process_buy_order_match(
         %Order{volume: vol, trader_id: {t1, tid1}} = order1,
         %Order{volume: matched_vol, price: price, trader_id: {t2, tid2}} = order2
       )
       when vol == matched_vol do
    t1.execution_report({t1, tid1}, order1, :full_fill_buy_order)
    t2.execution_report({t2, tid2}, order2, :full_fill_buy_order)
    log_orderbook_event(order1, vol, price, :full_fill_buy_order, true)
  end

  defp post_process_buy_order_match(
         %Order{volume: vol, trader_id: {t1, tid1}} = order1,
         %Order{volume: matched_vol, price: price, trader_id: {t2, tid2}} = order2
       )
       when vol > matched_vol do
    t1.execution_report({t1, tid1}, order1, :partial_fill_buy_order)
    t2.execution_report({t2, tid2}, order2, :full_fill_buy_order)
    log_orderbook_event(order1, matched_vol, price, :partial_fill_buy_order, true)
  end

  defp post_process_sell_order_match(
         %Order{volume: vol, trader_id: {t1, tid1}} = order1,
         %Order{volume: matched_vol, price: price, trader_id: {t2, tid2}} = order2
       )
       when vol < matched_vol do
    t1.execution_report({t1, tid1}, order1, :full_fill_sell_order)
    t2.execution_report({t2, tid2}, order2, :full_fill_sell_order)
    log_orderbook_event(order1, vol, price, :full_fill_sell_order, true)
  end

  defp post_process_sell_order_match(
         %Order{volume: vol, trader_id: {t1, tid1}} = order1,
         %Order{volume: matched_vol, price: price, trader_id: {t2, tid2}} = order2
       )
       when vol == matched_vol do
    t1.execution_report({t1, tid1}, order1, :full_fill_sell_order)
    t2.execution_report({t2, tid2}, order2, :full_fill_sell_order)
    log_orderbook_event(order1, vol, price, :full_fill_sell_order, true)
  end

  defp post_process_sell_order_match(
         %Order{volume: vol, trader_id: {t1, tid1}} = order1,
         %Order{volume: matched_vol, price: price, trader_id: {t2, tid2}} = order2
       )
       when vol > matched_vol do
    t1.execution_report({t1, tid1}, order1, :partial_fill_sell_order)
    t2.execution_report({t2, tid2}, order2, :full_fill_sell_order)
    log_orderbook_event(order1, matched_vol, price, :partial_fill_sell_order, true)
  end

  defp log_orderbook_event(%Order{} = order, type) do
    log_orderbook_event(order, order.volume, order.price, type, false)
  end

  defp log_orderbook_event(
         %Order{
           order_id: order_id,
           trader_id: tid,
           side: direction
         },
         size,
         price,
         type,
         transaction
       )
       when is_atom(type) and is_boolean(transaction) do
    event = %OrderbookEvent{
      run_index: run_index(),
      uid: generate_id(),
      order_id: order_id,
      trader_id: tid,
      type: type,
      volume: size,
      price: price,
      direction: direction,
      transaction: transaction
    }

    ReportingService.push_event(event)
  end

  defp run_index() do
    [{:iteration, index}] = :ets.lookup(:run_index, :iteration)
    index
  end

  defp bid_tree(bid_max) do
    case :ets.lookup(:bid_book, bid_max) do
      [{^bid_max, tree}] ->
        tree

      [] ->
        tree = :gb_trees.empty()
        :gb_trees.insert(:empty, :empty, tree)
    end
  end

  defp ask_tree(ask_min) do
    case :ets.lookup(:ask_book, ask_min) do
      [{^ask_min, tree}] ->
        tree

      [] ->
        tree = :gb_trees.empty()
        :gb_trees.insert(:empty, :empty, tree)
    end
  end

  defp insert_order_into_tree(%Order{side: 0, order_id: order_id, price: price} = order) do
    tree = bid_tree(price) |> tree_insert_order(order_id, order)
    :ets.insert(:bid_book, {price, tree})
  end

  defp insert_order_into_tree(%Order{side: 1, order_id: order_id, price: price} = order) do
    tree = ask_tree(price) |> tree_insert_order(order_id, order)
    :ets.insert(:ask_book, {price, tree})
  end

  defp tree_insert_order(tree, order_id, order) do
    :gb_trees.insert(order_id, order, tree)
  end

  defp remove_order_from_tree(tree, order_id) do
    :gb_trees.delete(order_id, tree)
  rescue
    FunctionClauseError ->
      tree
  end

  defp update_bid_book(tree, price) do
    case :gb_trees.smallest(tree) do
      {:empty, :empty} ->
        :ets.delete(:bid_book, price)

      _ ->
        :ets.insert(:bid_book, {price, tree})
    end
  end

  defp update_ask_book(tree, price) do
    case :gb_trees.smallest(tree) do
      {:empty, :empty} ->
        :ets.delete(:ask_book, price)

      _ ->
        :ets.insert(:ask_book, {price, tree})
    end
  end

  defp normalize_price(:undefined) do
    nil
  end

  defp normalize_price(price) do
    D.cast(price) |> D.round(2, :half_down) |> D.to_float()
  end

  def normalize_volume(volume) when is_integer(volume) do
    volume
  end

  defp set_acknowledged_at do
    :erlang.monotonic_time(:nanosecond)
  end

  defp generate_id do
    :erlang.unique_integer([:positive, :monotonic])
  end
end
