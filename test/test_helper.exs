defmodule DevCluster.TestHelpers do
  def start_cluster(amount, options \\ []) do
    DevCluster.start_link(amount, Keyword.put_new(options, :hidden, true))
  end

  def hidden_options(options \\ []) do
    Keyword.put_new(options, :hidden, true)
  end

  def unique_prefix(label) do
    "#{label}_#{System.pid()}_#{System.unique_integer([:positive])}_"
  end

  def eventually(function, attempts \\ 50)
  def eventually(function, 0), do: function.()

  def eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(20)
      eventually(function, attempts - 1)
    end
  end
end

Logger.configure(level: :error)
:ok = DevCluster.start_distribution()
ExUnit.start(max_cases: 3)
