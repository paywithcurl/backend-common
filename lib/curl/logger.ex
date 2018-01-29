defmodule Curl.Logger do
  @moduledoc ~S"""
  A backend for the Elixir `Logger` that logs JSON for Curl.
  Modify from `Logger.Backends.Console`

  ## Usage
  To use `Curl.Logger`:
      config :logger, backends: [Curl.Logger]

      config :logger, Curl.Logger,
        service: "service-name"
  """

  @behaviour :gen_event

  defstruct buffer: [],
            buffer_size: 0,
            device: nil,
            level: nil,
            service: nil,
            max_buffer: nil,
            metadata: nil,
            output: nil,
            ref: nil

  def init(__MODULE__) do
    config = Application.get_env(:logger, __MODULE__, [])
    Keyword.fetch!(config, :service)
    device = Keyword.get(config, :device, :user)

    if Process.whereis(device) do
      {:ok, init(config, %__MODULE__{})}
    else
      {:error, :ignore}
    end
  end

  def init({__MODULE__, opts}) when is_list(opts) do
    config = Keyword.merge(Application.get_env(:logger, __MODULE__), opts)
    {:ok, init(config, %__MODULE__{})}
  end

  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(options, state)}
  end

  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    %{level: log_level, ref: ref, buffer_size: buffer_size, max_buffer: max_buffer} = state

    cond do
      not meet_level?(level, log_level) ->
        {:ok, state}

      is_nil(ref) ->
        {:ok, log_event(level, msg, ts, md, state)}

      buffer_size < max_buffer ->
        {:ok, buffer_event(level, msg, ts, md, state)}

      buffer_size === max_buffer ->
        state = buffer_event(level, msg, ts, md, state)
        {:ok, await_io(state)}
    end
  end

  def handle_event(:flush, state) do
    {:ok, flush(state)}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def handle_info({:io_reply, ref, msg}, %{ref: ref} = state) do
    {:ok, handle_io_reply(msg, state)}
  end

  def handle_info({:DOWN, ref, _, pid, reason}, %{ref: ref}) do
    raise "device #{inspect(pid)} exited: " <> Exception.format_exit(reason)
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  ## Helpers

  defp meet_level?(_lvl, nil), do: true

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  defp configure(options, state) do
    config = Keyword.merge(Application.get_env(:logger, __MODULE__), options)
    Application.put_env(:logger, __MODULE__, config)
    init(config, state)
  end

  defp init(config, state) do
    level = Keyword.get(config, :level)
    service = Keyword.get(config, :service)
    device = Keyword.get(config, :device, :user)
    metadata = Keyword.get(config, :metadata, []) |> configure_metadata()
    max_buffer = Keyword.get(config, :max_buffer, 32)

    %{
      state
      | metadata: metadata,
        level: level,
        service: service,
        device: device,
        max_buffer: max_buffer
    }
  end

  defp configure_metadata(:all), do: :all
  defp configure_metadata(metadata), do: Enum.reverse(metadata)

  defp log_event(level, msg, ts, md, %{device: device} = state) do
    output = format_event(level, msg, ts, md, state)
    %{state | ref: async_io(device, output), output: output}
  end

  defp buffer_event(level, msg, ts, md, state) do
    %{buffer: buffer, buffer_size: buffer_size} = state
    buffer = [buffer | format_event(level, msg, ts, md, state)]
    %{state | buffer: buffer, buffer_size: buffer_size + 1}
  end

  defp async_io(name, output) when is_atom(name) do
    case Process.whereis(name) do
      device when is_pid(device) ->
        async_io(device, output)

      nil ->
        raise "no device registered with the name #{inspect(name)}"
    end
  end

  defp async_io(device, output) when is_pid(device) do
    ref = Process.monitor(device)
    send(device, {:io_request, self(), ref, {:put_chars, :unicode, output}})
    ref
  end

  defp await_io(%{ref: nil} = state), do: state

  defp await_io(%{ref: ref} = state) do
    receive do
      {:io_reply, ^ref, :ok} ->
        handle_io_reply(:ok, state)

      {:io_reply, ^ref, error} ->
        handle_io_reply(error, state)
        |> await_io()

      {:DOWN, ^ref, _, pid, reason} ->
        raise "device #{inspect(pid)} exited: " <> Exception.format_exit(reason)
    end
  end

  defp format_event(level, msg, ts, md, %{service: service}) do
    %{}
    |> format_message(msg)
    |> format_timestamp(ts)
    |> format_metadata(md)
    |> format_default(level, service)
    |> fixup_plug_logger_json()
    |> to_json
  end

  defp format_message(base, msg) when is_binary(msg) do
    Map.put(base, :message, msg)
  end
  defp format_message(base, msg) when is_list(msg) do
    format_message(base, IO.iodata_to_binary(msg))
  end

  defp format_timestamp(base, ts) do
    Map.put(base, :timestamp, formatted_timestamp(ts))
  end

  defp format_metadata(base, md) do
    Map.merge(base, Enum.into(md, %{}))
  end

  defp format_default(base, level, service) do
    Map.merge(base, %{level: level, service: service})
  end

  defp fixup_plug_logger_json(event) do
    with %{application: :plug_logger_json, module: Plug.LoggerJSON} <- event,
         %{message: json_message} <- event,
         {:ok, decoded} <- Poison.decode(json_message)
    do
      namespaced = decoded
      |> Enum.map(fn {k, v} -> {"plug_" <> k, v} end)
      |> Map.new()

      Map.merge(event, namespaced)
      |> Map.put(:message, "see plug_* fields")
    else
      _ -> event
    end
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

  defp log_buffer(%{buffer_size: 0, buffer: []} = state), do: state

  defp log_buffer(state) do
    %{device: device, buffer: buffer} = state
    %{state | ref: async_io(device, buffer), buffer: [], buffer_size: 0, output: buffer}
  end

  defp handle_io_reply(:ok, %{ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    log_buffer(%{state | ref: nil, output: nil})
  end

  defp handle_io_reply({:error, {:put_chars, :unicode, _} = error}, state) do
    retry_log(error, state)
  end

  defp handle_io_reply({:error, :put_chars}, %{output: output} = state) do
    retry_log({:put_chars, :unicode, output}, state)
  end

  defp handle_io_reply({:error, error}, _) do
    raise "failure while logging Curl messages: " <> inspect(error)
  end

  defp retry_log(error, %{device: device, ref: ref, output: dirty} = state) do
    Process.demonitor(ref, [:flush])

    case :unicode.characters_to_binary(dirty) do
      {_, good, bad} ->
        clean = [good | Logger.Formatter.prune(bad)]
        %{state | ref: async_io(device, clean), output: clean}

      _ ->
        # A well behaved IO device should not error on good data
        raise "failure while logging Curl messages: " <> inspect(error)
    end
  end

  defp flush(%{ref: nil} = state), do: state

  defp flush(state) do
    state
    |> await_io()
    |> flush()
  end
end
defimpl Poison.Encoder, for: [PID, Port, Reference, Tuple, Function] do
  def encode(value, options) do
    Poison.Encoder.BitString.encode(inspect(value), options)
  end
end
