defmodule SSEConsumer do
  require Logger
  use GenServer

  defmodule Request do
    @enforce_keys ~w(method url body headers)a
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  defmodule State do
    @moduledoc false
    @enforce_keys ~w(recipient request async_ref remaining_stream)a
    defstruct @enforce_keys

    def new(recipient, request = %SSEConsumer.Request{}) when is_pid(recipient) do
      %__MODULE__{
        recipient: recipient,
        request: request,
        remaining_stream: "",
        async_ref: nil
      }
    end

    def set_connection(%__MODULE__{async_ref: current_conn_id} = state, new_conn_id)
        when new_conn_id != nil and is_nil(current_conn_id) do
      %{state | async_ref: new_conn_id}
    end
  end

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  See `SSEConsumer.start_link/3`
  """
  def stream_to(recipient, request, options), do: start_link(recipient, request, options)

  @doc """
  Starts the `SSEConsumer` and links it to the current process. The consumer
  will perform the specified `request`, keep the connection open, and
  send the `recipient` the already parsed server side events.

  Once started, the `SSEConsumer` will send the `recipient` the following messages:

  - `{:sse, own_pid, events}` where `events` is a list of `%ServerSentEvent{}`,
  whenever it receives events from the stream

  - `{:sse_disconnected, own_pid, reason}` when it gets disconnected. It will
  only send this one once and terminate normally afterwards. It will will not
  attemt to reconnect.
  If the `reason` is anything but `:finished` it means the request didn't terminate
  normally.
  """
  @spec start_link(pid(), SSEConsumer.Request.t(), Keyword.t()) :: {:ok, pid()}
  def start_link(recipient, request = %Request{}, options) do
    initial_state = State.new(recipient, request)
    GenServer.start_link(__MODULE__, initial_state, options)
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================

  @impl GenServer
  def init(state) do
    send(self(), :connect)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:connect, state = %State{}) do
    %Request{method: method, url: url, body: body, headers: headers} = state.request
    Logger.info("SSEConsumer connecting to `#{url}`")

    case HTTPoison.request(method, url, body, headers, stream_opts()) do
      {:ok, async_ref = %{id: async_ref_id}} ->
        state = State.set_connection(state, async_ref)

        receive do
          %HTTPoison.AsyncStatus{id: ^async_ref_id, code: 200} ->
            {:ok, _} = HTTPoison.stream_next(state.async_ref)

            receive do
              %HTTPoison.AsyncHeaders{id: ^async_ref_id, headers: _} ->
                {:ok, _} = HTTPoison.stream_next(state.async_ref)
                Logger.info("SSEConsumer connected to `#{url}`")
                {:noreply, state}
            after
              100 ->
                Logger.warn("SSEConsumer timed out waiting for the headers")
                disconnect_and_die(state, :headers_timeout)
            end

          %HTTPoison.AsyncStatus{id: ^async_ref_id, code: 400} ->
            {:ok, _} = HTTPoison.stream_next(state.async_ref)

            receive do
              %HTTPoison.AsyncHeaders{headers: _} ->
                Logger.warn("SSEConsumer received HTTP 400")
                disconnect_and_die(state, :http_400)
            end
        after
          2_000 ->
            Logger.warn("SSEConsumer timed out waiting for a response")
            disconnect_and_die(state, :timeout)
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warn("SSEConsumer failed to connect. reason: `#{reason}`")
        disconnect_and_die(state, {:httpoison, reason})
    end
  end

  # ---------------------------------------------------------------------------
  # Handling HTTPoison messages
  # ---------------------------------------------------------------------------

  def handle_info(%HTTPoison.AsyncChunk{chunk: ""}, %State{} = state) do
    {:ok, _} = HTTPoison.stream_next(state.async_ref)
    {:noreply, state}
  end

  def handle_info(%HTTPoison.AsyncEnd{}, %State{} = state) do
    disconnect_and_die(state, :finished)
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk}, %State{} = state) do
    chunk = state.remaining_stream <> chunk

    case ServerSentEvent.parse_all(chunk) do
      {:ok, {events, remaining_stream}} ->
        handle_events(events, state)
        {:ok, _} = HTTPoison.stream_next(state.async_ref)
        {:noreply, %{state | remaining_stream: remaining_stream}}

      {:error, reason} ->
        Logger.warn("SSE Consumer failed to parse chunk `#{chunk}` because of `#{reason}`")
        disconnect_and_die(state, {:sse_parse, reason})
    end
  end

  def handle_info(%HTTPoison.Error{reason: reason}, %State{} = state) do
    Logger.warn("SSE Consumer streaming error; #{inspect(reason)}")
    disconnect_and_die(state, {:httpoison, reason})
  end

  def handle_info(info, state) do
    # If connection is established after timeout we need to drop messages streamed to process via HTTPoison
    Logger.warn("SSE Consumer: unexpected info message: #{inspect(info)}")
    {:noreply, state}
  end

  # ===========================================================================
  # Utility functions
  # ===========================================================================

  defp handle_events(events, state) do
    message = {:sse, self(), events}
    GenServer.call(state.recipient, message)
  end

  defp stream_opts, do: [stream_to: self(), timeout: 50_000, recv_timeout: 50_000, async: :once]

  defp disconnect_and_die(state = %State{async_ref: async_ref}, reason) do
    send(state.recipient, {:sse_disconnected, self(), reason})

    if async_ref != nil do
      # it shouldn't be a problem if this gets called more than once or on an invalid id
      disconnect_httpoison(async_ref)
    end

    {:stop, :normal, state}
  end

  defp disconnect_httpoison(id) do
    :hackney.stop_async(id)
  end
end
