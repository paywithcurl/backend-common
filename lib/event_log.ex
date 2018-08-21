defmodule EventLog.Consumer do
  @callback init(Map) :: no_return()
  @callback handle_event(Map, Map) :: Map
end

defmodule EventLog do
  require Logger
  use GenServer

  @enforce_keys [
    :source,
    :offset,
    :remaining_stream,
    :sse_consumer_pid,
    :keypair,
    :service,
    :consumer
  ]

  defstruct @enforce_keys

  def start_link(options) do
    source_url = Keyword.fetch!(options, :source_url)
    keypair = Keyword.fetch!(options, :keypair)
    service = Keyword.fetch!(options, :service)
    consumer = Keyword.fetch!(options, :consumer)

    state = %__MODULE__{
      source: source_url,
      keypair: keypair,
      service: service,
      consumer: consumer,
      # -1 means stream only the latest events, 0 would be from the beginning
      offset: -1,
      remaining_stream: "",
      sse_consumer_pid: nil
    }

    GenServer.start_link(__MODULE__, state, options)
  end

  @impl GenServer
  def init(%__MODULE__{consumer: consumer} = state) do
    consumer.init(state)
    send(self(), :connect)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:sse, _from, events}, _from_consumer, %__MODULE__{consumer: consumer} = state) do
    state = Enum.reduce(events, state, &consumer.handle_event/2)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:connect, %__MODULE__{} = state) do
    connect(state)
  end

  @impl GenServer
  def handle_info({:sse_disconnected, _from, _reason}, state) do
    Process.send_after(self(), :connect, 1_000)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(info, state) do
    Logger.warn("Event Log: unexpected info message: #{inspect(info)}")
    {:noreply, state}
  end

  defp connect(%__MODULE__{} = state) do
    Logger.info("Event Log Connecting to `#{__MODULE__}` `#{state.source}`")

    request = %SSEConsumer.Request{
      method: :get,
      url: state.source,
      body: "",
      headers: sign_headers(state)
    }

    {:ok, pid} = SSEConsumer.stream_to(self(), request, [])
    {:noreply, %{state | sse_consumer_pid: pid}}
  end

  def sign_headers(%__MODULE__{offset: offset, service: service, keypair: keypair}) do
    SignEx.HTTP.sign(
      %{
        method: :GET,
        path: "/events",
        query_string: "",
        headers: [
          "last-event-id": offset,
          "x-timestamp": DateTime.utc_now() |> DateTime.to_unix(),
          "x-service": service
        ],
        body: ""
      },
      keypair
    )
    |> Map.get(:headers)
  end
end
