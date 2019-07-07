defmodule APXR.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :apxr,
      version: @version,
      elixir: "~> 1.9",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      xref: xref(),
      deps: deps(),
      aliases: aliases(),
      test_coverage: [summary: true],
      preferred_cli_env: [check: :test]
    ]
  end

  # Configuration for the OTP application.
  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {APXR.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp xref() do
    [exclude: [ApxrSh.Registry]]
  end

  # Specifies your project dependencies.
  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 1.0", only: :dev},
      {:dialyxir, "~> 1.0.0-rc.6", only: [:dev], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  defp aliases() do
    [
      check: [
        "deps.get",
        "deps.compile",
        "compile --warnings-as-errors",
        "format",
        "xref unreachable",
        "xref deprecated",
        "test"
      ]
    ]
  end
end
