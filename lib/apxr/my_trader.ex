defmodule APXR.MyTrader do
  @moduledoc """
  Implement your trading strategy using this module as a template or modify it
  directly.
  """

  @behaviour APXR.Trader

  use GenServer

  alias APXR.{
    Order,
    Trader
  }

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
    {:ok, %{order_side_history: [], trader: trader}}
  end

  @impl true
  def handle_call({:actuate}, _from, state) do
    state = action(state)
    {:reply, :ok, state}
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

  defp action(%{trader: %Trader{} = _trader} = state) do
    # Your logic goes here...
    state
  end

  defp init_trader(id) do
    %Trader{
      trader_id: {__MODULE__, id},
      type: :my_trader,
      cash: 20_000_000.0,
      outstanding_orders: []
    }
  end
end
