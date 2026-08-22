defmodule SprintLensWeb.CoreComponentsTest do
  use SprintLens.UnitCase, async: true

  # Asserts on English copy, so it says so rather than reading the Thai
  # translation table back to itself.
  @moduletag locale: "en"

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import SprintLensWeb.CoreComponents

  alias Phoenix.HTML.FormField

  # `used?` mirrors whether the user has actually interacted with the field:
  # `Phoenix.Component.used_input?/1` looks for the field in the form's params,
  # and errors stay hidden until it is there.
  defp field(name, value, errors \\ [], used? \\ true) do
    params = if used?, do: %{to_string(name) => value}, else: %{}

    %FormField{
      id: "user_#{name}",
      name: "user[#{name}]",
      field: name,
      value: value,
      errors: errors,
      form: to_form(params, as: :user)
    }
  end

  describe "flash/1" do
    @tag req: ["FR-919"]
    test "renders an info message from the flash map" do
      html = render_component(&flash/1, kind: :info, flash: %{"info" => "Saved"})

      assert html =~ "Saved"
      assert html =~ ~s(data-tone="info")
      assert html =~ ~s(role="alert")
    end

    @tag req: ["FR-919"]
    test "renders an error message with error styling" do
      html = render_component(&flash/1, kind: :error, flash: %{"error" => "Could not save"})

      assert html =~ "Could not save"
      assert html =~ ~s(data-tone="error")
    end

    @tag req: ["FR-919"]
    test "renders nothing when there is no message" do
      assert render_component(&flash/1, kind: :info, flash: %{}) =~ ""
      refute render_component(&flash/1, kind: :info, flash: %{}) =~ "alert-info"
    end

    @tag req: ["FR-919"]
    test "renders an explicit title and inner block over the flash map" do
      html =
        render_component(&flash/1, %{
          kind: :info,
          title: "Heads up",
          inner_block: [%{inner_block: fn _, _ -> "Custom body" end, __slot__: :inner_block}]
        })

      assert html =~ "Heads up"
      assert html =~ "Custom body"
    end

    @tag req: ["FR-916"]
    test "the dismiss control is labelled for assistive technology" do
      html = render_component(&flash/1, kind: :info, flash: %{"info" => "Saved"})

      assert html =~ ~s(aria-label=)
    end
  end

  describe "button/1" do
    @tag req: ["FR-914"]
    test "renders a real button element by default" do
      html = render_component(&button/1, %{inner_block: inner("Save")})

      assert html =~ "<button"
      assert html =~ "Save"
      # The touch-target rule in the stylesheet hangs off this, not off a
      # styling class, so that it cannot be lost in a restyle (FR-904).
      assert html =~ ~s(data-slot="button")
    end

    @tag req: ["FR-914"]
    test "renders a link when given a navigation target" do
      html = render_component(&button/1, %{navigate: "/teams", inner_block: inner("Teams")})

      assert html =~ "<a"
      assert html =~ ~s(href="/teams")
    end

    @tag req: ["FR-914"]
    test "renders a link for a plain href" do
      html = render_component(&button/1, %{href: "/out", inner_block: inner("Out")})

      assert html =~ ~s(href="/out")
    end

    @tag req: ["FR-914"]
    test "renders a link for a patch target" do
      html = render_component(&button/1, %{patch: "/teams/1", inner_block: inner("Edit")})

      assert html =~ ~s(href="/teams/1")
    end

    @tag req: ["FR-914"]
    test "applies the primary variant" do
      html = render_component(&button/1, %{variant: "primary", inner_block: inner("Go")})

      assert html =~ "bg-primary"
      refute html =~ "bg-base-200"
    end

    @tag req: ["FR-914"]
    test "a caller-supplied class is added to the defaults, not swapped for them" do
      html = render_component(&button/1, %{class: "my-btn", inner_block: inner("Go")})

      assert html =~ "my-btn"
      # A caller asking for `w-full` wants a full-width button, not an
      # unstyled one — and under the old contract two of them got exactly that.
      assert html =~ "rounded-control"
    end
  end

  describe "input/1" do
    @tag req: ["FR-919"]
    test "renders a text input with a label" do
      html = render_component(&input/1, name: "title", value: "Retro", label: "Title")

      assert html =~ ~s(type="text")
      assert html =~ ~s(name="title")
      assert html =~ ~s(value="Retro")
      assert html =~ "Title"
    end

    @tag req: ["FR-919"]
    test "shows validation errors from a form field" do
      html = render_component(&input/1, field: field(:email, "", [{"can't be blank", []}]))

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
      assert html =~ ~s(aria-invalid="true")
    end

    @tag req: ["FR-919"]
    test "hides errors on a field the user has not touched yet" do
      html = render_component(&input/1, field: field(:email, "", [{"can't be blank", []}], false))

      refute html =~ "aria-invalid"
    end

    @tag req: ["FR-919"]
    test "derives id and name from the form field" do
      html = render_component(&input/1, field: field(:display_name, "Nok"))

      assert html =~ ~s(id="user_display_name")
      assert html =~ ~s(name="user[display_name]")
    end

    @tag req: ["FR-919"]
    test "names a multiple-select field as an array" do
      html =
        render_component(&input/1,
          field: field(:events, []),
          type: "select",
          multiple: true,
          options: [{"Started", "session.started"}]
        )

      assert html =~ ~s(name="user[events][]")
    end

    @tag req: ["FR-919"]
    test "renders a hidden input" do
      html = render_component(&input/1, type: "hidden", name: "token", value: "abc")

      assert html =~ ~s(type="hidden")
      assert html =~ ~s(value="abc")
    end

    @tag req: ["FR-919"]
    test "renders a checkbox with a false-valued companion so unchecking submits" do
      html =
        render_component(&input/1,
          type: "checkbox",
          name: "anon",
          value: true,
          label: "Anonymous"
        )

      assert html =~ ~s(type="checkbox")
      assert html =~ ~s(value="false")
      assert html =~ "checked"
      assert html =~ "Anonymous"
    end

    @tag req: ["FR-919"]
    test "renders an unchecked checkbox" do
      html = render_component(&input/1, type: "checkbox", name: "anon", value: false)

      refute html =~ "checked"
    end

    @tag req: ["FR-919"]
    test "renders a select with options and a prompt" do
      html =
        render_component(&input/1,
          type: "select",
          name: "language",
          value: "th",
          prompt: "Choose",
          options: [{"ไทย", "th"}, {"English", "en"}]
        )

      assert html =~ "<select"
      assert html =~ "Choose"
      assert html =~ "English"
      assert html =~ ~s(<option selected value="th">)
    end

    @tag req: ["FR-919"]
    test "renders a select error state" do
      html =
        render_component(&input/1,
          type: "select",
          name: "language",
          value: nil,
          options: [],
          errors: ["is required"]
        )

      assert html =~ ~s(aria-invalid="true")
      assert html =~ "is required"
    end

    @tag req: ["FR-301"]
    test "renders a textarea for long text" do
      html = render_component(&input/1, type: "textarea", name: "text", value: "we deploy rarely")

      assert html =~ "<textarea"
      assert html =~ "we deploy rarely"
    end

    @tag req: ["FR-301"]
    test "renders a textarea error state" do
      html =
        render_component(&input/1,
          type: "textarea",
          name: "text",
          value: "",
          errors: ["should be at most 500 character(s)"]
        )

      assert html =~ ~s(aria-invalid="true")
      assert html =~ "500"
    end

    @tag req: ["FR-919"]
    test "a caller-supplied class replaces the default input class" do
      html = render_component(&input/1, name: "n", value: "", class: "custom-input")

      assert html =~ "custom-input"
      refute html =~ "rounded-control"
    end

    @tag req: ["FR-919"]
    test "a caller-supplied error class replaces the default" do
      html =
        render_component(&input/1, name: "n", value: "", errors: ["bad"], error_class: "ring-red")

      assert html =~ "ring-red"
      # The custom class replaces the default border, not the state: a field
      # the server rejected is still announced as invalid.
      refute html =~ "border-error"
      assert html =~ ~s(aria-invalid="true")
    end
  end

  describe "header/1" do
    @tag req: ["FR-917"]
    test "renders a title" do
      html = render_component(&header/1, %{inner_block: inner("Team Alpha")})

      assert html =~ "<h1"
      assert html =~ "Team Alpha"
    end

    @tag req: ["FR-917"]
    test "renders a subtitle and actions when given" do
      html =
        render_component(&header/1, %{
          inner_block: inner("Team Alpha"),
          subtitle: inner("6 members", :subtitle),
          actions: inner("New session", :actions)
        })

      assert html =~ "6 members"
      assert html =~ "New session"
    end
  end

  describe "badge/1" do
    @tag req: ["FR-917"]
    test "says what it is and which tone it carries" do
      html = render_component(&badge/1, %{tone: "danger", inner_block: inner("Overdue")})

      assert html =~ "Overdue"
      assert html =~ ~s(data-slot="badge")
      assert html =~ ~s(data-tone="danger")
    end

    # The tinted version of this component — coloured text on a wash of the
    # same hue — reads better and fails WCAG at this size in both themes.
    # Only the pairs `contrast_test.exs` proves are allowed.
    @tag req: ["FR-913"]
    test "every tone is a contrast pair the palette test checks" do
      for tone <- ~w(neutral primary info success warning danger) do
        html = render_component(&badge/1, %{tone: tone, inner_block: inner("x")})

        assert html =~ ~s(data-tone="#{tone}")
      end
    end

    @tag req: ["FR-917"]
    test "takes an id, so a test can find the one it means" do
      html = render_component(&badge/1, %{id: "action-overdue-7", inner_block: inner("Overdue")})

      assert html =~ ~s(id="action-overdue-7")
    end
  end

  describe "panel/1" do
    @tag req: ["FR-918"]
    test "names its region with the heading inside it" do
      html =
        render_component(&panel/1, %{id: "members", title: "Members", inner_block: inner("x")})

      assert html =~ ~s(id="members" aria-labelledby="members-heading")
      assert html =~ "<section"
      assert html =~ ~s(<h2 id="members-heading")
      assert html =~ "Members"
    end

    @tag req: ["FR-918"]
    test "renders a subtitle and region-level actions when given" do
      html =
        render_component(&panel/1, %{
          id: "members",
          title: "Members",
          subtitle: inner("6 people", :subtitle),
          actions: inner("Invite", :actions),
          inner_block: inner("x")
        })

      assert html =~ "6 people"
      assert html =~ "Invite"
    end

    @tag req: ["FR-918"]
    test "and neither when not" do
      html =
        render_component(&panel/1, %{id: "members", title: "Members", inner_block: inner("x")})

      refute html =~ "6 people"
      refute html =~ "Invite"
    end
  end

  describe "stat/1 and stats/1" do
    # Written out by hand in two places before this, with the same four
    # utilities both times. A number and its label are a pair, and a pair of
    # that kind is a definition list.
    @tag req: ["FR-918"]
    test "pairs a number with the question it answers" do
      html =
        render_component(&stat/1, %{id: "stat-open", label: "Still open", inner_block: inner("4")})

      assert html =~ "<dt"
      assert html =~ ~s(<dd id="stat-open")
      assert html =~ "Still open"
      assert html =~ "4"
    end

    # Two screens show four numbers each and they are not the same four, so
    # the id is the caller's to choose.
    @tag req: ["FR-918"]
    test "takes its id from the caller, since two screens count different things" do
      html =
        render_component(&stat/1, %{
          id: "insight-overdue",
          label: "Overdue",
          inner_block: inner("0")
        })

      assert html =~ ~s(id="insight-overdue")
    end

    @tag req: ["FR-918"]
    test "and a row of them is the list they belong to" do
      assert render_component(&stats/1, %{inner_block: inner("x")}) =~ "<dl"
    end
  end

  describe "empty_state/1" do
    @tag req: ["FR-917"]
    test "says what would be here rather than leaving a gap" do
      html =
        render_component(&empty_state/1, %{
          id: "home-actions-empty",
          title: "Nothing assigned to you.",
          inner_block: inner("Anything the team asks you to take on shows up here.")
        })

      assert html =~ ~s(id="home-actions-empty")
      assert html =~ "Nothing assigned to you."
      assert html =~ "shows up here"
      # The picture says what the sentence says, so it is not said twice.
      assert html =~ ~s(aria-hidden="true")
    end

    @tag req: ["FR-917"]
    test "carries the one thing to do about it, when there is one" do
      html =
        render_component(&empty_state/1, %{
          id: "teams-empty",
          title: "You are not in a team yet.",
          actions: inner("Create your first team", :actions)
        })

      assert html =~ "Create your first team"
    end
  end

  describe "mascot/1" do
    @tag req: ["FR-917"]
    test "draws each of the four poses, and each is a different drawing" do
      paths =
        for pose <- ~w(waiting empty error done) do
          html = render_component(&mascot/1, %{pose: pose})

          assert html =~ "<svg"
          assert html =~ ~s(fill="currentColor")
          html
        end

      assert paths |> Enum.uniq() |> length() == 4
    end
  end

  describe "avatar/1" do
    @tag req: ["FR-918"]
    test "takes the first letter of a display name, in upper case" do
      html = render_component(&avatar/1, %{name: "somchai"})

      assert html =~ ">\n  S\n</span>"
      assert html =~ ~s(aria-hidden="true")
    end

    # The shape a bad data migration leaves behind. The page still renders.
    @tag req: ["FR-919"]
    test "and a question mark when the record has no name at all" do
      assert render_component(&avatar/1, %{name: nil}) =~ "?"
    end

    @tag req: ["FR-913"]
    test "is drawn in one of the two contrast pairs the palette test checks" do
      assert render_component(&avatar/1, %{name: "A", tone: "primary"}) =~ "bg-primary"
      assert render_component(&avatar/1, %{name: "A", tone: "neutral"}) =~ "bg-base-300"
    end
  end

  describe "table/1" do
    test "renders column headers and rows" do
      html =
        render_component(&table/1, %{
          id: "actions",
          rows: [%{id: 1, title: "Fix the deploy"}, %{id: 2, title: "Write the runbook"}],
          col: [
            %{label: "Title", __slot__: :col, inner_block: fn _, row -> row.title end}
          ]
        })

      assert html =~ "Title"
      assert html =~ "Fix the deploy"
      assert html =~ "Write the runbook"
    end

    # A generic table is not the team action list FR-504 asks for; what it
    # does carry is the heading a screen reader needs (FR-913).
    @tag req: ["FR-913"]
    test "renders an action column with a screen-reader heading" do
      html =
        render_component(&table/1, %{
          id: "actions",
          rows: [%{id: 1, title: "Fix the deploy"}],
          row_id: fn row -> "action-#{row.id}" end,
          row_click: fn row -> "select-#{row.id}" end,
          col: [%{label: "Title", __slot__: :col, inner_block: fn _, row -> row.title end}],
          action: [%{__slot__: :action, inner_block: fn _, _row -> "Edit" end}]
        })

      assert html =~ "sr-only"
      assert html =~ "Edit"
      assert html =~ ~s(id="action-1")
      assert html =~ "select-1"
    end

    @tag req: ["FR-305"]
    test "renders a LiveView stream, deriving each row id from the stream" do
      stream =
        Phoenix.LiveView.LiveStream.new(:cards, "0", [%{id: 1, title: "Deploys are scary"}], [])

      html =
        render_component(&table/1, %{
          id: "cards",
          rows: stream,
          col: [%{label: "Card", __slot__: :col, inner_block: fn _, {_id, row} -> row.title end}]
        })

      assert html =~ ~s(phx-update="stream")
      assert html =~ ~s(id="cards-1")
      assert html =~ "Deploys are scary"
    end

    @tag req: ["FR-917"]
    test "renders an empty body when there are no rows" do
      html =
        render_component(&table/1, %{
          id: "actions",
          rows: [],
          col: [%{label: "Title", __slot__: :col, inner_block: fn _, row -> row.title end}]
        })

      assert html =~ "Title"
      refute html =~ "<td"
    end
  end

  describe "list/1" do
    @tag req: ["FR-602"]
    test "renders titled items" do
      html =
        render_component(&list/1, %{
          item: [
            %{
              title: "Template",
              __slot__: :item,
              inner_block: fn _, _ -> "Start-Stop-Continue" end
            },
            %{title: "Participants", __slot__: :item, inner_block: fn _, _ -> "6" end}
          ]
        })

      assert html =~ "Template"
      assert html =~ "Start-Stop-Continue"
      assert html =~ "Participants"
    end
  end

  describe "icon/1" do
    @tag req: ["FR-913"]
    test "renders a heroicon as a class-driven span" do
      html = render_component(&icon/1, name: "hero-x-mark")

      assert html =~ "hero-x-mark"
      assert html =~ "size-4"
    end

    @tag req: ["FR-913"]
    test "accepts a custom size class" do
      assert render_component(&icon/1, name: "hero-check", class: "size-8") =~ "size-8"
    end
  end

  describe "show/2 and hide/2" do
    @tag req: ["FR-916"]
    test "build JS commands targeting a selector" do
      assert %Phoenix.LiveView.JS{ops: [["show", %{to: "#flash"}]]} = show("#flash")
      assert %Phoenix.LiveView.JS{ops: [["hide", %{to: "#flash"}]]} = hide("#flash")
    end

    @tag req: ["FR-916"]
    test "chain onto an existing command" do
      assert %Phoenix.LiveView.JS{ops: [_first, ["hide", _]]} =
               "#a" |> show() |> hide("#b")
    end
  end

  describe "translate_error/1" do
    @tag req: ["FR-906"]
    test "translates a simple message" do
      assert translate_error({"can't be blank", []}) == "can't be blank"
    end

    @tag req: ["FR-906"]
    test "interpolates and pluralises a counted message" do
      assert translate_error({"should be at most %{count} character(s)", [count: 500]}) =~ "500"
    end
  end

  describe "translate_errors/2" do
    @tag req: ["FR-906"]
    test "picks out the messages for one field" do
      errors = [
        title: {"can't be blank", []},
        text: {"is too long", []},
        title: {"is reserved", []}
      ]

      assert translate_errors(errors, :title) == ["can't be blank", "is reserved"]
    end

    @tag req: ["FR-906"]
    test "returns an empty list for a field with no errors" do
      assert translate_errors([], :title) == []
    end
  end

  defp inner(text, name \\ :inner_block) do
    [%{__slot__: name, inner_block: fn _assigns, _ -> text end}]
  end
end
