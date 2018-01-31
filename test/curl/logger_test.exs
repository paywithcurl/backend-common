defmodule Curl.LoggerTest do
  use ExUnit.Case, async: false # only because we only reconfigure log level for one test
  import ExUnit.CaptureIO
  require Logger

  setup_all do
    conf = Application.get_env(:logger, :console)
    conf = Keyword.put(conf, :service, "backend-common-test")
    Application.put_env(:logger, :console, conf)
    :ok
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
    assert map["method"] == "GET"
    assert map["_module"] == "Elixir.Plug.LoggerJSON"
    Logger.configure(level: :warn)
  end
end
