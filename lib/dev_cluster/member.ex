defmodule DevCluster.Member do
  @moduledoc """
  A node owned by a DevCluster controller process.

  `peer` is the local `:peer` controller process and `node` is the distributed
  Erlang node name.
  """

  @enforce_keys [:peer, :node]
  defstruct [:peer, :node]

  @type t :: %__MODULE__{peer: pid(), node: node()}
end
