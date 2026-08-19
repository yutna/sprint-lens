defmodule SprintLens.ExportsTest do
  @moduledoc """
  Taking a retrospective out of the app (FR-701, FR-702, FR-703).

  These are string transformations over a recap map, so they need no
  database. The cases worth the most attention are the ones a spreadsheet or
  a parser will choke on: a card containing a comma, a quote, a newline and
  Thai text all at once, and a card that starts with an equals sign.
  """

  use SprintLens.UnitCase, async: true

  alias SprintLens.Actions.ActionItem
  alias SprintLens.Exports
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.Column
  alias SprintLens.Retro.DiscussionNote
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Topic

  @at ~U[2026-08-01 09:00:00Z]

  defp user(name), do: %SprintLens.Accounts.User{id: 1, display_name: name}

  defp card(id, column_id, text, author \\ nil) do
    %Card{id: id, column_id: column_id, text: text, position: 0, inserted_at: @at, author: author}
  end

  defp recap(overrides \\ %{}) do
    session = %Session{
      id: 7,
      title: "Sprint 12",
      team_id: 3,
      state: "closed",
      closed_at: @at,
      vote_budget: 5
    }

    columns = [
      %Column{id: 1, name: "Went well", position: 0},
      %Column{id: 2, name: "To improve", position: 1}
    ]

    cards = [card(10, 1, "Deploys are fast", user("Ploy")), card(11, 2, "Builds are slow")]

    base = %{
      session: session,
      columns: columns,
      cards: cards,
      topics: [%{Topic.from_card(hd(cards)) | votes: 3, note: "Keep doing this"}],
      notes: [%DiscussionNote{id: 5, card_id: 10, body: "Keep doing this"}],
      actions: [
        %ActionItem{
          id: 20,
          title: "Write the runbook",
          description: "Ask the SRE team",
          status: "open",
          due_date: @at,
          inserted_at: @at,
          assignee: user("Lek")
        }
      ],
      mood: %{kind: :checkin_mood, count: 2, average: 4.0, distribution: %{}, words: []},
      roti: %{kind: :roti, count: 1, average: 5.0, distribution: %{}, words: []},
      participant_count: 2
    }

    Map.merge(base, overrides)
  end

  defp empty_recap do
    recap(%{
      cards: [],
      topics: [],
      notes: [],
      actions: [],
      mood: %{kind: :checkin_mood, count: 0, average: nil, distribution: %{}, words: []},
      roti: %{kind: :roti, count: 0, average: nil, distribution: %{}, words: []}
    })
  end

  describe "choosing a format" do
    @tag req: ["FR-701"]
    test "markdown is what you get if you do not say" do
      assert Exports.parse_format(nil) == {:ok, :markdown}
      assert Exports.parse_format("md") == {:ok, :markdown}
      assert Exports.parse_format("markdown") == {:ok, :markdown}
    end

    @tag req: ["FR-702", "FR-703"]
    test "and the other two are named" do
      assert Exports.parse_format("csv") == {:ok, :csv}
      assert Exports.parse_format("json") == {:ok, :json}
      assert Exports.formats() == [:markdown, :csv, :json]
    end

    @tag req: ["FR-701"]
    test "anything else is not a format" do
      assert Exports.parse_format("pdf") == :error
      assert Exports.parse_format("") == :error
    end

    @tag req: ["FR-702"]
    test "a CSV is of the cards unless the actions are asked for" do
      assert Exports.parse_subject(nil) == {:ok, :cards}
      assert Exports.parse_subject("cards") == {:ok, :cards}
      assert Exports.parse_subject("actions") == {:ok, :actions}
      assert Exports.parse_subject("votes") == :error
    end
  end

  describe "markdown (FR-701)" do
    @tag req: ["FR-701"]
    test "reads as a document about the session" do
      body = Exports.markdown(recap())

      assert body =~ "# Sprint 12"
      assert body =~ "- Took part: 2"
      assert body =~ "- Mood: 4.0"
      assert body =~ "### Went well"
      assert body =~ "- Deploys are fast — Ploy"
      assert body =~ "### Deploys are fast (3 vote(s))"
      assert body =~ "> Keep doing this"
      assert body =~ "- Write the runbook · status: open · owner: Lek"
      assert String.ends_with?(body, "\n")
    end

    @tag req: ["FR-210", "FR-701"]
    test "an anonymous session's export names nobody, and says why" do
      body = Exports.markdown(recap(%{session: %{recap().session | is_anonymous: true}}))

      assert body =~ "Anonymous: authorship was not recorded"
      refute body =~ "Ploy"
    end

    @tag req: ["FR-701"]
    test "a card with a newline in it stays on one line" do
      broken = card(12, 1, "First line\n  second line")
      body = Exports.markdown(recap(%{cards: [broken]}))

      assert body =~ "- First line second line"
      refute body =~ "- First line\n  second"
    end

    @tag req: ["FR-917", "FR-701"]
    test "a session with nothing in it says so rather than showing blank headings" do
      body = Exports.markdown(empty_recap())

      assert body =~ "_Nothing in this column._"
      assert body =~ "_Nothing was discussed._"
      assert body =~ "_Nothing was agreed._"
      assert body =~ "- Mood: —"
    end

    @tag req: ["FR-701"]
    test "a cluster lists the cards it holds" do
      cards = [card(10, 1, "Deploys are slow"), card(11, 1, "Flaky CI")]

      group = %SprintLens.Retro.CardGroup{
        id: 4,
        label: "Tooling",
        cards: cards,
        inserted_at: @at
      }

      body =
        Exports.markdown(recap(%{cards: cards, topics: [%{Topic.from_group(group) | votes: 2}]}))

      assert body =~ "### Tooling (2 vote(s))"
      assert body =~ "- Flaky CI"
    end
  end

  describe "CSV (FR-702)" do
    @tag req: ["FR-702"]
    test "the cards, one row each, under a header" do
      body = Exports.csv(recap(), :cards)

      assert [header, first, second] = String.split(String.trim_trailing(body), "\r\n")
      assert header == "id,column,text,author,created_at"
      assert first == "10,Went well,Deploys are fast,Ploy,2026-08-01T09:00:00Z"
      assert second =~ "Builds are slow"
    end

    @tag req: ["FR-702"]
    test "the action items are their own file" do
      body = Exports.csv(recap(), :actions)

      assert [header, row] = String.split(String.trim_trailing(body), "\r\n")
      assert header == "id,title,description,status,assignee,due_date,created_at"
      assert row =~ "Write the runbook"
      assert row =~ "Lek"
    end

    @tag req: ["FR-702"]
    test "a card with a comma, a quote, a newline and Thai text survives" do
      awkward = card(12, 1, ~s(รีวิว "ช้า", มาก\nจริง))
      body = Exports.csv(recap(%{cards: [awkward]}), :cards)

      assert body =~ ~s("รีวิว ""ช้า"", มาก\nจริง")

      # And the whole thing still parses as one header plus one record.
      assert body |> String.trim_trailing() |> parse_csv() |> length() == 2
    end

    @tag req: ["NFR-203", "FR-702"]
    test "a card that would run in a spreadsheet is neutralised" do
      formulas = [~S{=HYPERLINK("http://evil","click")}, "+1+1", "-2+3", "@SUM(A1)"]

      for formula <- formulas do
        body = Exports.csv(recap(%{cards: [card(13, 1, formula)]}), :cards)

        assert body =~ "'" <> String.slice(formula, 0, 3)
      end
    end

    @tag req: ["FR-702"]
    test "records are separated by CRLF, as RFC 4180 says" do
      body = Exports.csv(recap(), :cards)

      assert String.ends_with?(body, "\r\n")
      refute body =~ ~r/[^\r]\n[^\s]/
    end

    @tag req: ["FR-210", "FR-702"]
    test "an anonymous session leaves the author column empty" do
      body = Exports.csv(recap(%{session: %{recap().session | is_anonymous: true}}), :cards)

      refute body =~ "Ploy"
      assert body =~ "10,Went well,Deploys are fast,,"
    end

    @tag req: ["FR-917", "FR-702"]
    test "a session with nothing in it is a header and no rows" do
      assert Exports.csv(empty_recap(), :cards) == "id,column,text,author,created_at\r\n"
    end
  end

  describe "JSON (FR-703)" do
    @tag req: ["FR-703"]
    test "carries the recap plus the session's metadata" do
      body = Exports.json(recap())
      data = Jason.decode!(body)

      assert data["session"]["id"] == 7
      assert data["session"]["participant_count"] == 2
      assert data["session"]["vote_budget"] == 5
      assert data["exported_at"]
      assert length(data["columns"]) == 2
      assert [%{"text" => "Deploys are fast", "author" => "Ploy"} | _rest] = data["cards"]
      assert [%{"votes" => 3, "note" => "Keep doing this"}] = data["topics"]
      assert [%{"topic" => "card:10", "body" => "Keep doing this"}] = data["notes"]
      assert [%{"title" => "Write the runbook", "assignee" => "Lek"}] = data["actions"]
      assert data["mood"]["average"] == 4.0
    end

    @tag req: ["FR-210", "FR-703"]
    test "an anonymous session's JSON has no author field at all" do
      body = Exports.json(recap(%{session: %{recap().session | is_anonymous: true}}))
      data = Jason.decode!(body)

      refute Enum.any?(data["cards"], &Map.has_key?(&1, "author"))
      refute body =~ "Ploy"
    end

    @tag req: ["FR-703"]
    test "is pretty-printed, because a person is going to read it" do
      assert Exports.json(recap()) =~ "\n  "
    end
  end

  describe "render/3" do
    @tag req: ["FR-701"]
    test "names the file after the session" do
      assert %{filename: "sprint-12-7.md", content_type: "text/markdown" <> _} =
               Exports.render(recap(), :markdown)
    end

    @tag req: ["FR-702"]
    test "and says which CSV it is" do
      assert %{filename: "sprint-12-7.cards.csv"} = Exports.render(recap(), :csv, :cards)
      assert %{filename: "sprint-12-7.actions.csv"} = Exports.render(recap(), :csv, :actions)
    end

    @tag req: ["FR-703"]
    test "and gives JSON its own content type" do
      assert %{filename: "sprint-12-7.json", content_type: "application/json" <> _} =
               Exports.render(recap(), :json)
    end

    @tag req: ["FR-906", "FR-701"]
    test "a Thai title still makes a filename" do
      thai = %{recap().session | title: "รีโทรสปรินต์ 12"}

      assert %{filename: filename} = Exports.render(recap(%{session: thai}), :markdown)
      assert filename == "รีโทรสปรินต์-12-7.md"
    end
  end

  # A deliberately small RFC 4180 reader, so the escaping test checks the
  # output against something other than the code that produced it.
  defp parse_csv(body) do
    body
    |> String.replace("\r\n", "\n")
    |> String.to_charlist()
    |> Enum.reduce({[], [], [], false}, &parse_char/2)
    |> finish()
  end

  defp parse_char(?", {rows, row, cell, in_quotes?}), do: {rows, row, cell, not in_quotes?}
  defp parse_char(?,, {rows, row, cell, false}), do: {rows, [flush(cell) | row], [], false}

  defp parse_char(?\n, {rows, row, cell, false}),
    do: {[[flush(cell) | row] | rows], [], [], false}

  defp parse_char(char, {rows, row, cell, quotes}), do: {rows, row, [char | cell], quotes}

  defp flush(cell), do: cell |> Enum.reverse() |> List.to_string()

  defp finish({rows, [], [], _quotes}), do: Enum.reverse(rows)
  defp finish({rows, row, cell, _quotes}), do: Enum.reverse([[flush(cell) | row] | rows])
end
