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
      0.01

  """
  def tick_size(_venue, _ticker) do
    @tick_size
  end

  @doc ~S"""
  Level 1 market data.
  The mid_price.

  ## Examples

      iex> APXR.Exchange.mid_price(:apxr, :apxr)
      100.00

  """
  def mid_price(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:mid_price}, 25000)
  end

  @doc ~S"""
  Level 1 market data.
  The highest posted price someone is willing to buy the asset at.

  ## Examples

      iex> APXR.Exchange.bid_price(:apxr, :apxr)
      99.99

  """
  def bid_price(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:bid_price}, 25000)
  end

  @doc ~S"""
  Level 1 market data.
  The volume that people are trying to buy at the bid price.

  ## Examples

      iex> APXR.Exchange.bid_size(:apxr, :apxr)
      100

  """
  def bid_size(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:bid_size}, 25000)
  end

  @doc ~S"""
  Level 1 market data.
  The lowest posted price someone is willing to sell the asset at.

  ## Examples

      iex> APXR.Exchange.ask_price(:apxr, :apxr)
      100.01

  """
  def ask_price(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:ask_price}, 25000)
  end

  @doc ~S"""
  Level 1 market data.
  The volume being sold at the ask price.

  ## Examples

      iex> APXR.Exchange.ask_size(:apxr, :apxr)
      100

  """
  def ask_size(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:ask_size}, 25000)
  end

  @doc ~S"""
  Level 1 market data.
  Returns the price at which the last transaction occurred.

  ## Examples

      #iex> APXR.Exchange.last_price(:apxr, :apxr)
      #"75.0"

  """
  def last_price(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:last_price}, 25000)
  end

  @doc ~S"""
  Level 1 market data.
  Returns the number of shares, etc. involved in the last transaction.

  ## Examples

      iex> APXR.Exchange.last_size(:apxr, :apxr)
      1

  """
  def last_size(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:last_size}, 25000)
  end

  @doc ~S"""
  Level 2 market data.
  Returns (up to) the highest 5 prices where traders are willing to buy an asset,
  and have placed an order to do so.

  ## Examples

      iex> APXR.Exchange.highest_bid_prices(:apxr, :apxr)
      [99.99]

  """
  def highest_bid_prices(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:highest_bid_prices}, 25000)
  end

  @doc ~S"""
  Level 2 market data.
  Returns the volume that people are trying to buy at each of the
  highest (up to) 5 prices where traders are willing to buy an asset,
  and have placed an order to do so.

  ## Examples

      iex> APXR.Exchange.highest_bid_sizes(:apxr, :apxr)
      [100]

  """
  def highest_bid_sizes(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:highest_bid_sizes}, 25000)
  end

  @doc ~S"""
  Level 2 market data.
  Returns (up to) the lowest 5 prices where traders are willing to sell an asset,
  and have placed an order to do so.

  ## Examples

      iex> APXR.Exchange.lowest_ask_prices(:apxr, :apxr)
      [100.01]

  """
  def lowest_ask_prices(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:lowest_ask_prices}, 25000)
  end

  @doc ~S"""
  Level 2 market data.
  Returns the volume that people are trying to sell at each of the
  lowest (up to) 5 prices where traders are willing to sell an asset,
  and have placed an order to do so.

  ## Examples

      iex> APXR.Exchange.lowest_ask_sizes(:apxr, :apxr)
      [100]

  """
  def lowest_ask_sizes(venue, ticker) do
    GenServer.call(via_tuple({venue, ticker}), {:lowest_ask_sizes}, 25000)
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
      25000
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
      25000
    )
  end

  @doc """
  Create a buy limit order.

  Returns `%Order{} | :rejected`.  
  """
  def buy_limit_order(venue, ticker, trader, price, vol) do
    cond do
      price <= 0.0 ->
        :rejected

      vol <= 0 ->
        :rejected

      true ->
        GenServer.call(
          via_tuple({venue, ticker}),
          {:limit_order, venue, ticker, trader, 0, price, vol},
          25000
        )
    end
  end

  @doc """
  Create a sell limit order.

  Returns `%Order{} | :rejected`.  
  """
  def sell_limit_order(venue, ticker, trader, price, vol) do
    cond do
      price <= 0.0 ->
        :rejected

      vol <= 0 ->
        :rejected

      true ->
        GenServer.call(
          via_tuple({venue, ticker}),
          {:limit_order, venue, ticker, trader, 1, price, vol},
          25000
        )
    end
  end

  @doc """
  Cancel an order.

  Returns `:ok`.   
  """
  def cancel_order(venue, ticker, order) do
    GenServer.call(via_tuple({venue, ticker}), {:cancel_order, order})
  end

  ## Server callbacks

  @impl true
  def init([venue, ticker, init_price, init_vol]) do
    {:ok,
     %{
       venue: venue,
       ticker: ticker,
       last_price: init_price,
       last_size: init_vol,
       bid_book: :gb_trees.empty(),
       ask_book: :gb_trees.empty()
     }}
  end

  @impl true
  def handle_call({:bid_price}, _from, %{bid_book: bid_book} = state) do
    bid_price = do_bid_price(bid_book)
    {:reply, bid_price, state}
  end

  @impl true
  def handle_call({:bid_size}, _from, %{bid_book: bid_book} = state) do
    bid_size = do_bid_size(bid_book)
    {:reply, bid_size, state}
  end

  @impl true
  def handle_call({:ask_price}, _from, %{ask_book: ask_book} = state) do
    ask_price = do_ask_price(ask_book)
    {:reply, ask_price, state}
  end

  @impl true
  def handle_call({:ask_size}, _from, %{ask_book: ask_book} = state) do
    ask_size = do_ask_size(ask_book)
    {:reply, ask_size, state}
  end

  @impl true
  def handle_call({:last_price}, _from, %{last_price: last_price} = state) do
    {:reply, last_price, state}
  end

  @impl true
  def handle_call({:last_size}, _from, %{last_size: last_size} = state) do
    {:reply, last_size, state}
  end

  @impl true
  def handle_call({:mid_price}, _from, %{bid_book: bid_book, ask_book: ask_book} = state) do
    mid_price = do_mid_price(bid_book, ask_book)
    {:reply, mid_price, state}
  end

  @impl true
  def handle_call({:highest_bid_prices}, _from, %{bid_book: bid_book} = state) do
    highest_bid_prices = do_highest_bid_prices(bid_book)
    {:reply, highest_bid_prices, state}
  end

  @impl true
  def handle_call({:highest_bid_sizes}, _from, %{bid_book: bid_book} = state) do
    highest_bid_sizes = do_highest_bid_sizes(bid_book)
    {:reply, highest_bid_sizes, state}
  end

  @impl true
  def handle_call({:lowest_ask_prices}, _from, %{ask_book: ask_book} = state) do
    lowest_ask_prices = do_lowest_ask_prices(ask_book)
    {:reply, lowest_ask_prices, state}
  end

  @impl true
  def handle_call({:lowest_ask_sizes}, _from, %{ask_book: ask_book} = state) do
    lowest_ask_sizes = do_lowest_ask_sizes(ask_book)
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
    state = do_cancel_order(order, state)
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

  defp do_mid_price(bid_book, ask_book) do
    bid_price = do_bid_price(bid_book)
    ask_price = do_ask_price(ask_book)
    ((bid_price + ask_price) / 2.0) |> Float.round(2)
  end

  defp do_bid_price(bid_book) do
    if :gb_trees.is_empty(bid_book) do
      0.0
    else
      {bid_max, _} = :gb_trees.largest(bid_book)
      bid_max
    end
  end

  defp do_bid_size(bid_book) do
    if :gb_trees.is_empty(bid_book) do
      0
    else
      {_bid_max, bid_tree} = :gb_trees.largest(bid_book)
      vol = for {_id, order} <- :gb_trees.to_list(bid_tree), do: order.volume
      Enum.sum(vol)
    end
  end

  defp do_ask_price(ask_book) do
    if :gb_trees.is_empty(ask_book) do
      0.0
    else
      {ask_min, _} = :gb_trees.smallest(ask_book)
      ask_min
    end
  end

  defp do_ask_size(ask_book) do
    if :gb_trees.is_empty(ask_book) do
      0
    else
      {_ask_min, ask_tree} = :gb_trees.smallest(ask_book)
      vol = for {_id, order} <- :gb_trees.to_list(ask_tree), do: order.volume
      Enum.sum(vol)
    end
  end

  defp do_highest_bid_prices(bid_book) do
    bid_book_list = :gb_trees.to_list(bid_book) |> Enum.reverse() |> Enum.slice(0, 5)
    for {price, _bid_tree} <- bid_book_list, do: price
  end

  defp do_highest_bid_sizes(bid_book) do
    bid_book_list = :gb_trees.to_list(bid_book) |> Enum.reverse() |> Enum.slice(0, 5)
    bid_tree_list = for {_price, bid_tree} <- bid_book_list, do: bid_tree

    for bid_tree <- bid_tree_list do
      vol = for {_id, order} <- :gb_trees.to_list(bid_tree), do: order.volume
      Enum.sum(vol)
    end
  end

  defp do_lowest_ask_prices(ask_book) do
    ask_book_list = :gb_trees.to_list(ask_book) |> Enum.slice(0, 5)
    for {price, _ask_tree} <- ask_book_list, do: price
  end

  defp do_lowest_ask_sizes(ask_book) do
    ask_book_list = :gb_trees.to_list(ask_book) |> Enum.slice(0, 5)
    ask_tree_list = for {_price, ask_tree} <- ask_book_list, do: ask_tree

    for ask_tree <- ask_tree_list do
      vol = for {_id, order} <- :gb_trees.to_list(ask_tree), do: order.volume
      Enum.sum(vol)
    end
  end

  defp order(venue, ticker, trader, side, price, vol) do
    %Order{
      venue: venue,
      ticker: ticker,
      trader_id: trader,
      side: side,
      price: normalize_price(price),
      volume: normalize_volume(vol),
      order_id: generate_id()
    }
  end

  defp do_market_order(%Order{order_id: order_id, side: side} = order, state) do
    log_orderbook_event(order, :new_market_order)
    ReportingService.push_order_side(timestep(), order_id, :market_order, side)
    price_time_match(order, state, :market_order)
  end

  defp do_limit_order(%Order{order_id: order_id, side: side} = order, state) do
    log_orderbook_event(order, :new_limit_order)
    ReportingService.push_order_side(timestep(), order_id, :limit_order, side)
    price_time_match(order, state, :limit_order)
  end

  defp do_cancel_order(
         %Order{order_id: order_id, price: price, side: 0, trader_id: {trader, tid}} = order,
         %{bid_book: bid_book} = state
       ) do
    log_orderbook_event(order, :cancel_limit_order)

    state =
      bid_tree(price, bid_book)
      |> remove_order_from_tree(order_id)
      |> update_bid_book(price, state)

    trader.execution_report({trader, tid}, order, :cancelled_order)
    state
  end

  defp do_cancel_order(
         %Order{order_id: order_id, price: price, side: 1, trader_id: {trader, tid}} = order,
         %{ask_book: ask_book} = state
       ) do
    log_orderbook_event(order, :cancel_limit_order)

    state =
      ask_tree(price, ask_book)
      |> remove_order_from_tree(order_id)
      |> update_ask_book(price, state)

    trader.execution_report({trader, tid}, order, :cancelled_order)
    state
  end

  defp price_time_match(
         %Order{side: 0, volume: vol} = order,
         %{ask_book: ask_book} = state,
         :market_order
       ) do
    ask_min = do_ask_price(ask_book)
    ask_tree = ask_tree(ask_min, ask_book)

    if :gb_trees.is_empty(ask_tree) do
      {state, order}
    else
      {_key, %Order{volume: matched_vol} = matched_order} = :gb_trees.smallest(ask_tree)
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

  defp price_time_match(
         %Order{side: 1, volume: vol} = order,
         %{bid_book: bid_book} = state,
         :market_order
       ) do
    bid_max = do_bid_price(bid_book)
    bid_tree = bid_tree(bid_max, bid_book)

    if :gb_trees.is_empty(bid_tree) do
      {state, order}
    else
      {_value, %Order{volume: matched_vol} = matched_order} = :gb_trees.smallest(bid_tree)
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

  defp price_time_match(
         %Order{side: 0, price: price, volume: vol} = order,
         %{ask_book: ask_book} = state,
         :limit_order
       ) do
    if :gb_trees.is_empty(ask_book) do
      state = insert_order_into_tree(order, state)
      {state, order}
    else
      {ask_min, _ask_tree} = :gb_trees.smallest(ask_book)

      if price >= ask_min do
        check_for_match(vol, state, ask_book, order)
      else
        state = insert_order_into_tree(order, state)
        {state, order}
      end
    end
  end

  defp price_time_match(
         %Order{side: 1, price: price, volume: vol} = order,
         %{bid_book: bid_book} = state,
         :limit_order
       ) do
    if :gb_trees.is_empty(bid_book) do
      state = insert_order_into_tree(order, state)
      {state, order}
    else
      {bid_max, _bid_tree} = :gb_trees.largest(bid_book)

      if price <= bid_max do
        check_for_match(vol, state, bid_book, order)
      else
        state = insert_order_into_tree(order, state)
        {state, order}
      end
    end
  end

  defp check_for_match(vol, state, ask_book, %Order{side: 0} = order) do
    if :gb_trees.is_empty(ask_book) do
      state = insert_order_into_tree(order, state)
      {state, order}
    else
      {ask_min, ask_tree, ask_book2} = :gb_trees.take_smallest(ask_book)

      if :gb_trees.is_empty(ask_tree) do
        check_for_match(vol, state, ask_book2, order)
      else
        {_key, %Order{volume: matched_vol} = matched_order} = :gb_trees.smallest(ask_tree)

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
    end
  end

  defp check_for_match(vol, state, bid_book, %Order{side: 1} = order) do
    if :gb_trees.is_empty(bid_book) do
      state = insert_order_into_tree(order, state)
      {state, order}
    else
      {bid_max, bid_tree, bid_book2} = :gb_trees.take_largest(bid_book)

      if :gb_trees.is_empty(bid_tree) do
        check_for_match(vol, state, bid_book2, order)
      else
        {_key, %Order{volume: matched_vol} = matched_order} = :gb_trees.smallest(bid_tree)

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
    end
  end

  defp buy_side_match(
         matched_vol,
         _matched_order,
         order_vol,
         ask_tree,
         %{bid_book: bid_book, ask_book: ask_book} = state,
         ask_min,
         order,
         order_type
       )
       when matched_vol == order_vol do
    {_key, popped_order, ask_tree} = :gb_trees.take_smallest(ask_tree)
    mid_price_before = do_mid_price(bid_book, ask_book)
    state = update_ask_book(ask_tree, ask_min, state)
    %{bid_book: bid_book, ask_book: ask_book} = state
    mid_price_after = do_mid_price(bid_book, ask_book)
    post_process_buy_order_match(order, popped_order)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        timestep(),
        order.order_id,
        :market_order,
        order_vol,
        mid_price_before,
        mid_price_after
      )
    end

    state = %{state | last_price: ask_min, last_size: matched_vol}
    {state, order}
  end

  defp buy_side_match(
         matched_vol,
         matched_order,
         order_vol,
         ask_tree,
         %{bid_book: bid_book, ask_book: ask_book} = state,
         ask_min,
         order,
         order_type
       )
       when matched_vol < order_vol do
    {_key, _popped_order, ask_tree} = :gb_trees.take_smallest(ask_tree)
    mid_price_before = do_mid_price(bid_book, ask_book)
    state = update_ask_book(ask_tree, ask_min, state)
    %{bid_book: bid_book, ask_book: ask_book} = state
    mid_price_after = do_mid_price(bid_book, ask_book)
    post_process_buy_order_match(order, matched_order)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        timestep(),
        order.order_id,
        :market_order,
        order_vol,
        mid_price_before,
        mid_price_after
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
         %{ask_book: ask_book} = state,
         ask_min,
         order,
         _order_type
       )
       when matched_vol > order_vol do
    {_key, popped_order, ask_tree} = :gb_trees.take_smallest(ask_tree)
    popped_order = %{popped_order | volume: matched_vol - order_vol}
    ask_tree = :gb_trees.enter(popped_order.order_id, popped_order, ask_tree)
    post_process_buy_order_match(order, matched_order)
    ask_book = :gb_trees.enter(ask_min, ask_tree, ask_book)
    state = %{state | last_price: ask_min, last_size: order_vol, ask_book: ask_book}
    {state, order}
  end

  defp sell_side_match(
         matched_vol,
         _matched_order,
         order_vol,
         bid_tree,
         %{bid_book: bid_book, ask_book: ask_book} = state,
         bid_max,
         order,
         order_type
       )
       when matched_vol == order_vol do
    {_key, popped_order, bid_tree} = :gb_trees.take_smallest(bid_tree)
    mid_price_before = do_mid_price(bid_book, ask_book)
    state = update_bid_book(bid_tree, bid_max, state)
    %{bid_book: bid_book, ask_book: ask_book} = state
    mid_price_after = do_mid_price(bid_book, ask_book)
    post_process_sell_order_match(order, popped_order)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        timestep(),
        order.order_id,
        :market_order,
        order_vol,
        mid_price_before,
        mid_price_after
      )
    end

    state = %{state | last_price: bid_max, last_size: matched_vol}
    {state, order}
  end

  defp sell_side_match(
         matched_vol,
         matched_order,
         order_vol,
         bid_tree,
         %{bid_book: bid_book, ask_book: ask_book} = state,
         bid_max,
         order,
         order_type
       )
       when matched_vol < order_vol do
    {_key, _popped_order, bid_tree} = :gb_trees.take_smallest(bid_tree)
    mid_price_before = do_mid_price(bid_book, ask_book)
    state = update_bid_book(bid_tree, bid_max, state)
    %{bid_book: bid_book, ask_book: ask_book} = state
    mid_price_after = do_mid_price(bid_book, ask_book)
    post_process_sell_order_match(order, matched_order)

    if order_type == :market_order do
      ReportingService.push_price_impact(
        timestep(),
        order.order_id,
        :market_order,
        order_vol,
        mid_price_before,
        mid_price_after
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
         %{bid_book: bid_book} = state,
         bid_max,
         order,
         _order_type
       )
       when matched_vol > order_vol do
    {_key, popped_order, bid_tree} = :gb_trees.take_smallest(bid_tree)
    popped_order = %{popped_order | volume: matched_vol - order_vol}
    bid_tree = :gb_trees.enter(popped_order.order_id, popped_order, bid_tree)
    post_process_sell_order_match(order, matched_order)
    bid_book = :gb_trees.enter(bid_max, bid_tree, bid_book)
    state = %{state | last_price: bid_max, last_size: order_vol, bid_book: bid_book}
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
         %Order{order_id: order_id, trader_id: tid, side: direction},
         size,
         price,
         type,
         transaction
       )
       when is_atom(type) and is_boolean(transaction) do
    event = %OrderbookEvent{
      timestep: timestep(),
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

  defp bid_tree(bid_max, bid_book) do
    case :gb_trees.lookup(bid_max, bid_book) do
      {:value, tree} ->
        tree

      :none ->
        :gb_trees.empty()
    end
  end

  defp ask_tree(ask_min, ask_book) do
    case :gb_trees.lookup(ask_min, ask_book) do
      {:value, tree} ->
        tree

      :none ->
        :gb_trees.empty()
    end
  end

  defp insert_order_into_tree(
         %Order{side: 0, order_id: order_id, price: price} = order,
         %{bid_book: bid_book} = state
       ) do
    tree = bid_tree(price, bid_book) |> tree_insert_order(order_id, order)
    bid_book = :gb_trees.enter(price, tree, bid_book)
    %{state | bid_book: bid_book}
  end

  defp insert_order_into_tree(
         %Order{side: 1, order_id: order_id, price: price} = order,
         %{ask_book: ask_book} = state
       ) do
    tree = ask_tree(price, ask_book) |> tree_insert_order(order_id, order)
    ask_book = :gb_trees.enter(price, tree, ask_book)
    %{state | ask_book: ask_book}
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

  defp update_bid_book(tree, price, %{bid_book: bid_book} = state) do
    bid_book =
      if :gb_trees.is_empty(tree) do
        :gb_trees.delete(price, bid_book)
      else
        :gb_trees.enter(price, tree, bid_book)
      end

    %{state | bid_book: bid_book}
  rescue
    FunctionClauseError ->
      state
  end

  defp update_ask_book(tree, price, %{ask_book: ask_book} = state) do
    ask_book =
      if :gb_trees.is_empty(tree) do
        :gb_trees.delete(price, ask_book)
      else
        :gb_trees.enter(price, tree, ask_book)
      end

    %{state | ask_book: ask_book}
  rescue
    FunctionClauseError ->
      state
  end

  defp normalize_price(:undefined) do
    nil
  end

  defp normalize_price(price) when is_integer(price) or is_float(price) do
    (price / 1.0) |> Float.round(2)
  end

  def normalize_volume(volume) when is_integer(volume) or is_float(volume) do
    round(volume)
  end

  defp generate_id do
    :erlang.unique_integer([:positive, :monotonic])
  end

  defp timestep() do
    [{:step, step}] = :ets.lookup(:timestep, :step)
    step
  end
end
