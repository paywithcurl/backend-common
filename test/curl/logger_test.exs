defmodule Curl.LoggerTest do
  use ExUnit.Case, async: false # only because we only reconfigure log level for one test
  import ExUnit.CaptureIO
  require Logger

  setup_all do
    Application.put_env(:logger, :service, "backend-common-test")
    :ok
  end

  test "always JSON with timestamp, service and level" do
    assert json = capture_io(:user, fn ->
      Logger.warn("some message")
      Logger.flush()
    end)
    log = Poison.decode!(json)
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

    assert {:ok, map1} = Poison.decode(json)

    map2 = map1["message"]
    assert map2["method"] == "GET"
    assert map1["module"] == "Elixir.Plug.LoggerJSON"
    Logger.configure(level: :warn)
  end

  test "sanitizing metadata" do
    case Curl.Logger.format(:info, "message", :timestamp, pid: self(), ref: make_ref(), other: "other") do
      "could not format "<> _ ->
        flunk("format failer")
      _ ->
        :ok
    end
  end
end
