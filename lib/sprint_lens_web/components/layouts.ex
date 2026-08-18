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
    <header class="navbar gap-2 border-b border-base-200 px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-2 text-base font-semibold">
          <img src={~p"/images/logo.svg"} width="28" alt="" />
          <span>SprintLens</span>
        </.link>
      </div>

      <nav class="flex flex-none items-center gap-1" aria-label={gettext("Main")}>
        <.language_switcher locale={@locale} />
        <.theme_toggle theme={@theme} />

        <%= if @current_scope && @current_scope.user do %>
          <.link navigate={~p"/home"} class="btn btn-ghost btn-sm">{gettext("Home")}</.link>
          <.link navigate={~p"/teams"} class="btn btn-ghost btn-sm">{gettext("Teams")}</.link>
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
  Switches the interface language without a full reload (FR-907).

  The choice is written to the profile by
  `SprintLensWeb.Hooks.Preferences`, so it follows the user to their next
  device rather than living in this browser.
  """
  attr :locale, :string, default: "th"

  def language_switcher(assigns) do
    ~H"""
    <div class="join" role="group" aria-label={gettext("Language")}>
      <button
        :for={language <- SprintLensWeb.Locale.supported()}
        type="button"
        class={["btn btn-ghost btn-xs join-item", @locale == language && "btn-active"]}
        aria-pressed={to_string(@locale == language)}
        phx-click={JS.push("set_language", value: %{language: language})}
      >
        {language_label(language)}
      </button>
    </div>
    """
  end

  defp language_label("th"), do: "ไทย"
  defp language_label("en"), do: "EN"

  @doc """
  Light, dark and system themes (FR-910).

  Each option both dispatches the client event that repaints immediately and
  pushes the choice to the server so it lands in the profile (FR-911).
  """
  attr :theme, :string, default: "system"

  def theme_toggle(assigns) do
    ~H"""
    <div
      class="card relative flex flex-row items-center rounded-full border-2 border-base-300 bg-base-300"
      role="group"
      aria-label={gettext("Theme")}
    >
      <div class="absolute left-0 h-full w-1/3 rounded-full border-1 border-base-200 bg-base-100 brightness-200 transition-[left] [[data-theme-source=system]_&]:!left-0 [[data-theme=dark]_&]:left-2/3 [[data-theme=light]_&]:left-1/3" />

      <button
        :for={{value, icon, label} <- theme_options()}
        type="button"
        class="flex w-1/3 cursor-pointer p-2"
        data-phx-theme={value}
        aria-pressed={to_string(@theme == value)}
        aria-label={label}
        phx-click={JS.dispatch("phx:set-theme") |> JS.push("set_theme", value: %{theme: value})}
      >
        <.icon name={icon} class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

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
