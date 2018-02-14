defmodule BackendCommon.Vault do
  require Logger
  @version "v1"

  def token_renew(renew_token, method, credentials) do
    with {:reply, {:ok, :authenticated}, %{token: token, url: url}} <-
            Vaultex.Auth.handle(method, credentials, %{url: url}),
         {:ok, _} <- do_token_renew(url, renew_token, token)
    do
      Logger.info("Token renewed")
    else
      error ->
        Logger.error("Token renewing result: #{inspect error}")
    end
  end

  def do_token_renew(url, renew_token, token) do
    :post
    |> request("#{url}auth/token/renew/#{renew_token}", %{}, [{"X-Vault-Token", token}])
    |> handle_response(url)
  end

  defp handle_response({:ok, response}, _url) do
    case response.status_code do
      204 ->
        :ok
      _ ->
        case response.body |> Poison.Parser.parse! do
          %{"data" => data} -> {:ok, data}
          %{"errors" => []} -> {:error, ["Key not found"]}
          %{"errors" => messages} -> {:error, messages}
        end
    end
  end

  defp handle_response({_, %HTTPoison.Error{reason: reason}}, url) do
      {:reply, {:error, ["Bad response from vault [#{url}]", "#{reason}"]}}
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
