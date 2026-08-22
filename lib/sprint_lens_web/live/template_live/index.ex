defmodule SprintLensWeb.TemplateLive.Index do
  @moduledoc """
  SCR-11 Templates: the built-in layouts every team can use, and the ones this
  team has defined for itself (FR-201, FR-202).
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Teams
  alias SprintLens.Teams.Template
  alias SprintLensWeb.CoreComponents
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
      team={@team}
      breadcrumbs={[
        {gettext("Teams"), ~p"/teams"},
        {@team.name, ~p"/teams/#{@team}"},
        {gettext("Templates"), ~p"/teams/#{@team}/templates"}
      ]}
    >
      <.header>
        {gettext("Templates")}
        <:subtitle>{gettext("The columns a board starts with.")}</:subtitle>
      </.header>

      <.panel id="template-list" title={gettext("Available templates")}>
        <:subtitle>
          {gettext("Five come with the product. The rest are this team's own.")}
        </:subtitle>

        <ul id="templates" class="grid gap-3 sm:grid-cols-2">
          <li
            :for={template <- @templates}
            id={"template-#{template.id}"}
            class="flex flex-col gap-3 rounded-card border border-base-200 p-4"
          >
            <div class="flex items-start justify-between gap-2">
              <span class="flex min-w-0 flex-wrap items-center gap-2">
                <span class="font-semibold">{TemplateText.template_name(template)}</span>
                <.badge :if={template.is_builtin}>{gettext("Built-in")}</.badge>
              </span>
              <.button
                :if={not template.is_builtin and not @team.is_archived}
                id={"delete-template-#{template.id}"}
                phx-click="delete"
                phx-value-id={template.id}
                data-confirm={gettext("Delete this template?")}
                variant="ghost"
                size="sm"
              >
                {gettext("Delete")}
              </.button>
            </div>

            <%!--
              An ordered list, because the order is the layout: these are the
              columns of a board from left to right.
            --%>
            <ol class="flex flex-wrap gap-1.5">
              <li
                :for={name <- TemplateText.template_column_names(template)}
                class="rounded-control border border-base-300 px-2 py-0.5 text-caption"
              >
                {name}
              </li>
            </ol>
          </li>
        </ul>
      </.panel>

      <.panel
        :if={not @team.is_archived}
        id="template-new"
        title={gettext("Write your own")}
        class="max-w-xl"
      >
        <.form
          for={@form}
          id="template_form"
          phx-change="validate"
          phx-submit="save"
          class="rounded-panel border border-base-200 bg-base-100 p-4 shadow-resting sm:p-6"
        >
          <.input field={@form[:name]} type="text" label={gettext("Template name")} required />

          <fieldset>
            <legend class="mb-1.5 block text-label font-medium">
              {gettext("Columns (%{min} to %{max})",
                min: elem(Template.column_bounds(), 0),
                max: elem(Template.column_bounds(), 1)
              )}
            </legend>

            <div
              :for={index <- 0..(elem(Template.column_bounds(), 1) - 1)}
              class="grid gap-2 sm:grid-cols-2"
            >
              <.input
                type="text"
                id={"template-column-#{index}-name"}
                name={"template[columns][#{index}][name]"}
                value={column_value(@columns, index, "name")}
                placeholder={gettext("Column %{number}", number: index + 1)}
                aria-label={gettext("Column %{number} name", number: index + 1)}
              />
              <.input
                type="text"
                id={"template-column-#{index}-hint"}
                name={"template[columns][#{index}][hint]"}
                value={column_value(@columns, index, "hint")}
                placeholder={gettext("Hint (optional)")}
                aria-label={gettext("Column %{number} hint", number: index + 1)}
              />
            </div>

            <%!--
              `text-error` is load-bearing: a browser test finds the refusal
              by that class rather than by its wording, which is what lets the
              message be rewritten or retranslated without breaking the suite.
            --%>
            <p :for={message <- column_errors(@form)} class="text-label text-error">
              {message}
            </p>
          </fieldset>

          <.button variant="primary" phx-disable-with={gettext("Saving...")} class="mt-4">
            {gettext("Save template")}
          </.button>
        </.form>
      </.panel>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"team_id" => team_id}, _session, socket) do
    case Teams.fetch_team(socket.assigns.current_scope, team_id) do
      {:ok, team} ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Templates"))
         |> assign(:team, team)
         |> assign(:columns, [])
         |> assign_templates()
         |> assign_form(Teams.change_template())}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That resource does not exist."))
         |> push_navigate(to: ~p"/teams")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"template" => params}, socket) do
    params = normalise(params)
    changeset = Teams.change_template(%Template{}, params) |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:columns, params["columns"]) |> assign_form(changeset)}
  end

  def handle_event("save", %{"template" => params}, socket) do
    params = normalise(params)

    case Teams.create_template(socket.assigns.current_scope, socket.assigns.team, params) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> assign(:columns, [])
         |> assign_templates()
         |> assign_form(Teams.change_template())
         |> put_flash(:info, gettext("Template saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:columns, params["columns"])
         |> assign_form(Map.put(changeset, :action, :insert))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You do not have permission to do that."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, template} <- Teams.fetch_template(socket.assigns.team, id),
         :ok <- Teams.delete_template(socket.assigns.current_scope, socket.assigns.team, template) do
      {:noreply, socket |> assign_templates() |> put_flash(:info, gettext("Template deleted."))}
    else
      {:error, :builtin} ->
        {:noreply, put_flash(socket, :error, gettext("Built-in templates cannot be changed."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("You do not have permission to do that."))}
    end
  end

  # The column inputs submit as an index-keyed map; drop the blank rows so a
  # partly filled form is judged on what was actually typed (FR-202).
  defp normalise(%{"columns" => columns} = params) when is_map(columns) do
    kept =
      columns
      |> Enum.sort_by(fn {index, _column} -> String.to_integer(index) end)
      |> Enum.map(fn {_index, column} -> column end)
      |> Enum.reject(&(blank?(&1["name"]) and blank?(&1["hint"])))

    Map.put(params, "columns", kept)
  end

  defp normalise(params), do: Map.put_new(params, "columns", [])

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(value) == ""

  defp column_value(columns, index, key) do
    case Enum.at(columns || [], index) do
      nil -> nil
      column -> column[key]
    end
  end

  # Column errors belong to the fieldset as a whole rather than to any one
  # input, so they are rendered here instead of by `<.input>`.
  defp column_errors(form), do: CoreComponents.translate_errors(form.errors, :columns)

  defp assign_templates(socket) do
    assign(socket, :templates, Teams.list_templates(socket.assigns.team))
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "template"))
  end
end
