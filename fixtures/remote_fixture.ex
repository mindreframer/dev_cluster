defmodule DevCluster.RemoteFixture do
  def node_name, do: Node.self()
end
