# DevCluster

`DevCluster` starts real local BEAM nodes for testing distributed Elixir code.
It combines the per-cluster ownership model of
[LocalCluster](https://github.com/whitfin/local-cluster) with the modern
`:peer`/`:erpc` and distributed coverage approach of
[HayCluster](https://github.com/tank-bohr/hay_cluster).

## Why another cluster helper?

- One linked controller per cluster; there is no global cluster server.
- Modern OTP `:peer` nodes with automatic cleanup.
- Remote execution contributes to `mix test --cover`.
- Transactional node startup and rollback on setup failures.
- Checked remote application and file setup.
- Monotonic member names after nodes are removed.
- No `global_flags`, inet boot server, or legacy `:slave` fallback.

This is a **local multi-node test tool**, not a replacement for containerized or
multi-machine integration tests.

## Requirements

- Elixir 1.14 or newer
- Erlang/OTP 25 or newer (`:peer` and `:erpc`)
- Long-name Erlang distribution; an existing short-name manager is rejected
- `epmd` available; CI environments may need `epmd -daemon`

## Installation

Add the package as a test dependency:

```elixir
defp deps do
  [
    {:dev_cluster, path: "../dev_cluster", only: :test}
  ]
end
```

Prevent Mix from starting your application before the manager becomes a
distributed node:

```elixir
defp aliases do
  [test: "test --no-start"]
end
```

Then configure `test/test_helper.exs`:

```elixir
:ok = DevCluster.start_distribution()
{:ok, _} = Application.ensure_all_started(:my_app)
ExUnit.start()
```

The default manager and member names include the OS process ID, so independent
test VMs do not compete for fixed names.

## Usage

```elixir
defmodule MyDistributedTest do
  use ExUnit.Case, async: false

  test "runs on three nodes" do
    {:ok, cluster} =
      DevCluster.start_link(3,
        applications: [:my_app],
        environment: [my_app: [port: 0]]
      )

    on_exit(fn ->
      if Process.alive?(cluster), do: DevCluster.stop(cluster)
    end)

    {:ok, nodes} = DevCluster.nodes(cluster)

    assert Enum.all?(nodes, fn node ->
             :erpc.call(node, MyApp.Health, :ready?, [])
           end)
  end
end
```

The cluster controller and its `:peer` processes are linked. Stopping the
controller stops all nodes concurrently within a bounded deadline. A member can
also be stopped independently:

```elixir
{:ok, [node | _]} = DevCluster.nodes(cluster)
:ok = DevCluster.stop(cluster, node)
```

Nodes can be added later without reusing names of removed members:

```elixir
{:ok, new_members} = DevCluster.start(cluster, 2)
```

## Options

`DevCluster.start_link/2` accepts:

- `applications: [:app_a, :app_b]` — applications started in this order. By
  default, applications started on the manager are mirrored.
- `environment: [my_app: [key: value]]` — application environment overrides.
- `files: [absolute_path]` — files required on every node, useful for test-only
  modules.
- `name: :registered_cluster` — registers the cluster controller.
- `prefix: "worker_"` — produces names such as `worker_1@127.0.0.1`.

The manager code paths, Mix environment, logger level, and application
configuration are copied before selected applications start.

## Coverage

When the manager has a running `:cover_server`—for example under
`mix test --cover`—DevCluster calls `:cover.start(nodes)` before application
startup. Calls made on child nodes are therefore included in the manager's coverage
report. Shutdown flushes remote counters before detaching a node from `:cover`.

## Failure behavior

Starting a batch is transactional. If a peer cannot boot, an application fails
to start, a remote file raises, or another setup call fails, every peer created
for that batch is stopped and the existing cluster state is preserved. Cleanup
failures are included in the returned error instead of being hidden.

Explicit prefixes can still collide if two clusters use the same prefix at the
same time. Use generated defaults for concurrent clusters. Erlang node names
are atoms, so avoid creating unbounded numbers of unique explicit prefixes in a
long-lived VM.

## Origins

The API and lifecycle model are based on LocalCluster. Coverage propagation and
the modern local-node setup are based on HayCluster. Both projects are MIT
licensed.
