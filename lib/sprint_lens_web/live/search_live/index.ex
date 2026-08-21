defmodule SprintLensWeb.SearchLive.Index do
  @moduledoc """
  Searching a team's past cards, discussion notes and action items (FR-603).

  Section 8.1 lists no screen for this, so it gets its own route rather than
  being tucked into a corner of another page: a search box that is hard to
  find is a feature nobody uses.

  Only finished sessions are searched — see `SprintLens.Insights.search/3` for
  why that is a promise and not a limitation.
  """

  use SprintLensWeb, :live_view

  import SprintLensWeb.ActionComponents

  alias SprintLens.Insights
  alias SprintLens.Teams
  alias SprintLensWeb.TemplateText

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      theme={@theme}
      current_path={@current_path}
    >
      <.header>
        {gettext("Search")}
        <:subtitle>{@team.name}</:subtitle>
        <:actions>
          <.link navigate={~p"/teams/#{@team}"} class="btn btn-ghost btn-sm">
            {gettext("Back to team")}
          </.link>
        </:actions>
      </.header>

      <.form for={@form} id="search-form" phx-change="search" phx-submit="search">
        <.input
          field={@form[:q]}
          type="search"
          label={gettext("Find a card, a note or an action")}
          placeholder={gettext("What are you looking for?")}
          autocomplete="off"
        />
      </.form>

      <p
        :if={is_nil(@results)}
        id="search-prompt"
        class="rounded-box border border-base-300 p-6 text-center"
      >
        {gettext("Only finished retrospectives are searched.")}
      </p>

      <div :if={@results} class="space-y-6">
        <p
          :if={empty?(@results)}
          id="search-empty"
          class="rounded-box border border-base-300 p-6 text-center"
        >
          {gettext("Nothing matched “%{query}”.", query: @results.query)}
        </p>

        <section :if={@results.cards != []} aria-labelledby="search-cards-heading">
          <h2 id="search-cards-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
            {ngettext("%{count} card", "%{count} cards", length(@results.cards),
              count: length(@results.cards)
            )}
          </h2>

          <ul id="search-cards" class="space-y-2">
            <li
              :for={card <- @results.cards}
              id={"search-card-#{card.id}"}
              class="rounded-box border border-base-200 p-2"
            >
              <p class="whitespace-pre-wrap break-words">{card.text}</p>
              <.link
                navigate={~p"/sessions/#{card.column.session_id}/recap"}
                class="text-xs opacity-70 hover:underline"
              >
                {card.column.session.title} · {TemplateText.column_name(card.column)}
              </.link>
            </li>
          </ul>
        </section>

        <section :if={@results.notes != []} aria-labelledby="search-notes-heading">
          <h2 id="search-notes-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
            {ngettext("%{count} note", "%{count} notes", length(@results.notes),
              count: length(@results.notes)
            )}
          </h2>

          <ul id="search-notes" class="space-y-2">
            <li
              :for={note <- @results.notes}
              id={"search-note-#{note.id}"}
              class="rounded-box border border-base-200 p-2"
            >
              <p class="whitespace-pre-wrap break-words">{note.body}</p>
              <.link
                navigate={~p"/sessions/#{note.session_id}/recap"}
                class="text-xs opacity-70 hover:underline"
              >
                {note.session.title}
              </.link>
            </li>
          </ul>
        </section>

        <section :if={@results.actions != []} aria-labelledby="search-actions-heading">
          <h2 id="search-actions-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
            {ngettext("%{count} action", "%{count} actions", length(@results.actions),
              count: length(@results.actions)
            )}
          </h2>

          <ul id="search-actions" class="space-y-2">
            <.action_row :for={action <- @results.actions} action={action} now={@now} />
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"team_id" => team_id}, _session, socket) do
    case Teams.fetch_team(socket.assigns.current_scope, team_id) do
      {:ok, team} ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Search"))
         |> assign(:team, team)
         |> assign(:now, DateTime.utc_now())
         |> assign(:results, nil)
         |> assign(:form, to_form(%{"q" => ""}, as: :search))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That resource does not exist."))
         |> push_navigate(to: ~p"/teams")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("search", %{"search" => %{"q" => query}}, socket) do
    socket = assign(socket, :form, to_form(%{"q" => query}, as: :search))

    case Insights.search(socket.assigns.current_scope, socket.assigns.team, query) do
      {:ok, results} -> {:noreply, assign(socket, :results, results)}
      # An empty box is not a failed search; it is not a search.
      {:error, :empty_query} -> {:noreply, assign(socket, :results, nil)}
    end
  end

  defp empty?(results) do
    results.cards == [] and results.notes == [] and results.actions == []
  end
end
