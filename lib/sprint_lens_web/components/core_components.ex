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
  attr :class, :any
  attr :variant, :string, values: ~w(primary ghost danger)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base =
      "inline-flex items-center justify-center gap-2 rounded-control px-4 py-2.5 " <>
        "text-label font-medium transition-[background-color,opacity] " <>
        "duration-(--sl-duration-quick) cursor-pointer " <>
        "disabled:pointer-events-none disabled:opacity-50"

    variants = %{
      "primary" => "bg-primary text-primary-content shadow-resting hover:opacity-90",
      "danger" => "bg-error text-error-content shadow-resting hover:opacity-90",
      "ghost" => "text-base-content hover:bg-base-200",
      nil => "bg-base-200 text-base-content hover:bg-base-300"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        [base, Map.fetch!(variants, assigns[:variant])]
      end)

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
