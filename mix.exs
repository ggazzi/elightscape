defmodule Elightscape.MixProject do
  use Mix.Project

  def project do
    [
      app: :elightscape,
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
      mod: {Elightscape, []},
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
      {:gun, "~> 2.0.0-rc.2", override: true},
      {:json, "~> 1.4"},
      {:emqtt, github: "emqx/emqtt", tag: "1.6.0"},
      {:cowlib, "~> 2.11.0",
       env: :prod, hex: "cowlib", repo: "hexpm", optional: false, override: true},
      {:propcheck, "~> 1.4", only: [:test, :dev]}
    ]
  end
end
