defmodule BackendCommon.Plaintext do
  def decrypt_map(%{ciphertext: plaintext, encrypted_data_key: _}) do
    try do
      {:ok, _decrypted} = Poison.decode(plaintext)
    rescue
      _ ->
        {:error, "Could not decrypt #{inspect plaintext}"}
    end
  end

  def encrypt_map(%{} = secret, key_id) when is_binary(key_id) do
    with {:ok, plaintext} <- Poison.encode(secret)
    do
      {:ok, %{encrypted_data_key: "PLAINTEXT", ciphertext: plaintext}}
    else
      _ ->
        {:error, "Could not encrypt #{inspect secret} with key #{key_id}"}
    end
  end
end
