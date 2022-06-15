defmodule Roomctrl.MixProject do
  use Mix.Project

  def project do
    [
      app: :roomctrl,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :gun],
      mod: {RoomCtrl, []},
      env: [
        hass_plugin: true,
        hass_host: "localhost",
        hass_port: 8123,
        hass_token: nil
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gun, "~> 2.0.0-rc.2"},
      {:json, "~> 1.4"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
