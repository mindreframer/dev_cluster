defmodule DevCluster.UnresponsiveShutdownTest do
  use ExUnit.Case, async: true

  import DevCluster.TestHelpers

  alias DevCluster.Member

  @moduletag :heavy

  test "stops unresponsive peer controllers concurrently within a cluster deadline" do
    {:ok, cluster} =
      start_cluster(1,
        prefix: unique_prefix("blocked_stop"),
        shutdown_timeout: 750,
        cluster_shutdown_timeout: 1_000
      )

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
    assert elapsed < 2_000_000
    refute Process.alive?(cluster)
    refute Enum.any?(blocked_members, &Process.alive?(&1.peer))
  end
end
