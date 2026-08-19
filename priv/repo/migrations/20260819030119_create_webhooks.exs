defmodule SprintLens.Repo.Migrations.CreateWebhooks do
  @moduledoc """
  A team's outbound webhook and the record of what it has delivered
  (section 6.3 WEBHOOK_SUBSCRIPTION, FR-704 to FR-706).

  ## Why there is a deliveries table

  Section 6.3 gives the subscription a `last_delivery (json, optional)` field.
  FR-706 asks for something that one field cannot be: "failed deliveries MUST
  be retried with exponential backoff and recorded in a delivery log visible
  to the Team Lead". A log of one entry cannot show a retry, and showing the
  retries is the point — a lead looking at this page is asking "did it get
  through, and if not, how many times has it tried?".

  So the deliveries are their own table and `last_delivery` does not exist:
  two records of the same thing would only disagree.

  ## One webhook per team

  FR-704 says "a team MAY configure one outbound webhook", so `team_id` is
  unique. Sending the same event to two places is a feature nobody asked for
  and a second secret to keep.
  """

  use Ecto.Migration

  def change do
    create table(:webhook_subscriptions) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false

      add :url, :string, null: false
      add :secret, :string, null: false
      add :events, :string, null: false
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:webhook_subscriptions, [:team_id])

    create table(:webhook_deliveries) do
      add :subscription_id, references(:webhook_subscriptions, on_delete: :delete_all),
        null: false

      # The id sent in the delivery header, so a receiver's logs and this
      # table can be lined up when somebody asks what happened (§7.4).
      add :delivery_id, :string, null: false
      add :event, :string, null: false
      add :attempt, :integer, null: false, default: 1
      add :status, :string, null: false
      add :response_code, :integer
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create index(:webhook_deliveries, [:subscription_id, :inserted_at])
    create index(:webhook_deliveries, [:delivery_id])

    # An action is announced as due once. A daily sweep would otherwise send
    # the same reminder every morning until somebody closed the item, which
    # is how a team learns to ignore a channel (FR-704).
    alter table(:action_items) do
      add :due_notified_at, :utc_datetime
    end
  end
end
