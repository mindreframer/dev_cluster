defmodule DevCluster.MembershipTest do
  use ExUnit.Case, async: true

  import DevCluster.TestHelpers

  alias DevCluster.Member

  test "adding members keeps node indexes monotonic after removals" do
    prefix = unique_prefix("index")
    {:ok, cluster} = start_cluster(3, prefix: prefix)
    {:ok, [_node1, node2, _node3]} = DevCluster.nodes(cluster)
    :ok = DevCluster.stop(cluster, node2)

    {:ok, [%Member{node: node4}]} = DevCluster.start(cluster, 1)
    assert node4 == String.to_atom("#{prefix}4@127.0.0.1")
    :ok = DevCluster.stop(cluster, node4)

    {:ok, [%Member{node: node5}]} = DevCluster.start(cluster, 1)
    assert node5 == String.to_atom("#{prefix}5@127.0.0.1")

    :ok = DevCluster.stop(cluster)
  end
end
