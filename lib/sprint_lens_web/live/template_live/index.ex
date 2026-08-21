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
    >
      <.header>
        {gettext("Templates")}
        <:subtitle>
          {gettext("Column layouts for %{team}", team: @team.name)}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/teams/#{@team}"} class="btn btn-ghost btn-sm">
            {gettext("Back to team")}
          </.link>
        </:actions>
      </.header>

      <.form
        :if={not @team.is_archived}
        for={@form}
        id="template_form"
        phx-change="validate"
        phx-submit="save"
        class="max-w-xl"
      >
        <.input field={@form[:name]} type="text" label={gettext("Template name")} required />

        <fieldset class="fieldset">
          <legend class="label">
            {gettext("Columns (%{min} to %{max})",
              min: elem(Template.column_bounds(), 0),
              max: elem(Template.column_bounds(), 1)
            )}
          </legend>

          <div :for={index <- 0..(elem(Template.column_bounds(), 1) - 1)} class="mb-2 flex gap-2">
            <input
              type="text"
              name={"template[columns][#{index}][name]"}
              value={column_value(@columns, index, "name")}
              placeholder={gettext("Column %{number}", number: index + 1)}
              class="w-1/2 input"
              aria-label={gettext("Column %{number} name", number: index + 1)}
            />
            <input
              type="text"
              name={"template[columns][#{index}][hint]"}
              value={column_value(@columns, index, "hint")}
              placeholder={gettext("Hint (optional)")}
              class="w-1/2 input"
              aria-label={gettext("Column %{number} hint", number: index + 1)}
            />
          </div>

          <p :for={message <- column_errors(@form)} class="text-sm text-error">{message}</p>
        </fieldset>

        <.button variant="primary" phx-disable-with={gettext("Saving...")}>
          {gettext("Save template")}
        </.button>
      </.form>

      <section aria-labelledby="templates-heading">
        <h2 id="templates-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Available templates")}
        </h2>

        <ul id="templates" class="grid gap-3 sm:grid-cols-2">
          <li
            :for={template <- @templates}
            id={"template-#{template.id}"}
            class="rounded-box border border-base-300 p-4"
          >
            <div class="flex items-start justify-between gap-2">
              <div>
                <span class="font-semibold">{TemplateText.template_name(template)}</span>
                <span :if={template.is_builtin} class="badge badge-ghost badge-sm ml-2">
                  {gettext("Built-in")}
                </span>
              </div>
              <.button
                :if={not template.is_builtin and not @team.is_archived}
                id={"delete-template-#{template.id}"}
                phx-click="delete"
                phx-value-id={template.id}
                data-confirm={gettext("Delete this template?")}
                class="btn btn-ghost btn-xs"
              >
                {gettext("Delete")}
              </.button>
            </div>
            <ol class="mt-2 flex flex-wrap gap-1">
              <li
                :for={name <- TemplateText.template_column_names(template)}
                class="badge badge-outline badge-sm"
              >
                {name}
              </li>
            </ol>
          </li>
        </ul>
      </section>
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
