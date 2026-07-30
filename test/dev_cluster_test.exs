defmodule DevClusterTest do
  use ExUnit.Case, async: false

  alias DevCluster.Member

  test "distribution startup is idempotent and uses a unique manager name" do
    assert :ok = DevCluster.start_distribution()
    assert :ok = DevCluster.start_distribution()
    assert Atom.to_string(Node.self()) =~ "dev_cluster_manager_"
    assert Atom.to_string(Node.self()) =~ System.pid()
  end

  test "rejects an already-running short-name manager" do
    executable = System.find_executable("elixir")
    ebin = Application.app_dir(:dev_cluster, "ebin")
    short_name = "dev_cluster_short_#{System.unique_integer([:positive])}"

    {output, status} =
      System.cmd(
        executable,
        [
          "--sname",
          short_name,
          "-pa",
          ebin,
          "-e",
          "IO.inspect(DevCluster.start_distribution())"
        ],
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "{:error, :shortnames_not_supported}"
  end

  test "creates, queries, stops, and cleans up cluster members" do
    {:ok, cluster} = DevCluster.start_link(3, prefix: unique_prefix("basic"))
    {:ok, nodes} = DevCluster.nodes(cluster)
    {:ok, members} = DevCluster.members(cluster)
    {:ok, peers} = DevCluster.pids(cluster)

    assert Enum.map(members, & &1.node) == nodes
    assert Enum.map(members, & &1.peer) == peers
    assert Enum.all?(nodes, &(Node.ping(&1) == :pong))

    [first | remaining] = nodes
    assert :ok = DevCluster.stop(cluster, first)
    assert Node.ping(first) == :pang
    assert {:ok, ^remaining} = DevCluster.nodes(cluster)

    assert :ok = DevCluster.stop(cluster)
    assert Enum.all?(remaining, &(Node.ping(&1) == :pang))
  end

  test "can stop members by struct, node, or peer pid" do
    {:ok, cluster} = DevCluster.start_link(3, prefix: unique_prefix("selectors"))
    {:ok, [member1, member2, member3]} = DevCluster.members(cluster)

    assert %Member{} = member1
    assert :ok = DevCluster.stop(cluster, member1)
    assert :ok = DevCluster.stop(cluster, member2.node)
    assert :ok = DevCluster.stop(cluster, member3.peer)
    assert {:ok, []} = DevCluster.nodes(cluster)
    assert :ok = DevCluster.stop(cluster, member1)
    assert :ok = DevCluster.stop(cluster)
  end

  test "adding members keeps node indexes monotonic after removals" do
    prefix = unique_prefix("index")
    {:ok, cluster} = DevCluster.start_link(3, prefix: prefix)
    {:ok, [_node1, node2, _node3]} = DevCluster.nodes(cluster)
    :ok = DevCluster.stop(cluster, node2)

    {:ok, [%Member{node: node4}]} = DevCluster.start(cluster, 1)
    assert node4 == String.to_atom("#{prefix}4@127.0.0.1")
    :ok = DevCluster.stop(cluster, node4)

    {:ok, [%Member{node: node5}]} = DevCluster.start(cluster, 1)
    assert node5 == String.to_atom("#{prefix}5@127.0.0.1")

    :ok = DevCluster.stop(cluster)
  end

  test "copies environment and starts selected applications" do
    {:ok, cluster} =
      DevCluster.start_link(1,
        prefix: unique_prefix("setup"),
        applications: [:dev_cluster, :ex_unit],
        environment: [dev_cluster: [remote_value: :overridden]]
      )

    {:ok, [node]} = DevCluster.nodes(cluster)

    assert :overridden ==
             :erpc.call(node, Application, :get_env, [:dev_cluster, :remote_value])

    loaded =
      node
      |> :erpc.call(Application, :loaded_applications, [])
      |> Enum.map(&elem(&1, 0))

    assert :dev_cluster in loaded
    assert :ex_unit in loaded
    :ok = DevCluster.stop(cluster)
  end

  test "requires additional files on remote nodes" do
    file = Path.expand("../fixtures/remote_fixture.ex", __DIR__)

    {:ok, cluster} =
      DevCluster.start_link(1, prefix: unique_prefix("files"), files: [file])

    {:ok, [node]} = DevCluster.nodes(cluster)

    assert :erpc.call(node, DevCluster.RemoteFixture, :node_name, []) == node
    :ok = DevCluster.stop(cluster)
  end

  test "bad application startup fails and rolls back nodes" do
    prefix = unique_prefix("rollback")

    assert {:error, reason} =
             DevCluster.start_link(1,
               prefix: prefix,
               applications: [:application_that_does_not_exist]
             )

    node = String.to_atom("#{prefix}1@127.0.0.1")
    assert inspect(reason) =~ "application_start_failed"
    assert eventually(fn -> Node.ping(node) == :pang end)
  end

  test "invalid amounts and options return errors" do
    assert {:error, {:invalid_amount, 0}} = DevCluster.start_link(0)
    assert {:error, {:invalid_amount, -1}} = DevCluster.start_link(-1)
    assert {:error, {:invalid_options, :bad}} = DevCluster.start_link(1, :bad)
    assert {:error, {:invalid_prefix, []}} = DevCluster.start_link(1, prefix: [])
    assert {:error, {:invalid_name, "bad"}} = DevCluster.start_link(1, name: "bad")

    assert {:error, {:unknown_options, [:aplications]}} =
             DevCluster.start_link(1, aplications: [:dev_cluster])

    assert {:error, {:invalid_environment, [dev_cluster: :bad]}} =
             DevCluster.start_link(1, environment: [dev_cluster: :bad])

    assert {:error, {:invalid_applications, ["dev_cluster"]}} =
             DevCluster.start_link(1, applications: ["dev_cluster"])

    assert {:error, {:invalid_files, [:not_a_path]}} =
             DevCluster.start_link(1, files: [:not_a_path])

    {:ok, cluster} = DevCluster.start_link(1)
    assert {:error, {:invalid_amount, 0}} = DevCluster.start(cluster, 0)
    :ok = DevCluster.stop(cluster)
  end

  test "supports named clusters under a supervisor" do
    children = [
      {DevCluster, {1, [name: :supervised_dev_cluster, prefix: unique_prefix("supervised")]}}
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
    assert {:ok, [_node]} = DevCluster.nodes(:supervised_dev_cluster)
    Supervisor.stop(supervisor)
    refute Process.whereis(:supervised_dev_cluster)
  end

  test "concurrent clusters have independent controllers and names" do
    {:ok, cluster1} = DevCluster.start_link(1)
    {:ok, cluster2} = DevCluster.start_link(1)
    {:ok, [node1]} = DevCluster.nodes(cluster1)
    {:ok, [node2]} = DevCluster.nodes(cluster2)

    refute cluster1 == cluster2
    refute node1 == node2

    :ok = DevCluster.stop(cluster1)
    assert Node.ping(node1) == :pang
    assert Node.ping(node2) == :pong
    :ok = DevCluster.stop(cluster2)
  end

  test "stops unresponsive peer controllers concurrently within a cluster deadline" do
    {:ok, cluster} = DevCluster.start_link(1, prefix: unique_prefix("blocked_stop"))

    blocked_members =
      Enum.map(1..3, fn index ->
        peer =
          spawn(fn ->
            receive do
              :never -> :ok
            end
          end)

        %Member{peer: peer, node: String.to_atom("blocked#{index}@127.0.0.1")}
      end)

    :sys.replace_state(cluster, fn state ->
      %{state | members: blocked_members ++ state.members}
    end)

    {elapsed, result} = :timer.tc(fn -> DevCluster.stop(cluster) end)

    assert {:error, {:cluster_shutdown_failed, errors}} = result
    assert length(errors) == 3
    assert elapsed < 7_000_000
    refute Process.alive?(cluster)
    refute Enum.any?(blocked_members, &Process.alive?(&1.peer))
  end

  test "owner death stops its cluster nodes and peer controllers" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, cluster} = DevCluster.start_link(1, prefix: unique_prefix("owned"))
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

  defp unique_prefix(label) do
    "#{label}_#{System.pid()}_#{System.unique_integer([:positive])}_"
  end

  defp eventually(function, attempts \\ 50)
  defp eventually(function, 0), do: function.()

  defp eventually(function, attempts) do
    if function.() do
      true
    else
      Process.sleep(20)
      eventually(function, attempts - 1)
    end
  end
end
