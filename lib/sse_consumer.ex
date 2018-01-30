defmodule SSEConsumer do
  require Logger
  use GenServer

  defmodule Request do
    @enforce_keys ~w(method url body headers)a
    defstruct @enforce_keys
  end

  defmodule State do
    @moduledoc false
    @enforce_keys ~w(recipient request conn_id remaining_stream)a
    defstruct @enforce_keys

    def new(recipient, request = %SSEConsumer.Request{}) when is_pid(recipient) do
      %__MODULE__{
        recipient: recipient,
        request: request,
        remaining_stream: "",
        conn_id: nil
      }
    end


    def set_connection(%__MODULE__{conn_id: current_conn_id} = state, new_conn_id)
    when new_conn_id != nil and is_nil(current_conn_id) do
      %{state | conn_id: new_conn_id}
    end
  end

  #===========================================================================
  # Public API
  #===========================================================================

  def stream_to(recipient, request, options), do: start_link(recipient, request, options)

  def start_link(recipient, request = %Request{}, options) do
    initial_state = State.new(recipient, request)
    GenServer.start_link(__MODULE__, initial_state, options)
  end

  #===========================================================================
  # Callbacks
  #===========================================================================

  @impl GenServer
  def init(state) do
    send(self(), :connect)
    {:ok, state}
  end


  @impl GenServer
  def handle_info(:connect, state = %State{}) do
    %Request{method: method, url: url, body: body, headers: headers} = state.request
    Logger.info("SSEConsumer connecting to TODO")
    case HTTPoison.request(method, url, body, headers, stream_opts()) do
      {:ok, %{id: conn_id}} ->
        state = State.set_connection(state, conn_id)
        receive do
          %HTTPoison.AsyncStatus{id: ^conn_id, code: 200} ->
            receive do
              %HTTPoison.AsyncHeaders{id: ^conn_id, headers: _} ->
                Logger.info("SSEConsumer connected to `#{url}`")
                {:noreply, state}
              after
                100 ->
                  Logger.warn("SSEConsumer timed out waiting for the headers")
                  disconnect_and_die(state)
            end
          %HTTPoison.AsyncStatus{id: ^conn_id, code: 400} ->
            receive do
              %HTTPoison.AsyncHeaders{headers: _} ->
                Logger.warn("SSEConsumer received HTTP 400")
                disconnect_and_die(state)
            end
          after
            2_000 ->
              Logger.warn("SSEConsumer timed out waiting for a response")
              disconnect_and_die(state)
        end
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warn("SSEConsumer failed to connect. reason: `#{reason}`")
        disconnect_and_die(state)
    end
  end

  #---------------------------------------------------------------------------
  # Handling HTTPoison messages
  #---------------------------------------------------------------------------

  def handle_info(%HTTPoison.AsyncChunk{chunk: ""}, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(%HTTPoison.AsyncEnd{}, %State{} = state) do
    disconnect_and_die(state)
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk}, %State{} = state) do
    chunk = state.remaining_stream <> chunk
    case ServerSentEvent.parse_all(chunk) do
      {:ok, {events, remaining_stream}} ->
        handle_events(events, state)
        {:noreply, %{state | remaining_stream: remaining_stream}}
      {:error, _reason} ->
        disconnect_and_die(state)
    end
  end

  def handle_info(%HTTPoison.Error{reason: reason}, %State{} = state) do
    Logger.warn("SSE Consumer streaming error; #{inspect(reason)}")
    disconnect_and_die(state)
  end

  def handle_info(info, state) do
    # If connection is established after timeout we need to drop messages streamed to process via HTTPoison
    Logger.warn("SSE Consumer: unexpected info message: #{inspect info}")
    {:noreply, state}
  end

  #===========================================================================
  # Utility functions
  #===========================================================================

  defp handle_events(events, state) do
    # TODO chunk the events
    message = {:sse, self(), events}
    send(state.recipient, message)
  end


  defp stream_opts, do: [stream_to: self(), timeout: 50_000, recv_timeout: 50_000]


  # TODO: add an optional argument of reason to be sent to the recipient
  defp disconnect_and_die(state = %State{conn_id: conn_id}) do
    send(state.recipient, {:sse_disconnected, self(), :reason}) #TODO reason
    if conn_id != nil do
      # it shouldn't be a problem if this gets called more than once or on an invalid id
      disconnect_httpoison(conn_id)
    end
    {:stop, :normal, state}
  end


  defp disconnect_httpoison(id) do
    :hackney.stop_async(id)
  end

end
