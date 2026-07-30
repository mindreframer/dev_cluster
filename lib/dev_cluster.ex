defmodule DevCluster do
  @moduledoc """
  Starts local BEAM nodes for distributed Elixir tests.

  Each cluster has its own linked controller process. Nodes are configured with
  the manager's code paths, Mix environment, application environment and
  selected applications. When `:cover` is running, new nodes are attached to it
  so remotely executed code contributes to the coverage report.
  """

  alias DevCluster.{Cluster, Member}

  @timeout 30_000
  @cluster_option_keys [:applications, :environment, :files, :name, :prefix]

  @type cluster :: GenServer.server()
  @type option ::
          {:applications, [atom()]}
          | {:environment, keyword()}
          | {:files, [Path.t()]}
          | {:name, GenServer.name()}
          | {:prefix, atom() | String.t()}

  @doc """
  Starts Erlang distribution for the current VM.

  Calling this function again is safe. The default manager name includes the OS
  process ID to avoid collisions with other test VMs on the same machine.
  """
  @spec start_distribution(keyword()) :: :ok | {:error, term()}
  def start_distribution(opts \\ [])

  def start_distribution(opts) when is_list(opts) do
    with :ok <- validate_distribution_options(opts) do
      if Node.alive?() do
        ensure_longnames()
      else
        name = Keyword.get(opts, :name, default_manager_name())

        case :net_kernel.start([normalize_manager_name(name), :longnames]) do
          {:ok, _pid} -> ensure_longnames()
          {:error, {:already_started, _pid}} -> ensure_longnames()
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  def start_distribution(opts), do: {:error, {:invalid_options, opts}}

  @doc "Alias for `start_distribution/0`."
  @spec start() :: :ok | {:error, term()}
  def start, do: start_distribution()

  @doc "Starts a linked cluster containing `amount` nodes."
  @spec start_link(pos_integer(), [option()]) :: GenServer.on_start()
  def start_link(amount, opts \\ [])

  def start_link(amount, opts)
      when is_integer(amount) and amount > 0 and is_list(opts) do
    with :ok <- validate_options(opts),
         :ok <- ensure_distribution_started() do
      case GenServer.start_link(Cluster, opts, Keyword.take(opts, [:name])) do
        {:ok, cluster} ->
          case GenServer.call(cluster, {:initialize, amount}, :infinity) do
            :ok ->
              {:ok, cluster}

            {:error, reason} ->
              GenServer.stop(cluster, :normal, @timeout)
              {:error, reason}
          end

        other ->
          other
      end
    end
  end

  def start_link(amount, _opts) when not is_integer(amount) or amount <= 0,
    do: {:error, {:invalid_amount, amount}}

  def start_link(_amount, opts), do: {:error, {:invalid_options, opts}}

  @doc "Returns a supervisor child specification for a cluster."
  @spec child_spec({pos_integer(), [option()]}) :: Supervisor.child_spec()
  def child_spec({amount, opts}) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [amount, opts]},
      type: :worker
    }
  end

  @doc "Returns all members owned by a cluster."
  @spec members(cluster()) :: {:ok, [Member.t()]}
  def members(cluster), do: {:ok, GenServer.call(cluster, :members, @timeout)}

  @doc "Returns all distributed node names owned by a cluster."
  @spec nodes(cluster()) :: {:ok, [node()]}
  def nodes(cluster) do
    {:ok, members} = members(cluster)
    {:ok, Enum.map(members, & &1.node)}
  end

  @doc "Returns the local `:peer` controller PIDs owned by a cluster."
  @spec pids(cluster()) :: {:ok, [pid()]}
  def pids(cluster) do
    {:ok, members} = members(cluster)
    {:ok, Enum.map(members, & &1.peer)}
  end

  @doc "Adds nodes to an existing cluster transactionally."
  @spec start(cluster(), pos_integer()) :: {:ok, [Member.t()]} | {:error, term()}
  def start(cluster, amount) when is_integer(amount) and amount > 0,
    do: GenServer.call(cluster, {:start, amount}, :infinity)

  def start(_cluster, amount), do: {:error, {:invalid_amount, amount}}

  @doc "Stops a cluster and all of its nodes within a bounded deadline."
  @spec stop(cluster()) :: :ok | {:error, term()}
  def stop(cluster) do
    result = GenServer.call(cluster, :shutdown, :infinity)
    GenServer.stop(cluster, :normal, @timeout)
    result
  end

  @doc "Stops one member, selected by member struct, node name, or peer PID."
  @spec stop(cluster(), Member.t() | node() | pid()) :: :ok | {:error, term()}
  def stop(cluster, selector),
    do: GenServer.call(cluster, {:stop, selector}, @timeout)

  @doc "Stops Erlang distribution for the current VM."
  @spec stop_distribution() :: :ok | {:error, term()}
  def stop_distribution do
    if Node.alive?(), do: :net_kernel.stop(), else: :ok
  end

  defp ensure_distribution_started do
    if Node.alive?(), do: ensure_longnames(), else: {:error, :distribution_not_started}
  end

  defp validate_options(opts) do
    unknown_keys =
      if Keyword.keyword?(opts), do: Keyword.keys(opts) -- @cluster_option_keys, else: []

    cond do
      not Keyword.keyword?(opts) ->
        {:error, {:invalid_options, opts}}

      unknown_keys != [] ->
        {:error, {:unknown_options, Enum.uniq(unknown_keys)}}

      not valid_name?(Keyword.get(opts, :name)) ->
        {:error, {:invalid_name, Keyword.get(opts, :name)}}

      not valid_prefix?(Keyword.get(opts, :prefix, "dev_cluster")) ->
        {:error, {:invalid_prefix, Keyword.get(opts, :prefix)}}

      not valid_applications?(Keyword.get(opts, :applications, [])) ->
        {:error, {:invalid_applications, Keyword.get(opts, :applications)}}

      not valid_files?(Keyword.get(opts, :files, [])) ->
        {:error, {:invalid_files, Keyword.get(opts, :files)}}

      not valid_environment?(Keyword.get(opts, :environment, [])) ->
        {:error, {:invalid_environment, Keyword.get(opts, :environment)}}

      true ->
        :ok
    end
  end

  defp validate_distribution_options(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, {:invalid_options, opts}}

      Keyword.keys(opts) -- [:name] != [] ->
        {:error, {:unknown_options, Enum.uniq(Keyword.keys(opts) -- [:name])}}

      not is_atom(Keyword.get(opts, :name, :dev_cluster_manager)) ->
        {:error, {:invalid_name, Keyword.get(opts, :name)}}

      true ->
        :ok
    end
  end

  defp valid_name?(nil), do: true
  defp valid_name?(name) when is_atom(name), do: true
  defp valid_name?({:global, _term}), do: true
  defp valid_name?({:via, module, _term}) when is_atom(module), do: true
  defp valid_name?(_name), do: false

  defp valid_prefix?(prefix), do: is_atom(prefix) or is_binary(prefix)
  defp valid_applications?(apps), do: is_list(apps) and Enum.all?(apps, &is_atom/1)
  defp valid_files?(files), do: is_list(files) and Enum.all?(files, &is_binary/1)

  defp valid_environment?(environment) do
    Keyword.keyword?(environment) and
      Enum.all?(environment, fn {application, values} ->
        is_atom(application) and Keyword.keyword?(values)
      end)
  end

  defp ensure_longnames do
    case :net_kernel.longnames() do
      true -> :ok
      false -> {:error, :shortnames_not_supported}
      :ignored -> {:error, :distribution_not_started}
    end
  end

  defp default_manager_name do
    String.to_atom("dev_cluster_manager_#{System.pid()}@127.0.0.1")
  end

  defp normalize_manager_name(name) when is_atom(name) do
    if String.contains?(Atom.to_string(name), "@") do
      name
    else
      String.to_atom("#{name}@127.0.0.1")
    end
  end
end
