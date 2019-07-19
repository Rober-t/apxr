NimbleCSV.define(CSV.RFC4180,
  separator: ",",
  escape: "\"",
  skip_headers: true,
  moduledoc: """
  A CSV parser that uses comma as separator and double-quotes as escape
  according to RFC4180.
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
  Prep the Reporting Service.
  """
  def prep(run_number) do
    GenServer.cast(__MODULE__, {:prep, run_number})
  end

  @doc """
  Writes the mid-price to disk for later processing and analysis.
  """
  def push_mid_price(price, timestep) do
    GenServer.cast(__MODULE__, {:push_mid_price, timestep, price})
  end

  @doc """
  Writes the order side to disk for later processing and analysis.
  """
  def push_order_side(timestep, id, type, side) do
    GenServer.cast(__MODULE__, {:push_order_side, timestep, id, type, side})
  end

  @doc """
  Writes the price impact data to disk for later processing and analysis.
  """
  def push_price_impact(timestep, id, type, volume, before_p, after_p) do
    GenServer.cast(
      __MODULE__,
      {:push_price_impact, timestep, id, type, volume, before_p, after_p}
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
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:prep, run_number}, _state) do
    state = do_prep(run_number)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:push_mid_price, _timestep, price}, state) do
    write_csv_file([[price]], :mid_price, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:push_order_side, _timestep, _order_id, _order_type, side}, state) do
    write_csv_file([[side]], :order_side, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:push_price_impact, _timestep, _id, _type, vol, before_p, after_p}, state) do
    impact = impact(before_p, after_p)
    write_csv_file([[vol, impact]], :price_impact, state)
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
  def terminate(_reason, %{
        event_device: ed,
        mid_price_device: mpd,
        order_side_device: osd,
        price_impact_device: pimpd
      }) do
    File.close(ed)
    File.close(mpd)
    File.close(osd)
    File.close(pimpd)
  end

  ## Private

  defp do_prep(run_number) do
    run = to_string(run_number)

    event_log_path = File.cwd!() |> Path.join("/output/apxr_trades" <> run <> ".csv")
    ed = File.open!(event_log_path, [:delayed_write, :append])

    mid_price_path = File.cwd!() |> Path.join("/output/apxr_mid_prices" <> run <> ".csv")
    mpd = File.open!(mid_price_path, [:delayed_write, :append])

    order_side_path = File.cwd!() |> Path.join("/output/apxr_order_sides" <> run <> ".csv")
    osd = File.open!(order_side_path, [:delayed_write, :append])

    price_impact_path = File.cwd!() |> Path.join("/output/apxr_price_impacts" <> run <> ".csv")
    pimpd = File.open!(price_impact_path, [:delayed_write, :append])

    %{
      run_number: run_number,
      event_device: ed,
      mid_price_device: mpd,
      order_side_device: osd,
      price_impact_device: pimpd
    }
  end

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

  defp write_csv_file(row, :mid_price, %{mid_price_device: device}) do
    if Application.get_env(:apxr, :environment) == :test do
      :ok
    else
      data = CSV.dump_to_iodata(row)
      IO.binwrite(device, data)
    end
  end

  defp write_csv_file(row, :order_side, %{order_side_device: device}) do
    if Application.get_env(:apxr, :environment) == :test do
      :ok
    else
      data = CSV.dump_to_iodata(row)
      IO.binwrite(device, data)
    end
  end

  defp write_csv_file(row, :price_impact, %{price_impact_device: device}) do
    if Application.get_env(:apxr, :environment) == :test do
      :ok
    else
      data = CSV.dump_to_iodata(row)
      IO.binwrite(device, data)
    end
  end

  defp write_csv_file(row, :event, %{event_device: device, run_number: run_number}) do
    if Application.get_env(:apxr, :environment) == :test do
      :ok
    else
      data = parse_event_data(run_number, row) |> CSV.dump_to_iodata()
      IO.binwrite(device, data)
    end
  end

  defp parse_event_data(_run_number, %OrderbookEvent{price: price}) do
    [[price]]
  end

  defp impact(before_p, after_p) do
    before_p = max(before_p, 0.0001)
    after_p = max(after_p, 0.0001)
    :math.log(after_p) - :math.log(before_p)
  end
end
