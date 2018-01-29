defmodule Curl.LoggerTest do
  use ExUnit.Case, async: false # only because we only reconfigure log level for one test
  import ExUnit.CaptureIO
  require Logger

  setup_all do
    Logger.configure_backend(Curl.Logger, service: "backend-common-test")
  end

  setup do
    on_exit(fn ->
      :ok = Logger.configure_backend(Curl.Logger, service: "backend-common-test", device: :user)
    end)
  end

  test "does not start when there is no user" do
    :ok = Logger.remove_backend(Curl.Logger)
    user = Process.whereis(:user)

    try do
      Process.unregister(:user)
      assert :gen_event.add_handler(Logger, Curl.Logger, Curl.Logger) == {:error, :ignore}
    after
      Process.register(user, :user)
    end
  after
    {:ok, _} = Logger.add_backend(Curl.Logger)
  end

  test "may use another device" do
    Logger.configure_backend(Curl.Logger, device: :standard_error)

    assert capture_io(:standard_error, fn ->
             Logger.warn("hello")
             Logger.flush()
           end) =~ "hello"
  end

  test "always JSON with timestamp, service and level" do
    assert json = capture_io(:user, fn ->
      Logger.warn("some message")
      Logger.flush()
    end)
    log = Poison.decode!(json)
    assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(log["timestamp"])
    assert log["level"] == "warn"
    assert log["service"] == "backend-common-test"
    assert log["message"] == "some message"
  end

  test "can log error" do
    assert lines = capture_io(:user, fn ->
      spawn fn ->
        raise "boom!"
      end
      Process.sleep(500)
    end)
    # NOTE: this is timing specific and in some configurations it logs more
    #       than one line. This makes it more robust.
    assert [log] = Regex.split(~r/\R/, lines, [trim: true])
    |> Enum.map(&Poison.decode!/1)
    |> Enum.filter(fn log -> String.contains?(log["message"], "boom!") end)
    assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(log["timestamp"])
    assert log["level"] == "error"
    assert log["service"] == "backend-common-test"
    assert log["message"] =~ "(RuntimeError) boom!"
  end


  test "plays well with the plug json logger" do
    conn = %Plug.Conn{}
    Logger.configure(level: :info)
    assert json = capture_io(:user, fn ->
      Plug.LoggerJSON.log(conn, :info, :erlang.timestamp())
      Logger.flush()
    end)

    assert {:ok, map} = Poison.decode(json)
    assert map["plug_method"] == "GET"
    Logger.configure(level: :warn)
  end
end
