defmodule SprintLensWeb.Layouts do
  @moduledoc """
  Page chrome: the navigation bar, the flash region, and the language and
  theme switchers that appear on every screen (FR-907, FR-910).
  """

  use SprintLensWeb, :html

  alias SprintLens.Accounts.User

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  # The mark is inlined rather than fetched as an image so it can take the
  # colour of the text beside it, which is what saves a light and a dark
  # variant. Read at compile time from the one drawing anyone edits — an
  # `<img>` cannot inherit a colour, and a second copy of the path data here
  # would be a second copy to keep in step.
  @mark_source "priv/static/images/logo-mark.svg"
  @external_resource @mark_source
  @mark_path (fn ->
                [_whole, path] = Regex.run(~r/\sd="([^"]+)"/, File.read!(@mark_source))

                path |> String.split() |> Enum.join(" ")
              end).()

  @doc """
  The `data-theme` the server stamps on `<html>`.

  Rendering the signed-in user's saved theme server-side is what stops a new
  device flashing the wrong colours before JavaScript runs (FR-911). "system"
  is left for the client to resolve, because only the browser knows the OS
  preference.
  """
  @spec initial_theme(map()) :: String.t() | nil
  def initial_theme(assigns) do
    case theme(assigns) do
      "system" -> nil
      theme -> theme
    end
  end

  @doc """
  Whether the active theme came from the user or should follow the OS.
  """
  @spec theme_source(map()) :: String.t()
  def theme_source(assigns) do
    if theme(assigns) == "system", do: "system", else: "user"
  end

  defp theme(assigns) do
    cond do
      is_binary(assigns[:theme]) -> assigns[:theme]
      is_binary(scope_field(assigns, :theme)) -> scope_field(assigns, :theme)
      true -> "system"
    end
  end

  defp locale(assigns) do
    scope_field(assigns, :language) || SprintLensWeb.Locale.default()
  end

  defp scope_field(assigns, field) do
    case assigns[:current_scope] do
      %{user: %{} = user} -> Map.get(user, field)
      _no_user -> nil
    end
  end

  @doc """
  The application shell every page renders inside.

  ## What it is for

  Navigation used to be five flat buttons and two switchers in one wrapping
  row, and everything below the team level was reached from buttons individual
  pages added to their own headers — one screen put six of them there. Nothing
  told you where you were, and nothing kept the team you were working in
  visible as you moved between its retrospectives, actions and insights.

  So: one persistent shell. The mark, the places a person actually goes, and
  an account menu holding the things that are about *you* rather than about
  the product — preferences, language, theme, signing out. Preferences belong
  behind a menu; they were taking up two thirds of the navigation bar.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :locale, :string, default: nil
  attr :theme, :string, default: nil

  attr :current_path, :string,
    default: "/",
    doc: "where the preference switchers should send the visitor back to"

  attr :breadcrumbs, :list,
    default: [],
    doc: "`{label, path}` pairs from the top of the hierarchy down to this page"

  slot :inner_block, required: true

  def app(assigns) do
    # Derived rather than required: a controller-rendered page has no
    # preferences hook to assign them, and every page needs the switchers to
    # show the right state (FR-907, FR-910).
    assigns =
      assigns
      |> assign(:locale, assigns[:locale] || locale(assigns))
      |> assign(:theme, theme(assigns))
      |> assign(:user, user(assigns))

    ~H"""
    <%!--
      The first focusable thing on every page. Without it a keyboard reaches
      the content by walking the whole navigation, on every single page.
    --%>
    <.link
      href="#main"
      class="sr-only rounded-control bg-primary px-4 py-2 text-primary-content focus:not-sr-only focus:absolute focus:top-3 focus:left-3 focus:z-50"
    >
      {gettext("Skip to content")}
    </.link>

    <header class="border-b border-base-200 bg-base-100">
      <div class="mx-auto flex w-full max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3 sm:px-6 lg:px-8">
        <%!--
          The mark is decorative: the wordmark beside it is real text, so
          describing the image would make a screen reader say the name twice.
        --%>
        <.link
          navigate={~p"/"}
          class="flex w-fit shrink-0 items-center gap-2 text-heading font-semibold"
        >
          <.logo class="size-7 text-primary" />
          <span>SprintLens</span>
        </.link>

        <nav
          :if={@user}
          class="flex flex-1 items-center gap-1"
          aria-label={gettext("Main navigation")}
        >
          <.nav_link navigate={~p"/home"} current_path={@current_path}>{gettext("Home")}</.nav_link>
          <.nav_link navigate={~p"/teams"} current_path={@current_path}>{gettext("Teams")}</.nav_link>
          <.nav_link navigate={~p"/join"} current_path={@current_path}>{gettext("Join")}</.nav_link>
        </nav>

        <div class={["flex items-center gap-2", !@user && "flex-1 justify-end"]}>
          <%= if @user do %>
            <.account_menu user={@user} locale={@locale} theme={@theme} current_path={@current_path} />
          <% else %>
            <.language_switcher locale={@locale} current_path={@current_path} />
            <.theme_toggle theme={@theme} current_path={@current_path} />
            <.link
              navigate={~p"/users/register"}
              data-slot="button"
              class="rounded-control px-3 py-2 text-label font-medium hover:bg-base-200"
            >
              {gettext("Register")}
            </.link>
            <.link
              navigate={~p"/users/log-in"}
              data-slot="button"
              class="rounded-control bg-primary px-3 py-2 text-label font-medium text-primary-content shadow-resting hover:opacity-90"
            >
              {gettext("Log in")}
            </.link>
          <% end %>
        </div>
      </div>

      <.breadcrumbs :if={@breadcrumbs != []} trail={@breadcrumbs} />
    </header>

    <main id="main" class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto w-full max-w-6xl space-y-6">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  defp user(assigns) do
    case assigns[:current_scope] do
      %{user: %{} = user} -> user
      _no_user -> nil
    end
  end

  @doc """
  One item of the primary navigation, which knows whether it is where you are.

  `aria-current="page"` rather than `"true"`: the phase bar and the discussion
  focus both use `[aria-current="true"]`, and two suites find the active phase
  by taking the first one in the document. This sits above them.
  """
  attr :navigate, :string, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  def nav_link(assigns) do
    assigns = assign(assigns, :here?, assigns.current_path == assigns.navigate)

    ~H"""
    <.link
      navigate={@navigate}
      data-slot="button"
      aria-current={@here? && "page"}
      class={[
        "rounded-control px-3 py-2 text-label font-medium transition-colors",
        "duration-(--sl-duration-quick)",
        if(@here?,
          do: "bg-base-200 text-base-content",
          else: "text-base-content/70 hover:bg-base-200"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Where you are in the hierarchy, from the top down.

  The last entry is the page itself and is not a link — there is nowhere for
  it to go, and offering one is a keyboard stop that does nothing.
  """
  attr :trail, :list, required: true

  def breadcrumbs(assigns) do
    ~H"""
    <nav aria-label={gettext("Breadcrumb")} class="border-t border-base-200 bg-base-200/40">
      <ol class="mx-auto flex w-full max-w-6xl flex-wrap items-center gap-1 px-4 py-2 text-label sm:px-6 lg:px-8">
        <li :for={{{label, path}, index} <- Enum.with_index(@trail)} class="flex items-center gap-1">
          <.icon
            :if={index > 0}
            name="hero-chevron-right-micro"
            class="size-4 shrink-0 opacity-40"
          />
          <.link
            :if={index < length(@trail) - 1}
            navigate={path}
            class="truncate text-base-content/70 hover:text-base-content"
          >
            {label}
          </.link>
          <span :if={index == length(@trail) - 1} aria-current="page" class="truncate font-medium">
            {label}
          </span>
        </li>
      </ol>
    </nav>
    """
  end

  @doc """
  The account menu: everything that is about the person rather than the
  product.

  A `<details>` element, not a scripted dropdown. It opens with a keyboard,
  closes with Escape, and works with JavaScript switched off — all of which a
  hand-rolled menu would have to be given, and would eventually be given
  wrongly.
  """
  attr :user, :map, required: true
  attr :locale, :string, required: true
  attr :theme, :string, required: true
  attr :current_path, :string, required: true

  def account_menu(assigns) do
    ~H"""
    <details class="relative" id="account-menu">
      <summary
        data-slot="button"
        class="flex cursor-pointer list-none items-center gap-2 rounded-control px-3 py-2 text-label font-medium hover:bg-base-200"
      >
        <span
          class="grid size-7 shrink-0 place-items-center rounded-full bg-primary text-caption font-semibold text-primary-content"
          aria-hidden="true"
        >
          {initial(@user)}
        </span>
        <span class="hidden max-w-40 truncate sm:inline">{@user.display_name}</span>
        <.icon name="hero-chevron-down-micro" class="size-4 opacity-60" />
      </summary>

      <div class="absolute right-0 z-40 mt-2 w-64 rounded-panel border border-base-300 bg-base-100 p-3 shadow-over">
        <p class="truncate px-1 pb-2 text-caption text-base-content/60">{@user.email}</p>

        <.link
          navigate={~p"/users/preferences"}
          data-slot="button"
          class="block rounded-control px-2 py-2 text-label hover:bg-base-200"
        >
          {gettext("Preferences")}
        </.link>

        <div class="my-2 border-t border-base-200" />

        <p class="px-2 pb-1.5 text-caption text-base-content/60">{gettext("Language")}</p>
        <.language_switcher locale={@locale} current_path={@current_path} />

        <p class="px-2 pt-3 pb-1.5 text-caption text-base-content/60">{gettext("Theme")}</p>
        <.theme_toggle theme={@theme} current_path={@current_path} />

        <div class="my-2 border-t border-base-200" />

        <.link
          href={~p"/users/log-out"}
          method="delete"
          data-slot="button"
          class="block rounded-control px-2 py-2 text-label hover:bg-base-200"
        >
          {gettext("Log out")}
        </.link>
      </div>
    </details>
    """
  end

  defp initial(%{display_name: name}) when is_binary(name) do
    name |> String.trim() |> String.first() |> to_string() |> String.upcase()
  end

  defp initial(_user), do: "?"

  @doc """
  The product's mark, in the colour of whatever it sits next to (FR-911).
  """
  attr :class, :string, default: "size-7"

  def logo(assigns) do
    assigns = assign(assigns, :path, @mark_path)

    ~H"""
    <svg viewBox="0 0 32 32" class={@class} fill="currentColor" aria-hidden="true">
      <path fill-rule="evenodd" d={@path} />
    </svg>
    """
  end

  @doc """
  The frame the sign-in, registration and account screens sit in.

  These are the first pages anybody sees, and they were a form floating in the
  middle of an empty page. A card gives the form somewhere to be: it says the
  page has one job, and it stops the eye hunting for where to start.

  Shared rather than repeated on five screens, because five copies of a layout
  are five chances for four of them to fall behind.
  """
  attr :class, :any, default: nil
  slot :title, required: true
  slot :subtitle
  slot :inner_block, required: true

  def auth_card(assigns) do
    ~H"""
    <div class={["mx-auto w-full max-w-md space-y-6 py-4", @class]}>
      <div class="space-y-1 text-center">
        <h1 class="text-title font-semibold">{render_slot(@title)}</h1>
        <p :if={@subtitle != []} class="text-label text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>

      <div class="rounded-panel border border-base-200 bg-base-100 p-6 shadow-resting sm:p-8">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  A quiet aside: something true about the situation that is not a problem.

  Distinct from a flash, which is about something that just happened, and from
  an error, which is about something being wrong.
  """
  slot :inner_block, required: true

  def notice(assigns) do
    ~H"""
    <div class="flex items-start gap-3 rounded-card border border-info/30 bg-info/10 p-4 text-label">
      <.icon name="hero-information-circle" class="mt-0.5 size-5 shrink-0 text-info" />
      <div class="min-w-0 space-y-0.5">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Switches the interface language (FR-907).

  Real navigation, not a pushed event. `JS.push` needs a live process on the
  other end of the socket; the landing page, the development routes and the
  rendered error pages have none, so the click died silently on every one of
  them — which is the defect this replaces.

  FR-907 asks for the change to apply "without a full reload where feasible".
  One mechanism that works on every page is worth more than a faster one that
  works on some, and switching language is something a person does once, so
  the link form is used everywhere rather than only where it is forced. It
  also works with JavaScript switched off, which the pushed event never did.

  `SprintLensWeb.LocaleController` decides where the choice is written: the
  profile for someone signed in, the session cookie for someone who is not.
  """
  attr :locale, :string, default: "th"
  attr :current_path, :string, default: "/"

  def language_switcher(assigns) do
    ~H"""
    <div
      class="inline-flex rounded-control border border-base-300 p-0.5"
      role="group"
      aria-label={gettext("Language")}
    >
      <.link
        :for={language <- SprintLensWeb.Locale.supported()}
        href={~p"/locale/#{language}?#{[return_to: @current_path]}"}
        data-slot="button"
        class={[
          "rounded-control px-2.5 py-1 text-caption font-medium transition-colors",
          "duration-(--sl-duration-quick)",
          if(@locale == language,
            do: "bg-base-content/10 text-base-content",
            else: "text-base-content/60 hover:text-base-content"
          )
        ]}
      >
        {language_label(language)}
        <span :if={@locale == language} class="sr-only">{gettext("current")}</span>
      </.link>
    </div>
    """
  end

  defp language_label("th"), do: "ไทย"
  defp language_label("en"), do: "EN"

  @doc """
  Light, dark and system themes (FR-910).

  Navigation for the same reason as the language switcher, and with one extra
  consequence worth stating: the choice now lives on the server, in the
  profile or in the session, rather than in `localStorage`. That is what makes
  FR-911 hold. The layout stamps `data-theme` on `<html>` before anything is
  painted, so a visitor who chose dark before signing in gets dark on the very
  next request instead of a flash of the operating system's preference.

  `system` is still resolved by the client, because only the browser knows
  what the operating system prefers.
  """
  attr :theme, :string, default: "system"
  attr :current_path, :string, default: "/"

  def theme_toggle(assigns) do
    ~H"""
    <div
      class="inline-flex rounded-control border border-base-300 p-0.5"
      role="group"
      aria-label={gettext("Theme")}
    >
      <.link
        :for={{value, icon, label} <- theme_options()}
        href={~p"/theme/#{value}?#{[return_to: @current_path]}"}
        data-slot="button"
        data-phx-theme={value}
        aria-label={theme_label(label, @theme == value)}
        class={[
          "rounded-control px-2 py-1.5 transition-colors duration-(--sl-duration-quick)",
          if(@theme == value,
            do: "bg-base-content/10 text-base-content",
            else: "text-base-content/60 hover:text-base-content"
          )
        ]}
      >
        <.icon name={icon} class="size-4" />
      </.link>
    </div>
    """
  end

  # Deliberately not `aria-current`. It is the right attribute for "the
  # current item in a set", and the phase bar and the discussion focus already
  # use it correctly — but four Playwright specs and three ExUnit tests find
  # the active phase by taking the first `[aria-current="true"]` in the
  # document, and this switcher sits above it in the header. Marking the
  # active option in text instead keeps the state announced without quietly
  # stealing that selector.
  defp theme_label(label, false), do: label
  defp theme_label(label, true), do: label <> ", " <> gettext("current")

  defp theme_options do
    [
      {"system", "hero-computer-desktop-micro", gettext("System theme")},
      {"light", "hero-sun-micro", gettext("Light theme")},
      {"dark", "hero-moon-micro", gettext("Dark theme")}
    ]
  end

  @doc """
  Every theme the UI offers, for building a form.
  """
  @spec theme_choices() :: [{String.t(), String.t()}]
  def theme_choices do
    [
      {gettext("Follow the system"), "system"},
      {gettext("Light"), "light"},
      {gettext("Dark"), "dark"}
    ]
  end

  @doc """
  Every language the UI offers, for building a form.
  """
  @spec language_choices() :: [{String.t(), String.t()}]
  def language_choices do
    Enum.map(User.languages(), fn
      "th" -> {"ไทย", "th"}
      "en" -> {"English", "en"}
    end)
  end
end
