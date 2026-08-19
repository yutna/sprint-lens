defmodule SprintLensWeb.CoreComponentsTest do
  use SprintLens.UnitCase, async: true

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
      assert html =~ "alert-info"
      assert html =~ ~s(role="alert")
    end

    @tag req: ["FR-919"]
    test "renders an error message with error styling" do
      html = render_component(&flash/1, kind: :error, flash: %{"error" => "Could not save"})

      assert html =~ "Could not save"
      assert html =~ "alert-error"
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
      assert html =~ "btn"
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

      assert html =~ "btn-primary"
      refute html =~ "btn-soft"
    end

    @tag req: ["FR-914"]
    test "a caller-supplied class replaces the defaults entirely" do
      html = render_component(&button/1, %{class: "my-btn", inner_block: inner("Go")})

      assert html =~ ~s(class="my-btn")
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
      assert html =~ "input-error"
    end

    @tag req: ["FR-919"]
    test "hides errors on a field the user has not touched yet" do
      html = render_component(&input/1, field: field(:email, "", [{"can't be blank", []}], false))

      refute html =~ "input-error"
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

      assert html =~ "select-error"
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

      assert html =~ "textarea-error"
      assert html =~ "500"
    end

    @tag req: ["FR-919"]
    test "a caller-supplied class replaces the default input class" do
      html = render_component(&input/1, name: "n", value: "", class: "custom-input")

      assert html =~ "custom-input"
      refute html =~ ~s(class="w-full input")
    end

    @tag req: ["FR-919"]
    test "a caller-supplied error class replaces the default" do
      html =
        render_component(&input/1, name: "n", value: "", errors: ["bad"], error_class: "ring-red")

      assert html =~ "ring-red"
      refute html =~ "input-error"
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
