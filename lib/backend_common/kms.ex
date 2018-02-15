defmodule BackendCommon.KMS do

  def decrypt_map(%{ciphertext: ciphertext, encrypted_data_key: encrypted_data_key} = secret) do
    response = ExAws.KMS.decrypt(encrypted_data_key) |> ExAws.request
    try do
      {:ok, %{"KeyId" => _, "Plaintext" => data_key}} =
        ExAws.KMS.decrypt(encrypted_data_key) |> ExAws.request
      <<iv::binary-16, ciphertext::binary>> = :base64.decode(ciphertext)
      state = :crypto.stream_init(:aes_ctr,  :base64.decode(data_key), iv)
      {_state, plaintext} = :crypto.stream_decrypt(state, ciphertext)
      {:ok, decrypted} = Poison.decode(plaintext)
    rescue
      _ ->
        {:error, "Could not decrypt #{inspect secret}"}
    end
  end

  def encrypt_map(%{} = secret, key_id) when is_binary(key_id) do
    with {:ok, plaintext} <- Poison.encode(secret),
         {:ok, %{"CiphertextBlob" => encrypted_data_key, "KeyId" => _, "Plaintext" => data_key}} <-
           ExAws.KMS.generate_data_key(key_id) |> ExAws.request,
         iv = :crypto.strong_rand_bytes(16),
         state = :crypto.stream_init(:aes_ctr, :base64.decode(data_key), iv),
         {_state, ciphertext} = :crypto.stream_encrypt(state, to_string(plaintext))
    do
      {:ok, %{encrypted_data_key: encrypted_data_key, ciphertext: :base64.encode(iv <> ciphertext)}}
    else
      _ ->
        {:error, "Could not encrypt #{inspect secret} with key #{key_id}"}
    end
  end
end
