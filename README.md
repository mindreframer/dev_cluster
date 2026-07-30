# DevCluster

[![CI](https://github.com/mindreframer/dev_cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/mindreframer/dev_cluster/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/dev_cluster.svg)](https://hex.pm/packages/dev_cluster)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/dev_cluster/)

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
    {:dev_cluster, "~> 0.1.0", only: :test}
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
- `hidden: true` — starts hidden Erlang nodes. This is useful for parallel tests
  that do not exercise `:global` because separate clusters will not merge their
  global registries.
- `name: :registered_cluster` — registers the cluster controller.
- `prefix: "worker_"` — produces names such as `worker_1@127.0.0.1`.
- `shutdown_timeout: milliseconds` — graceful per-member shutdown deadline.
- `cluster_shutdown_timeout: milliseconds` — overall concurrent member-shutdown
  deadline.

`DevCluster.stop/2` also accepts `timeout:` and `controller_timeout:` for a
custom public shutdown deadline. When `cluster_shutdown_timeout` exceeds the
seven-second `stop/1` deadline, call `stop/2` with a larger `timeout`. Production
defaults remain in use unless these options are explicitly provided.

The manager code paths, Mix environment, logger level, and application
configuration are copied before selected applications start.

## Coverage

When the manager has a running `:cover_server`—for example under
`mix test --cover`—DevCluster calls `:cover.start(nodes)` before application
startup. Calls made on child nodes are therefore included in the manager's
coverage report. Shutdown flushes remote counters before detaching a node from
`:cover`.

## Failure behavior

Starting a batch is transactional. If a peer cannot boot, an application fails
to start, a remote file raises, or another setup call fails, every peer created
for that batch is stopped and the existing cluster state is preserved. Cleanup
failures are included in the returned error instead of being hidden.

Explicit prefixes can still collide if two clusters use the same prefix at the
same time. Use generated defaults for concurrent clusters. Erlang node names
are atoms, so avoid creating unbounded numbers of unique explicit prefixes in a
long-lived VM.

## Test concurrency

Independent clusters can be tested from `async: true` ExUnit modules when node
names and external resources are unique. Use `hidden: true` to prevent unrelated
parallel clusters from interacting through `:global`; tests specifically
covering `:global` should use visible nodes and remain synchronous. Keep tests
that manipulate VM-global state such as `:cover_server` synchronous, and use a
modest `max_cases` value because every cluster member is a full BEAM process.
The package's own suite marks shutdown-timeout scenarios as `:heavy`, so they
can be targeted directly:

```bash
mix test --exclude heavy
mix test --only heavy
```

Release notes are available in [CHANGELOG.md](CHANGELOG.md).

Generate API documentation explicitly in the isolated docs environment:

```bash
MIX_ENV=docs mix deps.get
MIX_ENV=docs mix docs
```

## Maintainer

Roman Heinrich — [roman.heinrich@gmail.com](mailto:roman.heinrich@gmail.com)

## Origins

The API and lifecycle model are based on LocalCluster. Coverage propagation and
the modern local-node setup are based on HayCluster. Both projects are MIT
licensed.
