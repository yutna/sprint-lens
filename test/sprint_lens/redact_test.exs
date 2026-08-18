defmodule SprintLens.RedactTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.Redact

  describe "sensitive?/1" do
    @tag req: ["NFR-502"]
    test "recognises user content fields" do
      assert Redact.sensitive?(:text)
      assert Redact.sensitive?(:note)
      assert Redact.sensitive?("title")
      assert Redact.sensitive?("description")
    end

    @tag req: ["NFR-502"]
    test "recognises personal data fields" do
      assert Redact.sensitive?(:email)
      assert Redact.sensitive?(:display_name)
      assert Redact.sensitive?(:avatar_url)
    end

    @tag req: ["NFR-205"]
    test "recognises secrets" do
      assert Redact.sensitive?(:secret)
      assert Redact.sensitive?(:token)
      assert Redact.sensitive?(:hashed_password)
      assert Redact.sensitive?("Authorization")
    end

    @tag req: ["NFR-502"]
    test "leaves operational fields alone" do
      refute Redact.sensitive?(:id)
      refute Redact.sensitive?(:session_id)
      refute Redact.sensitive?("status")
      refute Redact.sensitive?("duration_ms")
    end
  end

  describe "payload/1" do
    @tag req: ["NFR-502"]
    test "replaces card text with a marker and its size" do
      assert %{id: 7, text: redacted} = Redact.payload(%{id: 7, text: "we deploy too rarely"})
      assert redacted == "#{Redact.marker()} (20 bytes)"
    end

    @tag req: ["NFR-502"]
    test "keeps the key so an operator can see the field was present" do
      assert Map.has_key?(Redact.payload(%{note: "anything"}), :note)
    end

    @tag req: ["AI-017"]
    test "redacts nested structures, keeping type timing and size" do
      job = %{
        type: "session_summary",
        duration_ms: 812,
        request: %{prompt: "summarise these cards", scope: ["cards", "notes"]},
        response: %{output: %{format: "markdown", content: "## Summary"}}
      }

      redacted = Redact.payload(job)

      assert redacted.type == "session_summary"
      assert redacted.duration_ms == 812
      assert redacted.request.scope == ["cards", "notes"]
      assert redacted.request.prompt == "#{Redact.marker()} (21 bytes)"
      assert redacted.response.output == Redact.marker()
    end

    @tag req: ["NFR-502"]
    test "reports the length of a redacted list rather than its contents" do
      assert %{notes: redacted} = Redact.payload(%{notes: ["one", "two", "three"]})
      assert redacted == "#{Redact.marker()} (3 items)"
    end

    @tag req: ["NFR-502"]
    test "redacts inside lists of maps" do
      assert [%{id: 1, text: first}, %{id: 2, text: second}] =
               Redact.payload([%{id: 1, text: "aa"}, %{id: 2, text: "bbbb"}])

      assert first == "#{Redact.marker()} (2 bytes)"
      assert second == "#{Redact.marker()} (4 bytes)"
    end

    @tag req: ["NFR-502"]
    test "leaves a nil sensitive value as nil rather than claiming a redaction" do
      assert Redact.payload(%{email: nil}) == %{email: nil}
    end

    @tag req: ["NFR-502"]
    test "redacts a non-string sensitive value without inventing a size" do
      assert Redact.payload(%{secret: 12_345}) == %{secret: Redact.marker()}
    end

    @tag req: ["NFR-502"]
    test "passes scalars and structs through untouched" do
      now = ~U[2026-08-18 09:30:00Z]

      assert Redact.payload(42) == 42
      assert Redact.payload("plain") == "plain"
      assert Redact.payload(nil) == nil
      assert Redact.payload(%{at: now}) == %{at: now}
    end
  end
end
