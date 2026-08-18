defmodule SprintLens.LogFormatterTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.LogFormatter

  # 2026-08-18T09:30:00Z in microseconds since the epoch.
  @time 1_787_045_400_000_000

  defp format(event, config \\ %{}) do
    event
    |> LogFormatter.format(config)
    |> IO.chardata_to_string()
  end

  defp decode(event, config \\ %{}) do
    event |> format(config) |> String.trim() |> Jason.decode!()
  end

  defp event(msg, meta \\ %{}) do
    %{level: :info, msg: msg, meta: Map.merge(%{time: @time}, meta)}
  end

  describe "format/2" do
    @tag req: ["NFR-502"]
    test "emits one JSON object per line" do
      output = format(event({:string, "board mutation accepted"}))

      assert String.ends_with?(output, "\n")
      assert output |> String.split("\n", trim: true) |> length() == 1
      assert %{"message" => "board mutation accepted"} = Jason.decode!(output)
    end

    @tag req: ["NFR-502"]
    test "carries the request correlation id" do
      entry = decode(event({:string, "hi"}, %{request_id: "F9-abc123"}))

      assert entry["request_id"] == "F9-abc123"
    end

    @tag req: ["NFR-502"]
    test "records level and an ISO 8601 timestamp" do
      entry = decode(%{level: :warning, msg: {:string, "careful"}, meta: %{time: @time}})

      assert entry["level"] == "warning"
      assert entry["time"] == "2026-08-18T09:30:00.000000Z"
    end

    @tag req: ["NFR-502"]
    test "omits the timestamp when the event carries none" do
      entry = decode(%{level: :info, msg: {:string, "no clock"}, meta: %{}})

      assert entry["time"] == nil
    end

    @tag req: ["NFR-502"]
    test "renders format-and-args messages" do
      entry = decode(event({~c"cards=~b in ~ts", [12, "brainstorm"]}))

      assert entry["message"] == "cards=12 in brainstorm"
    end

    @tag req: ["NFR-502"]
    test "renders report messages" do
      entry = decode(event({:report, %{outcome: :ok}}))

      assert entry["message"] =~ "outcome"
    end

    @tag req: ["NFR-502"]
    test "renders keyword-list reports" do
      entry = decode(event({:report, [outcome: :ok]}))

      assert entry["message"] =~ "outcome"
    end

    @tag req: ["NFR-502"]
    test "drops noisy internal metadata" do
      entry = decode(event({:string, "x"}, %{pid: self(), gl: self(), domain: [:elixir]}))

      refute Map.has_key?(entry, "pid")
      refute Map.has_key?(entry, "gl")
      refute Map.has_key?(entry, "domain")
    end

    @tag req: ["NFR-502"]
    test "keeps only the configured metadata keys when a list is given" do
      entry =
        decode(
          event({:string, "x"}, %{request_id: "r1", user_id: 4, extra: "drop me"}),
          %{metadata: [:request_id, :user_id]}
        )

      assert entry["request_id"] == "r1"
      assert entry["user_id"] == 4
      refute Map.has_key?(entry, "extra")
    end

    @tag req: ["NFR-502"]
    test "renders every metadata value type as JSON" do
      entry =
        decode(
          event({:string, "x"}, %{
            count: 3,
            ok: true,
            outcome: :accepted,
            missing: nil,
            scope: ["cards", :notes],
            nested: %{phase: :vote},
            at: ~U[2026-08-18 09:30:00Z],
            ref: make_ref()
          })
        )

      assert entry["count"] == 3
      assert entry["ok"] == true
      assert entry["outcome"] == "accepted"
      assert entry["missing"] == nil
      assert entry["scope"] == ["cards", "notes"]
      assert entry["nested"] == %{"phase" => "vote"}
      assert entry["at"] =~ "2026-08-18"
      assert entry["ref"] =~ "#Reference"
    end

    @tag req: ["NFR-502"]
    test "never takes the logger handler down when an event cannot be rendered" do
      output = format(%{level: :info, msg: :not_a_valid_message, meta: %{time: @time}})

      assert output =~ "\"level\":\"error\""
      assert String.ends_with?(output, "\n")
    end
  end
end
