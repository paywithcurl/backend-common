defmodule Curl.Logger do
  def format(level, message, timestamp, metadata) do
    try do
      message
      |> to_map
      |> add_timestamp(timestamp)
      |> add_metadata(metadata)
      |> add_level(level)
      |> add_service
      |> to_json
    rescue
      _ ->
        case Poison.encode(%{message: "could not format: #{inspect message}}", level: level, metadata: inspect(metadata)}) do
          {:ok, message} -> message
          _ -> "unexpected outcome"
        end
    end

  end

  defp to_map(message) when is_binary(message) do
    case Poison.decode(message) do
      {:ok, %{} = json} -> json
      {:ok, json} -> %{message: json}
      _ -> %{message: message}
    end
  end
  defp to_map(message) when is_list(message) do
    message
    |> IO.iodata_to_binary
    |> to_map
  end

  defp add_timestamp(%{} = base, timestamp) do
    Map.put(base, :timestamp, formatted_timestamp(timestamp))
  end

  defp add_metadata(%{} = base, metadata) do
    metadata = for {key, val} <- metadata, into: %{}, do: {"_#{key}", val}
    Map.merge(base, metadata)
  end

  defp add_level(%{} = base, level) do
    Map.put(base, :level, level)
  end

  defp add_service(%{} = base) do
    service = Application.get_env(:logger, :console, []) |> Keyword.get(:service, "unknown")
    Map.put(base, :service, service)
  end

  defp formatted_timestamp({date, {hours, minutes, seconds, milliseconds}}) do
    {date, {hours, minutes, seconds}}
    |> NaiveDateTime.from_erl!({milliseconds * 1000, 3})
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp to_json(event) do
    iodata = Poison.encode_to_iodata!(event)
    [iodata | [10]]
  end

  defimpl Poison.Encoder, for: [PID, Port, Reference, Tuple, Function] do
    def encode(value, options) do
      Poison.Encoder.BitString.encode(inspect(value), options)
    end
  end
end
