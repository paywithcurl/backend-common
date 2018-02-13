defmodule BackendCommon.Vault do
  use GenServer
  require Logger
  @version "v1"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def init(state) do
    {:ok, Map.merge(state, %{url: url()})}
  end

  def auth(method, credentials) do
    GenServer.call(__MODULE__, {:auth, method, credentials})
  end

  def token_renew(token) do
    case GenServer.call(__MODULE__, {:tokenrenew, token}) do
      :ok -> Logger.info("Token renewed")
      {:error, error} -> Logger.error("Token renewing result: #{inspect error}")
    end
  end

  def token_renew(token, method, credentials) do
    case token_renew(token) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, _} ->
        with {:ok, :authenticated} <- auth(method, credentials) do
          token_renew(token)
        end
    end
  end

  def handle_call({:auth, method, credentials}, _from, state) do
    Vaultex.Auth.handle(method, credentials, state)
  end

  def handle_call({:tokenrenew, renew_token}, _from, %{token: token} = state) do
    :post
    |> request("#{state.url}auth/token/renew/#{renew_token}", %{}, [{"X-Vault-Token", token}])
    |> handle_response(state)
  end

  def handle_call(_, _from, state) do
    {:reply, {:error, ["Not Authenticated"]}, state}
  end

  defp handle_response({:ok, response}, state) do
    case response.status_code do
      204 ->
        :ok
      _ ->
        case response.body |> Poison.Parser.parse! do
          %{"data" => data} -> {:reply, {:ok, data}, state}
          %{"errors" => []} -> {:reply, {:error, ["Key not found"]}, state}
          %{"errors" => messages} -> {:reply, {:error, messages}, state}
        end
    end
  end

  defp handle_response({_, %HTTPoison.Error{reason: reason}}, state) do
      {:reply, {:error, ["Bad response from vault [#{state.url}]", "#{reason}"]}, state}
  end

  defp request(method, url, body, headers) do
    Vaultex.RedirectableRequests.request(method, url, body, headers)
  end

  defp url do
    "#{scheme()}://#{host()}:#{port()}/#{@version}/"
  end

  defp host do
    parsed_vault_addr().host || get_env(:host)
  end

  defp port do
    parsed_vault_addr().port || get_env(:port)
  end

  defp scheme do
    parsed_vault_addr().scheme || get_env(:scheme)
  end

  defp parsed_vault_addr do
    get_env(:vault_addr) |> to_string |> URI.parse
  end

  defp get_env(:host) do
    System.get_env("VAULT_HOST") || Application.get_env(:vaultex, :host) || "localhost"
  end

  defp get_env(:port) do
      System.get_env("VAULT_PORT") || Application.get_env(:vaultex, :port) || 8200
  end

  defp get_env(:scheme) do
      System.get_env("VAULT_SCHEME") || Application.get_env(:vaultex, :scheme) || "http"
  end

  defp get_env(:vault_addr) do
    Application.get_env(:vaultex, :vault_addr) || System.get_env("VAULT_ADDR")
  end
end

