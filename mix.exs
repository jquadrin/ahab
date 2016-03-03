defmodule Ahab.Mixfile do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/jquadrin/ahab"

  def project do
    [app: :ahab,
     version: @version,
     elixir: "~> 1.2",
     deps: deps,
     docs: docs,
     name: "Ahab",
     description: description,
     package: package,
     source_url: @source_url]
  end

  def application do
    [applications: []]
  end

  defp deps do
    []
  end

  defp docs do
    [source_ref: "v#{@version}", 
     main: "readme", 
     extras: ["README.md"]]
  end

  defp description do
  """
  A lightweight, low latency TCP acceptor pool for Elixir.

  """
  end

  defp package do
    [maintainers: ["Joe Quadrino"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => @source_url}]
  end
end
