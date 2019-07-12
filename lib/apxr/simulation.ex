defmodule APXR.Simulation do
  @moduledoc """
  Simulation manager. 
  """

  use GenServer

  alias APXR.{
    Market,
    RunSupervisor
  }

  @total_runs 10

  ## Client API

  @doc """
  Starts the Simulation server.
  """
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts the simulation.
  """
  def start do
    GenServer.cast(__MODULE__, {:start})
  end

  @doc """
  Sent from the Market process at the end of the day.
  Starts a new day of stops the simulation depending on the number of runs
  completed.
  """
  def run_over do
    GenServer.cast(__MODULE__, {:run_over})
  end

  ## Server callbacks

  @impl true
  def init([]) do
    :ets.new(:run_number, [:public, :named_table, read_concurrency: true])
    dir = File.cwd!() |> Path.join("/output")
    File.rm_rf!(dir)
    File.mkdir!(dir)
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:start}, state) do
    do_run()
    {:noreply, state}
  end

  @impl true
  @spec handle_cast(any(), any()) :: no_return()
  def handle_cast({:run_over}, state) do
    do_run()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private

  defp do_run() do
    run_number = :ets.update_counter(:run_number, :number, 1, {0, 0})

    case run_number do
      1 ->
        IO.puts("SIMULATION STARTED")
        Market.open(run_number)

      run_number when run_number > @total_runs ->
        IO.puts("\nRUN #{run_number - 1} ENDED")
        IO.puts("SIMULATION FINISHED")
        System.stop(0)

      _ ->
        Process.whereis(RunSupervisor) |> Process.exit(:shutdown)
        IO.puts("\nRUN #{run_number - 1} ENDED")
        Market.open(run_number)
    end
  end
end
