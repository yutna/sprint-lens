defmodule SprintLensWeb.Layouts do
  @moduledoc """
  Page chrome: the navigation bar, the flash region, and the language and
  theme switchers that appear on every screen (FR-907, FR-910).
  """

  use SprintLensWeb, :html

  alias SprintLens.Accounts.User

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

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

  slot :inner_block, required: true

  def app(assigns) do
    # Derived rather than required: a controller-rendered page has no
    # preferences hook to assign them, and every page needs the switchers to
    # show the right state (FR-907, FR-910).
    assigns =
      assigns
      |> assign(:locale, assigns[:locale] || locale(assigns))
      |> assign(:theme, theme(assigns))

    ~H"""
    <%!--
      The nav wraps rather than holding its row: five buttons plus two
      switchers do not fit across a phone, and FR-905 forbids the page
      scrolling sideways to make room.
    --%>
    <header class="navbar flex-wrap gap-2 border-b border-base-200 px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-2 text-base font-semibold">
          <img src={~p"/images/logo.svg"} width="28" alt="" />
          <span>SprintLens</span>
        </.link>
      </div>

      <nav class="flex flex-wrap items-center justify-end gap-1" aria-label={gettext("Main")}>
        <.language_switcher locale={@locale} current_path={@current_path} />
        <.theme_toggle theme={@theme} current_path={@current_path} />

        <%= if @current_scope && @current_scope.user do %>
          <.link navigate={~p"/home"} class="btn btn-ghost btn-sm">{gettext("Home")}</.link>
          <.link navigate={~p"/teams"} class="btn btn-ghost btn-sm">{gettext("Teams")}</.link>
          <.link navigate={~p"/join"} class="btn btn-ghost btn-sm">{gettext("Join")}</.link>
          <.link navigate={~p"/users/preferences"} class="btn btn-ghost btn-sm">
            {gettext("Preferences")}
          </.link>
          <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
            {gettext("Log out")}
          </.link>
        <% else %>
          <.link navigate={~p"/users/register"} class="btn btn-ghost btn-sm">
            {gettext("Register")}
          </.link>
          <.link navigate={~p"/users/log-in"} class="btn btn-primary btn-sm">
            {gettext("Log in")}
          </.link>
        <% end %>
      </nav>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto w-full max-w-5xl space-y-6">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
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
    <div class="join" role="group" aria-label={gettext("Language")}>
      <.link
        :for={language <- SprintLensWeb.Locale.supported()}
        href={~p"/locale/#{language}?#{[return_to: @current_path]}"}
        class={["btn btn-ghost btn-xs join-item", @locale == language && "btn-active"]}
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
      class="card relative flex flex-row items-center rounded-full border-2 border-base-300 bg-base-300"
      role="group"
      aria-label={gettext("Theme")}
    >
      <div class="absolute left-0 h-full w-1/3 rounded-full border-1 border-base-200 bg-base-100 brightness-200 transition-[left] [[data-theme-source=system]_&]:!left-0 [[data-theme=dark]_&]:left-2/3 [[data-theme=light]_&]:left-1/3" />

      <.link
        :for={{value, icon, label} <- theme_options()}
        href={~p"/theme/#{value}?#{[return_to: @current_path]}"}
        class="flex w-1/3 cursor-pointer p-2"
        data-phx-theme={value}
        aria-label={theme_label(label, @theme == value)}
      >
        <.icon name={icon} class="size-4 opacity-75 hover:opacity-100" />
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
