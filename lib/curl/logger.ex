defmodule Curl.Logger do
    # Handle the cases where the message is an io_list
    def format(level, message, timestamp, metadata) when is_list(message) do
      message = :erlang.iolist_to_binary(message)
      format(level, message, timestamp, metadata)
    rescue
      error ->
        "could not format: #{inspect {level, message, metadata, error}}"
    end
    def format(level, message, _timestamp, metadata) when is_binary(message) do
      (metadata
      |> Enum.map(&sanitize/1)
      |> Enum.into(%{})
      |> Map.put(:level, level)
      |> Map.put(:message, message)
      |> Map.put(:service, Application.get_env(:logger, :service, "unknown"))
      |> Poison.encode!) <> "\n"
    rescue
      error ->
        "could not format: #{inspect {level, message, metadata, error}}"
    end
    def format(level, message, _timestamp, metadata) do
      "could not format: #{inspect {level, message, metadata}}"
    end

    defp sanitize({k, v}) when is_pid(v) or is_port(v) or is_reference(v) do
      {k, inspect(v)}
    end
    defp sanitize(x) do
      x
    end
  end
