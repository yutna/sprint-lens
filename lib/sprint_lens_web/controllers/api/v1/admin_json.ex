defmodule SprintLensWeb.Api.V1.AdminJSON do
  @moduledoc """
  Serialises the administration surface (§7.2).

  The user list is the one place in this API where an email address appears:
  it is how an administrator tells two people with the same name apart, and
  FR-801 is the only requirement that asks for a list of everybody. Every
  other endpoint sends `UserJSON.summary/1`, which does not.
  """

  alias SprintLens.Accounts.User
  alias SprintLens.Admin.AuditEvent
  alias SprintLens.Admin.OrgSettings

  @doc """
  One person, as an administrator needs to see them (FR-801).
  """
  @spec user(User.t()) :: map()
  def user(%User{} = user) do
    %{
      id: user.id,
      display_name: user.display_name,
      email: user.email,
      language: user.language,
      is_active: user.is_active,
      is_org_admin: user.is_org_admin,
      is_erased: User.erased?(user),
      created_at: user.inserted_at
    }
  end

  @doc """
  One audit entry (FR-807).
  """
  @spec event(AuditEvent.t()) :: map()
  def event(%AuditEvent{} = event) do
    %{
      id: event.id,
      action: event.action,
      target: event.target,
      actor_id: event.actor_id,
      detail: AuditEvent.detail(event),
      occurred_at: event.inserted_at
    }
  end

  @doc """
  The organisation's settings (FR-802, FR-806).
  """
  @spec settings(OrgSettings.t()) :: map()
  def settings(%OrgSettings{} = settings) do
    %{
      default_language: settings.default_language,
      default_vote_budget: settings.default_vote_budget,
      retention_days: settings.retention_days,
      ai_enabled: settings.ai_enabled,
      webhooks_enabled: settings.webhooks_enabled
    }
  end
end
