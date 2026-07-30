defmodule DevCluster.DistributionTest do
  use ExUnit.Case, async: true

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
end
