defmodule APXR.Application do
  @moduledoc """
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications
  """

  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        APXR.Simulation,
        APXR.RunSupervisor
      ],
      strategy: :rest_for_one,
      name: APXR.Supervisor
    )
  end
end
