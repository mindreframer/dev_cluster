defmodule DevCluster.LifecycleTest do
  use ExUnit.Case, async: true

  import DevCluster.TestHelpers

  alias DevCluster.Member

  test "owner death stops its cluster nodes and peer controllers" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, cluster} = start_cluster(1, prefix: unique_prefix("owned"))
        {:ok, [%Member{node: node, peer: peer}]} = DevCluster.members(cluster)
        send(parent, {:owned_cluster, node, peer})

        receive do
          :finish -> :ok
        end
      end)

    owner_ref = Process.monitor(owner)
    assert_receive {:owned_cluster, node, peer}, 30_000
    assert Node.ping(node) == :pong
    assert Process.alive?(peer)

    send(owner, :finish)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :normal}
    assert eventually(fn -> Node.ping(node) == :pang end)
    refute Process.alive?(peer)
  end
end
