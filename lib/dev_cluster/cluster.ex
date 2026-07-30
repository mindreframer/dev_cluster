defmodule DevCluster.Cluster do
  @moduledoc false

  use GenServer

  alias DevCluster.Member

  @rpc_timeout 30_000
  @shutdown_timeout 5_000
  @cluster_shutdown_timeout 6_000

  defmodule State do
    @moduledoc false
    defstruct prefix: nil, next_index: 1, members: [], options: []
  end

  @impl GenServer
  def init(options) do
    Process.flag(:trap_exit, true)

    {:ok,
     %State{
       prefix: cluster_prefix(options),
       options: options
     }}
  end

  @impl GenServer
  def handle_call({:initialize, amount}, _from, state) do
    case add_members(state, amount) do
      {:ok, modified, _members} -> {:reply, :ok, modified}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:members, _from, state) do
    {:reply, state.members, state}
  end

  def handle_call({:start, amount}, _from, state) do
    case add_members(state, amount) do
      {:ok, modified, members} -> {:reply, {:ok, members}, modified}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:shutdown, _from, state) do
    case shutdown_members(state.members) do
      [] -> {:reply, :ok, %{state | members: []}}
      errors -> {:reply, {:error, {:cluster_shutdown_failed, errors}}, %{state | members: []}}
    end
  end

  def handle_call({:stop, selector}, _from, state) do
    case find_member(state.members, selector) do
      nil ->
        {:reply, :ok, state}

      member ->
        case shutdown_member(member) do
          {:ok, result} ->
            members = List.delete(state.members, member)
            {:reply, result, %{state | members: members}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl GenServer
  def handle_info({:EXIT, peer, _reason}, state) when is_pid(peer) do
    members = Enum.reject(state.members, &(&1.peer == peer))
    {:noreply, %{state | members: members}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    shutdown_members(state.members)
    :ok
  end

  defp add_members(state, amount) do
    case start_members(state.prefix, state.next_index, amount, []) do
      {:ok, members} ->
        case configure_members(members, state.options) do
          :ok ->
            modified = %{
              state
              | members: state.members ++ members,
                next_index: state.next_index + amount
            }

            {:ok, modified, members}

          {:error, reason} ->
            {:error, add_cleanup_errors(reason, rollback(members))}
        end

      {:error, reason, started} ->
        {:error, add_cleanup_errors(reason, rollback(started))}
    end
  end

  defp start_members(_prefix, _index, 0, members), do: {:ok, Enum.reverse(members)}

  defp start_members(prefix, index, remaining, members) do
    short_name = String.to_atom("#{prefix}#{index}")

    options = %{
      name: short_name,
      host: ~c"127.0.0.1",
      longnames: true,
      wait_boot: @rpc_timeout
    }

    case :peer.start_link(options) do
      {:ok, peer, node} ->
        member = %Member{peer: peer, node: node}
        start_members(prefix, index + 1, remaining - 1, [member | members])

      {:error, reason} ->
        {:error, {:peer_start_failed, short_name, reason}, Enum.reverse(members)}

      other ->
        {:error, {:peer_start_failed, short_name, other}, Enum.reverse(members)}
    end
  end

  defp configure_members(members, options) do
    nodes = Enum.map(members, & &1.node)

    with :ok <- rpc_expect(nodes, :code, :add_paths, [:code.get_path()], &(&1 == :ok)),
         :ok <- ensure_applications(nodes, [:mix, :logger]),
         :ok <- rpc(nodes, Logger, :configure, [[level: Logger.level()]]),
         :ok <- rpc(nodes, Mix, :env, [Mix.env()]),
         :ok <- attach_coverage(nodes),
         :ok <- transfer_environment(nodes, options),
         :ok <- start_applications(nodes, options),
         :ok <- require_files(nodes, options) do
      :ok
    end
  end

  defp transfer_environment(nodes, options) do
    overrides = Keyword.get(options, :environment, [])

    loaded =
      Application.loaded_applications()
      |> Enum.map(fn {app, _description, _version} -> app end)

    applications = Enum.uniq(loaded ++ Keyword.keys(overrides))

    Enum.reduce_while(applications, :ok, fn application, :ok ->
      environment =
        application
        |> Application.get_all_env()
        |> Keyword.merge(Keyword.get(overrides, application, []))

      result =
        Enum.reduce_while(environment, :ok, fn {key, value}, :ok ->
          case rpc_expect(
                 nodes,
                 Application,
                 :put_env,
                 [application, key, value],
                 &(&1 == :ok)
               ) do
            :ok -> {:cont, :ok}
            {:error, _reason} = error -> {:halt, error}
          end
        end)

      case result do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp start_applications(nodes, options) do
    applications =
      Keyword.get_lazy(options, :applications, fn ->
        Application.started_applications()
        |> Enum.map(fn {app, _description, _version} -> app end)
        |> Enum.reverse()
      end)

    ensure_applications(nodes, applications)
  end

  defp ensure_applications(nodes, applications) do
    Enum.reduce_while(applications, :ok, fn application, :ok ->
      validator = fn
        {:ok, _started} -> :ok
        {:error, reason} -> {:error, {:application_start_failed, application, reason}}
        other -> {:error, {:unexpected_application_result, application, other}}
      end

      case rpc_expect(nodes, Application, :ensure_all_started, [application], validator) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp require_files(nodes, options) do
    options
    |> Keyword.get(:files, [])
    |> Enum.reduce_while(:ok, fn file, :ok ->
      case rpc(nodes, Code, :require_file, [file]) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp attach_coverage(nodes) do
    if Process.whereis(:cover_server) do
      case :cover.start(nodes) do
        {:ok, started_nodes} ->
          case nodes -- started_nodes do
            [] -> :ok
            missing -> {:error, {:coverage_start_failed, {:missing_nodes, missing}}}
          end

        {:error, reason} ->
          {:error, {:coverage_start_failed, reason}}

        other ->
          {:error, {:coverage_start_failed, other}}
      end
    else
      :ok
    end
  end

  defp rpc(nodes, module, function, arguments) do
    rpc_expect(nodes, module, function, arguments, fn _result -> :ok end)
  end

  defp rpc_expect(nodes, module, function, arguments, validator) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case remote_call(node, module, function, arguments) do
        {:ok, result} ->
          case validator.(result) do
            true ->
              {:cont, :ok}

            :ok ->
              {:cont, :ok}

            false ->
              {:halt, {:error, {:unexpected_remote_result, node, module, function, result}}}

            {:error, reason} ->
              {:halt, {:error, {:remote_setup_failed, node, reason}}}
          end

        {:error, reason} ->
          {:halt, {:error, {:remote_call_failed, node, module, function, reason}}}
      end
    end)
  end

  defp remote_call(node, module, function, arguments) do
    try do
      {:ok, :erpc.call(node, module, function, arguments, @rpc_timeout)}
    rescue
      exception -> {:error, {:exception, exception}}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp find_member(members, %Member{} = member), do: Enum.find(members, &(&1 == member))
  defp find_member(members, node) when is_atom(node), do: Enum.find(members, &(&1.node == node))
  defp find_member(members, peer) when is_pid(peer), do: Enum.find(members, &(&1.peer == peer))
  defp find_member(_members, _selector), do: nil

  defp rollback(members), do: shutdown_members(members)

  defp shutdown_members([]), do: []

  defp shutdown_members(members) do
    members
    |> Task.async_stream(&shutdown_member/1,
      max_concurrency: length(members),
      ordered: true,
      timeout: @cluster_shutdown_timeout,
      on_timeout: :kill_task
    )
    |> Enum.zip(members)
    |> Enum.reduce([], fn {task_result, member}, errors ->
      case task_result do
        {:ok, {:ok, :ok}} ->
          errors

        {:ok, {:ok, {:error, reason}}} ->
          [{member.node, reason} | errors]

        {:ok, {:error, reason}} ->
          Process.exit(member.peer, :kill)
          [{member.node, reason} | errors]

        {:exit, reason} ->
          Process.exit(member.peer, :kill)
          [{member.node, {:shutdown_timeout, reason}} | errors]
      end
    end)
    |> Enum.reverse()
  end

  defp add_cleanup_errors(reason, []), do: reason

  defp add_cleanup_errors(reason, errors),
    do: {:startup_failed, reason, {:cleanup_failed, errors}}

  defp shutdown_member(member) do
    coverage_result = detach_coverage(member.node)

    case stop_peer(member.peer) do
      :ok ->
        {:ok, coverage_result}

      {:error, reason} ->
        case force_stop_peer(member.peer) do
          :ok ->
            peer_error = {:peer_stop_failed_but_forced, reason}
            {:ok, {:error, combine_cleanup_errors(coverage_result, peer_error)}}

          {:error, force_reason} ->
            peer_error = {:peer_stop_failed, reason, force_reason}
            {:error, combine_cleanup_errors(coverage_result, peer_error)}
        end
    end
  end

  defp combine_cleanup_errors(:ok, peer_error), do: peer_error

  defp combine_cleanup_errors({:error, coverage_error}, peer_error),
    do: {:multiple_cleanup_failures, [coverage_error, peer_error]}

  defp stop_peer(peer) do
    run_bounded(
      fn ->
        try do
          :peer.stop(peer)
        catch
          :exit, {:noproc, _} -> :ok
          :exit, :noproc -> :ok
          kind, reason -> {:error, {kind, reason}}
        end
      end,
      @shutdown_timeout,
      :peer_stop_timeout
    )
  end

  defp force_stop_peer(peer) do
    if Process.alive?(peer) do
      reference = Process.monitor(peer)
      Process.exit(peer, :kill)

      receive do
        {:DOWN, ^reference, :process, ^peer, _reason} -> :ok
      after
        1_000 ->
          Process.demonitor(reference, [:flush])
          {:error, :force_stop_timeout}
      end
    else
      :ok
    end
  end

  defp detach_coverage(node) do
    if Process.whereis(:cover_server) do
      run_bounded(
        fn ->
          try do
            with :ok <- coverage_result(:cover.flush([node]), :flush, node),
                 :ok <- coverage_result(:cover.stop([node]), :stop, node) do
              :ok
            end
          catch
            kind, reason -> {:error, {:coverage_stop_failed, node, {kind, reason}}}
          end
        end,
        @shutdown_timeout,
        {:coverage_stop_timeout, node}
      )
    else
      :ok
    end
  end

  defp run_bounded(function, timeout, timeout_reason) do
    caller = self()
    result_ref = make_ref()

    {worker, monitor_ref} =
      spawn_monitor(fn ->
        send(caller, {result_ref, function.()})
      end)

    receive do
      {^result_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^worker, reason} ->
        {:error, {:shutdown_worker_failed, reason}}
    after
      timeout ->
        Process.exit(worker, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^worker, _reason} -> :ok
        after
          100 -> Process.demonitor(monitor_ref, [:flush])
        end

        {:error, timeout_reason}
    end
  end

  defp coverage_result(:ok, _operation, _node), do: :ok

  defp coverage_result({:error, reason}, operation, node),
    do: {:error, {:coverage_stop_failed, node, operation, reason}}

  defp coverage_result(other, operation, node),
    do: {:error, {:coverage_stop_failed, node, operation, other}}

  defp cluster_prefix(options) do
    case Keyword.get(options, :prefix) do
      nil -> "dev_cluster_#{System.pid()}_#{System.unique_integer([:positive])}_"
      prefix when is_atom(prefix) -> Atom.to_string(prefix)
      prefix when is_binary(prefix) -> prefix
    end
  end
end
