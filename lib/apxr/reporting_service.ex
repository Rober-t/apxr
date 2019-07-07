NimbleCSV.define(CSV.RFC4180,
  separator: ",",
  escape: "\"",
  skip_headers: true,
  moduledoc: """
  A CSV parser that uses comma as separator and double-quotes as escape according to RFC4180.
  """
)

defmodule APXR.ReportingService do
  @moduledoc """
  Trade reporting service. For example, dispatches events to subscribed agents.
  """

  use GenServer

  alias APXR.OrderbookEvent
  alias CSV.RFC4180, as: CSV

  ## Client API

  @doc """
  Starts ReportingService.
  """
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Writes the mid-price to disk for later processing and analysis.
  """
  def push_mid_price(price, iteration) do
    GenServer.cast(__MODULE__, {:push_mid_price, iteration, price})
  end

  @doc """
  Writes the price impact data to disk for later processing and analysis.
  """
  def push_price_impact(iteration, order_id, before_price, after_price, volume) do
    GenServer.cast(
      __MODULE__,
      {:push_price_impact, iteration, order_id, before_price, after_price, volume}
    )
  end

  @doc """
  Writes the order book events to disk for later processing and analysis and
  dispatches them to subscribed agents.
  """
  def push_event(%OrderbookEvent{} = event) do
    GenServer.cast(__MODULE__, {:push_event, event})
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    event_log_path = File.cwd!() |> Path.join("/apxr_trades.csv")
    if File.exists?(event_log_path), do: File.rm!(event_log_path)
    ed = File.open!(event_log_path, [:delayed_write, :append])

    mid_price_path = File.cwd!() |> Path.join("/apxr_mid_price.csv")
    if File.exists?(mid_price_path), do: File.rm!(mid_price_path)
    mpd = File.open!(mid_price_path, [:delayed_write, :append])

    mid_price_path = File.cwd!() |> Path.join("/apxr_price_impact.csv")
    if File.exists?(mid_price_path), do: File.rm!(mid_price_path)
    pimpd = File.open!(mid_price_path, [:delayed_write, :append])

    {:ok, %{event_device: ed, mid_price_device: mpd, price_impact_device: pimpd}}
  end

  @impl true
  def handle_cast({:push_mid_price, iteration, price}, state) do
    write_csv_file([[iteration, price]], :mid_price, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:push_price_impact, iteration, order_id, before_price, after_price, volume},
        state
      ) do
    write_csv_file(
      [[iteration, order_id, before_price, after_price, volume]],
      :price_impact,
      state
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:push_event, event}, state) do
    process_event(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{event_device: ed, mid_price_device: mpd, price_impact_device: pimpd}) do
    File.close(ed)
    File.close(mpd)
    File.close(pimpd)
  end

  ## Private

  defp process_event(%OrderbookEvent{transaction: true} = event, state) do
    write_csv_file(event, :event, state)
    broadcast_event(event)
  end

  defp process_event(%OrderbookEvent{transaction: false} = event, _state) do
    broadcast_event(event)
  end

  defp broadcast_event(%OrderbookEvent{} = event) do
    Registry.dispatch(APXR.ReportingServiceRegistry, "orderbook_event", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, event})
    end)
  end

  defp write_csv_file(iteration_price, :mid_price, %{mid_price_device: device}) do
    if Application.get_env(:apxr, :environment) == :test do
      :ok
    else
      data = CSV.dump_to_iodata(iteration_price)
      IO.binwrite(device, data)
    end
  end

  defp write_csv_file(iteration_price, :price_impact, %{price_impact_device: device}) do
    if Application.get_env(:apxr, :environment) == :test do
      :ok
    else
      data = CSV.dump_to_iodata(iteration_price)
      IO.binwrite(device, data)
    end
  end

  defp write_csv_file(event, :event, %{event_device: device}) do
    if Application.get_env(:apxr, :environment) == :test do
      :ok
    else
      data = parse_data(event) |> CSV.dump_to_iodata()
      IO.binwrite(device, data)
    end
  end

  defp parse_data(%OrderbookEvent{
         uid: uid,
         volume: volume,
         direction: direction,
         price: price
       }) do
    [
      [
        uid,
        volume,
        direction,
        price
      ]
    ]
  end
end
