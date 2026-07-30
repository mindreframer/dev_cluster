defmodule DevCluster.ClusterTest do
  use ExUnit.Case, async: true

  import DevCluster.TestHelpers

  alias DevCluster.Member

  test "creates, queries, stops, and cleans up cluster members" do
    {:ok, cluster} = start_cluster(3, prefix: unique_prefix("basic"))
    {:ok, nodes} = DevCluster.nodes(cluster)
    {:ok, members} = DevCluster.members(cluster)
    {:ok, peers} = DevCluster.pids(cluster)

    assert Enum.map(members, & &1.node) == nodes
    assert Enum.map(members, & &1.peer) == peers
    assert Enum.all?(nodes, &(&1 in Node.list(:hidden)))
    assert Enum.all?(nodes, &(Node.ping(&1) == :pong))

    [first | remaining] = nodes
    assert :ok = DevCluster.stop(cluster, first)
    assert Node.ping(first) == :pang
    assert {:ok, ^remaining} = DevCluster.nodes(cluster)

    assert :ok = DevCluster.stop(cluster)
    assert Enum.all?(remaining, &(Node.ping(&1) == :pang))
  end

  test "can stop members by struct, node, or peer pid" do
    {:ok, cluster} = start_cluster(3, prefix: unique_prefix("selectors"))
    {:ok, [member1, member2, member3]} = DevCluster.members(cluster)

    assert %Member{} = member1
    assert :ok = DevCluster.stop(cluster, member1)
    assert :ok = DevCluster.stop(cluster, member2.node)
    assert :ok = DevCluster.stop(cluster, member3.peer)
    assert {:ok, []} = DevCluster.nodes(cluster)
    assert :ok = DevCluster.stop(cluster, member1)
    assert :ok = DevCluster.stop(cluster)
  end

  test "supports named clusters under a supervisor" do
    cluster_name = String.to_atom(unique_prefix("supervised"))

    children = [
      {DevCluster,
       {1, hidden_options(name: cluster_name, prefix: unique_prefix("supervised_node"))}}
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
    assert {:ok, [_node]} = DevCluster.nodes(cluster_name)
    Supervisor.stop(supervisor)
    refute Process.whereis(cluster_name)
  end

  test "concurrent clusters have independent controllers and names" do
    {:ok, cluster1} = start_cluster(1)
    {:ok, cluster2} = start_cluster(1)
    {:ok, [node1]} = DevCluster.nodes(cluster1)
    {:ok, [node2]} = DevCluster.nodes(cluster2)

    refute cluster1 == cluster2
    refute node1 == node2

    :ok = DevCluster.stop(cluster1)
    assert Node.ping(node1) == :pang
    assert Node.ping(node2) == :pong
    :ok = DevCluster.stop(cluster2)
  end
end
