defmodule APXR.MyTrader do
  @moduledoc """
  Implement your trading strategy using this module as a template or modify it
  directly.
  """

  @behaviour APXR.Trader

  use GenServer

  alias APXR.{
    Market,
    Order,
    Trader
  }

  alias Decimal, as: D

  ## Client API

  @doc """
  Starts a MyTrader trader.
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
    {:ok, %{order_side_history: [], trader: trader}}
  end

  @impl true
  def handle_cast({:actuate}, state) do
    trader = my_trader(state)
    Market.ack(trader.trader_id)
    {:noreply, %{state | trader: trader}}
  end

  @impl true
  def handle_cast({:broadcast, _event}, state) do
    # Do nothing
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

  defp my_trader(%{trader: %Trader{} = trader} = _state) do
    # Your magic logic goes here...
    trader
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :my_trader,
      cash: D.new("20000000"),
      outstanding_orders: []
    }
  end
end
