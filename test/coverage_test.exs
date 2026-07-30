defmodule DevCluster.CoverageTest do
  use ExUnit.Case, async: false

  test "counts code executed on remote nodes and flushes it during shutdown" do
    started_cover? = Process.whereis(:cover_server) == nil

    if started_cover? do
      assert {:ok, _pid} = :cover.start()
    end

    assert {:ok, DevCluster} = :cover.compile_beam(DevCluster)

    prefix = "coverage_#{System.pid()}_#{System.unique_integer([:positive])}_"
    {:ok, cluster} = DevCluster.start_link(1, prefix: prefix)

    try do
      {:ok, [node]} = DevCluster.nodes(cluster)

      assert :ok = :erpc.call(node, DevCluster, :start_distribution, [])

      assert :ok = DevCluster.stop(cluster)

      assert {:ok, functions} = :cover.analyse(DevCluster, :calls, :function)

      assert {{DevCluster, :start_distribution, 0}, calls} =
               List.keyfind(functions, {DevCluster, :start_distribution, 0}, 0)

      assert calls >= 1
    after
      if Process.alive?(cluster), do: DevCluster.stop(cluster)
      if started_cover? and Process.whereis(:cover_server), do: :cover.stop()
    end
  end
end
