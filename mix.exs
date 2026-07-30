defmodule DevCluster.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mindreframer/dev_cluster"

  def project do
    [
      app: :dev_cluster,
      name: "DevCluster",
      version: @version,
      elixir: "~> 1.14",
      description: "Local distributed-node test clusters with remote coverage",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
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
      {:ex_doc, "~> 0.34", only: :docs, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"],
      maintainers: ["Roman Heinrich"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "DevCluster",
      extras: ["README.md", "CHANGELOG.md"],
      authors: ["Roman Heinrich"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
