defmodule BackendCommon do
  @moduledoc """
  Documentation for BackendCommon.
  """

  def start(_type, _args) do
    children = [
      {BackendCommon.Vault, name: BackendCommon.Vault}
    ]

    opts = [strategy: :one_for_one, name: BackendCommon.Supervisor]
    Supervisor.start_link(children, opts)

  end
end
