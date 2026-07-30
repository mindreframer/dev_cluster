defmodule DevCluster.ConfigurationTest do
  use ExUnit.Case, async: true

  import DevCluster.TestHelpers

  test "copies environment and starts selected applications" do
    {:ok, cluster} =
      start_cluster(1,
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
      start_cluster(1, prefix: unique_prefix("files"), files: [file])

    {:ok, [node]} = DevCluster.nodes(cluster)

    assert :erpc.call(node, DevCluster.RemoteFixture, :node_name, []) == node
    :ok = DevCluster.stop(cluster)
  end

  test "bad application startup fails and rolls back nodes" do
    prefix = unique_prefix("rollback")

    assert {:error, reason} =
             start_cluster(1,
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

    assert {:error, {:invalid_hidden, :yes}} = DevCluster.start_link(1, hidden: :yes)

    assert {:error, {:invalid_shutdown_timeout, 0}} =
             DevCluster.start_link(1, shutdown_timeout: 0)

    assert {:error, {:invalid_cluster_shutdown_timeout, -1}} =
             DevCluster.start_link(1, cluster_shutdown_timeout: -1)

    {:ok, cluster} = start_cluster(1)
    assert {:error, {:invalid_amount, 0}} = DevCluster.start(cluster, 0)
    assert {:error, {:invalid_stop_timeout, 0}} = DevCluster.stop(cluster, timeout: 0)

    assert {:error, {:unknown_stop_options, [:unknown]}} =
             DevCluster.stop(cluster, unknown: 1)

    :ok = DevCluster.stop(cluster)
  end
end
