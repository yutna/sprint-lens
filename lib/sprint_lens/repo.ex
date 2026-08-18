defmodule SprintLens.Repo do
  use Ecto.Repo,
    otp_app: :sprint_lens,
    adapter: Ecto.Adapters.SQLite3
end
