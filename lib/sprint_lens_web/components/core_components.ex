defmodule SprintLensWeb.CoreComponents do
  @moduledoc """
  The pieces every screen is built from.

  ## What changed, and what did not

  These began as the Phoenix generator's components styled with daisyUI
  classes. `AGENTS.md` asks for components written by hand instead, and the
  interface cannot have a voice of its own while it is wearing a component
  library's. So the markup and the styling are the project's now — Tailwind
  utilities over the tokens in `assets/css/tokens.css`, no `@apply`, no
  library classes.

  What deliberately did not change is every caller's side of the contract:
  the function names, their attributes and slots, the ids they render, and
  the behaviour their tests assert. Seventeen LiveViews call into this module
  and around three hundred element lookups depend on what comes out. Rewriting
  the insides while leaving the edges alone is what makes the screens that
  follow a restyle rather than a rewire.

  ## Two hooks that are not styling

  `data-slot` marks what a thing *is* — a button, a field, a control — so the
  stylesheet can guarantee a forty-four pixel touch target (FR-904) without
  depending on which utility classes happen to be on the element that day.

  `aria-invalid` marks a field the server rejected. It replaces the
  `input-error` class the tests used to look for, and it is the better
  contract twice over: it is what assistive technology reads (FR-919), and it
  does not disappear the next time the styling does.
  """

  use Phoenix.Component
  use Gettext, backend: SprintLensWeb.Gettext

  alias Phoenix.LiveView.JS

  # The mascot's four poses, read at compile time from the drawings themselves
  # so the component and the files cannot fall out of step. Each pose is one
  # path, exactly as the mark is (see `SprintLensWeb.Layouts.logo/1`).
  @mascot_poses ~w(waiting empty error done)

  for pose <- @mascot_poses do
    @external_resource "priv/static/images/mascot-#{pose}.svg"
  end

  @mascot_paths (for pose <- @mascot_poses, into: %{} do
                   source = "priv/static/images/mascot-#{pose}.svg"
                   [_whole, path] = Regex.run(~r/\sd="([^"]+)"/, File.read!(source))

                   {pose, path |> String.split() |> Enum.join(" ")}
                 end)

  # Shared field furniture, so a text input, a select and a textarea cannot
  # drift apart. Functions rather than module attributes: inside a `~H`
  # sigil `@thing` means `assigns.thing`, so an attribute referenced from a
  # template silently renders nothing.
  defp control_class do
    "w-full rounded-control border bg-base-100 px-3 py-2.5 text-body " <>
      "transition-colors placeholder:text-base-content/40 " <>
      "disabled:cursor-not-allowed disabled:opacity-60"
  end

  defp control_border([], _error_class), do: "border-base-300 hover:border-base-content/30"
  defp control_border(_errors, nil), do: "border-error"
  defp control_border(_errors, error_class), do: error_class

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      data-slot="flash"
      data-tone={@kind}
      class="fixed top-4 right-4 z-50 flex justify-end"
      {@rest}
    >
      <div class={
        [
          # Never wider than the viewport it floats over (FR-905).
          "flex w-[calc(100vw-2rem)] max-w-80 items-start gap-3 rounded-panel p-4 text-wrap",
          "shadow-over sm:w-96 sm:max-w-96",
          @kind == :info && "bg-info text-info-content",
          @kind == :error && "bg-error text-error-content"
        ]
      }>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div class="min-w-0 flex-1">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button
          type="button"
          data-slot="button"
          class="shrink-0 cursor-pointer opacity-60 transition-opacity hover:opacity-100"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)

  attr :class, :any,
    default: nil,
    doc: "added to the variant's classes rather than replacing them"

  attr :variant, :string, values: ~w(primary ghost danger)
  attr :size, :string, values: ~w(sm), doc: "smaller, for a control inside a row of content"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base =
      "inline-flex items-center justify-center gap-2 rounded-control font-medium " <>
        "transition-[background-color,opacity] duration-(--sl-duration-quick) cursor-pointer " <>
        "disabled:pointer-events-none disabled:opacity-50"

    variants = %{
      "primary" => "bg-primary text-primary-content shadow-resting hover:opacity-90",
      "danger" => "bg-error text-error-content shadow-resting hover:opacity-90",
      "ghost" => "text-base-content hover:bg-base-200",
      nil => "bg-base-200 text-base-content hover:bg-base-300"
    }

    sizes = %{"sm" => "px-2.5 py-1.5 text-caption", nil => "px-4 py-2.5 text-label"}

    # Added to, not replacing. A caller asking for `w-full` wants a full-width
    # button, not an unstyled one — and two of them were getting exactly that.
    assigns =
      assign(assigns, :class, [
        base,
        Map.fetch!(variants, assigns[:variant]),
        Map.fetch!(sizes, assigns[:size]),
        assigns[:class]
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} data-slot="button" {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} data-slot="button" {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-4" data-slot="field">
      <label for={@id} class="flex items-center gap-2.5 text-label">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          data-slot="control"
          aria-invalid={@errors != [] && "true"}
          class={@class || "size-5 rounded-control border-base-300 text-primary"}
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-4" data-slot="field">
      <label for={@id}>
        <span :if={@label} class="mb-1.5 block text-label font-medium">{@label}</span>
        <select
          id={@id}
          name={@name}
          data-slot="control"
          aria-invalid={@errors != [] && "true"}
          class={[
            @class || control_class(),
            @class == nil && control_border(@errors, @error_class)
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-4" data-slot="field">
      <label for={@id}>
        <span :if={@label} class="mb-1.5 block text-label font-medium">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          data-slot="control"
          aria-invalid={@errors != [] && "true"}
          class={[
            @class || control_class(),
            @class == nil && control_border(@errors, @error_class)
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="mb-4" data-slot="field">
      <label for={@id}>
        <span :if={@label} class="mb-1.5 block text-label font-medium">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          data-slot="control"
          aria-invalid={@errors != [] && "true"}
          class={[
            @class || control_class(),
            @class == nil && control_border(@errors, @error_class)
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors.
  #
  # `text-error` is load-bearing: a Playwright spec finds a validation message
  # by that class. It is the one styling class in this module that is also a
  # contract.
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex items-center gap-2 text-label text-error">
      <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-start justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-title font-semibold">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-label text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  A short fact about the thing beside it: a state, a role, a count.

  The tones are solid rather than tinted. A tinted badge — coloured text on a
  ten-percent wash of the same hue — is the prettier option and fails WCAG at
  small sizes in both themes; `test/sprint_lens_web/contrast_test.exs` proves
  the `{role}` / `{role}-content` pairs clear 4.5:1, so those are the pairs a
  badge is allowed to use.

  ## Examples

      <.badge>Built-in</.badge>
      <.badge tone="danger">Overdue</.badge>
  """
  attr :tone, :string,
    default: "neutral",
    values: ~w(neutral primary info success warning danger)

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def badge(assigns) do
    tones = %{
      "neutral" => "border border-base-300 bg-base-200 text-base-content/80",
      "primary" => "bg-primary text-primary-content",
      "info" => "bg-info text-info-content",
      "success" => "bg-success text-success-content",
      "warning" => "bg-warning text-warning-content",
      "danger" => "bg-error text-error-content"
    }

    assigns =
      assign(assigns, :class, [
        "inline-flex shrink-0 items-center gap-1 rounded-control px-2 py-0.5",
        "text-caption leading-normal font-medium whitespace-nowrap",
        Map.fetch!(tones, assigns.tone),
        assigns.class
      ])

    ~H"""
    <span class={@class} data-slot="badge" data-tone={@tone} {@rest}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  A person, where there is no room for the whole of them.

  The initial of a display name in a circle. There are no uploaded pictures in
  this product and there is no plan for any, so this is the whole of it — and
  it is decorative, because every place it appears has the person's name in
  text beside it.

  ## Examples

      <.avatar name={@user.display_name} />
  """
  attr :name, :any, required: true, doc: "a display name, or nil if the record lost one"
  attr :tone, :string, default: "neutral", values: ~w(neutral primary)
  attr :class, :any, default: "size-9 text-label"

  def avatar(assigns) do
    tones = %{
      "neutral" => "bg-base-300 text-base-content/80",
      "primary" => "bg-primary text-primary-content"
    }

    assigns =
      assign(assigns,
        initial: initial(assigns.name),
        tone_class: Map.fetch!(tones, assigns.tone)
      )

    ~H"""
    <span
      class={["grid shrink-0 place-items-center rounded-full font-semibold", @tone_class, @class]}
      aria-hidden="true"
    >
      {@initial}
    </span>
    """
  end

  # A record with no display name is the shape a bad migration leaves behind.
  # The page it appears on still has to render.
  defp initial(name) when is_binary(name) do
    name |> String.trim() |> String.first() |> to_string() |> String.upcase()
  end

  defp initial(_missing), do: "?"

  @doc """
  One labelled region of a page.

  Every screen is a stack of these, and they were being written out by hand
  each time — a `<section>`, an `aria-labelledby`, an `<h2>` and the same four
  utility classes, six times over on two screens. Repeating a landmark is how
  one of them ends up without a name.

  The heading id is derived from the region's, so the label and the thing it
  labels cannot drift apart.

  ## Examples

      <.panel id="members" title={gettext("Members")}>
        ...
      </.panel>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :class, :any, default: nil
  slot :subtitle, doc: "what the region is for, when the title does not say it"
  slot :actions, doc: "controls that belong to this region rather than the page"
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-heading"} class={["space-y-3", @class]}>
      <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <div class="min-w-0">
          <h2 id={"#{@id}-heading"} class="text-heading font-semibold">{@title}</h2>
          <p :if={@subtitle != []} class="text-label text-base-content/70">
            {render_slot(@subtitle)}
          </p>
        </div>
        <div :if={@actions != []} class="flex flex-none flex-wrap items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>

      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  What a region shows when there is nothing in it yet (FR-917).

  An empty region is the most common state a new team sees and the least
  designed one in most software: a blank rectangle, or the word "None". This
  says what would be here, and where the first one comes from.

  The mascot is decorative and marked so. The sentence beside it already says
  what the picture says, and a screen reader should not say it twice.
  """
  attr :id, :string, required: true
  attr :pose, :string, default: "empty", values: ~w(waiting empty error done)
  attr :title, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, doc: "a sentence about what goes here and how it gets here"
  slot :actions, doc: "the one thing to do about it, if there is one"

  def empty_state(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex flex-col items-center gap-3 rounded-panel border border-dashed border-base-300",
        "px-6 py-10 text-center",
        @class
      ]}
    >
      <.mascot pose={@pose} class="size-12 text-base-content/25" />
      <div class="space-y-1">
        <p class="font-medium">{@title}</p>
        <p :if={@inner_block != []} class="text-label text-base-content/70">
          {render_slot(@inner_block)}
        </p>
      </div>
      <div :if={@actions != []} class="flex flex-wrap justify-center gap-2 pt-1">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  The character, in one of the four poses it has.

  Inlined at compile time rather than fetched as an image, for the reason the
  mark is: an `<img>` cannot take the colour of the text around it, so it
  would need one file per theme, and a second copy of the path data here would
  be a second copy to keep in step with the drawing.
  """
  attr :pose, :string, required: true, values: ~w(waiting empty error done)
  attr :class, :any, default: "size-12"

  def mascot(assigns) do
    assigns = assign(assigns, :path, Map.fetch!(@mascot_paths, assigns.pose))

    ~H"""
    <svg viewBox="0 0 32 32" class={@class} fill="currentColor" aria-hidden="true">
      <path fill-rule="evenodd" d={@path} />
    </svg>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="w-full text-left text-label" data-slot="table">
      <thead class="border-b border-base-300 text-base-content/70">
        <tr>
          <th :for={col <- @col} class="py-2.5 pr-4 font-medium">{col[:label]}</th>
          <th :if={@action != []} class="py-2.5">
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody
        id={@id}
        phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
        class="divide-y divide-base-200"
      >
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="hover:bg-base-200/60">
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={["py-3 pr-4", @row_click && "hover:cursor-pointer"]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 py-3 font-medium">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-base-200" data-slot="list">
      <li :for={item <- @item} class="flex flex-col gap-0.5 py-3">
        <div class="text-label font-semibold text-base-content/70">{item.title}</div>
        <div>{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(SprintLensWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SprintLensWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
