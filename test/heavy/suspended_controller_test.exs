defmodule DevCluster.SuspendedControllerTest do
  use ExUnit.Case, async: true

  import DevCluster.TestHelpers
  import ExUnit.CaptureLog

  alias DevCluster.Member

  @moduletag :heavy

  test "public shutdown has a deadline when the controller is suspended" do
    {:ok, cluster} = start_cluster(1, prefix: unique_prefix("suspended_cluster"))
    {:ok, [%Member{node: node}]} = DevCluster.members(cluster)
    :ok = :sys.suspend(cluster)
    caller = self()

    capture_log(fn ->
      {elapsed, result} =
        :timer.tc(fn -> DevCluster.stop(cluster, timeout: 1_250, controller_timeout: 250) end)

      node_stopped? = eventually(fn -> Node.ping(node) == :pang end)
      Process.sleep(100)
      send(caller, {:stop_result, elapsed, result, node_stopped?})
    end)

    assert_receive {:stop_result, elapsed, {:error, :cluster_shutdown_timeout}, true}
    assert elapsed < 2_500_000
    refute Process.alive?(cluster)
  end
end
