defmodule DevCluster.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :dev_cluster,
      version: @version,
      elixir: "~> 1.14",
      description: "Local distributed-node test clusters with remote coverage",
      package: package(),
      docs: [main: "DevCluster"],
      deps: deps(),
      aliases: [test: "test --no-start"],
      test_coverage: [summary: [threshold: 70]]
    ]
  end

  def application do
    [extra_applications: [:logger, :tools]]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      licenses: ["MIT"]
    ]
  end
end
