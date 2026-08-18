defmodule SprintLens.HealthTest do
  use SprintLens.DataCase

  alias SprintLens.Health

  describe "alive/0" do
    @tag req: ["NFR-501"]
    test "reports ok without probing any dependency" do
      assert Health.alive() == %{status: :ok, checks: []}
    end
  end

  describe "ready/0" do
    @tag req: ["NFR-501"]
    test "reports ok when every critical dependency answers" do
      report = Health.ready()

      assert report.status == :ok
      assert Enum.all?(report.checks, &(&1.status == :ok))
    end

    @tag req: ["NFR-501"]
    test "covers the database and the job runner" do
      names = Health.ready().checks |> Enum.map(& &1.name) |> Enum.sort()

      assert names == [:database, :jobs]
    end

    @tag req: ["NFR-501"]
    test "carries no detail while a check is passing" do
      assert Enum.all?(Health.ready().checks, &is_nil(&1.detail))
    end
  end

  describe "check_database/2" do
    @tag req: ["NFR-501"]
    test "passes against a working repo" do
      assert Health.check_database() == %{name: :database, status: :ok, detail: nil}
    end

    @tag req: ["NFR-501"]
    test "fails with a detail when the database answers with an error" do
      check = Health.check_database(SprintLens.Repo, "SELECT * FROM no_such_table")

      assert check.name == :database
      assert check.status == :error
      assert check.detail =~ "no_such_table"
    end

    @tag req: ["NFR-501"]
    test "fails rather than raising when the repo is not there at all" do
      check = Health.check_database(SprintLens.NotARepo)

      assert check.status == :error
      assert is_binary(check.detail)
    end
  end

  describe "check_jobs/1" do
    @tag req: ["NFR-501"]
    test "passes while the job runner is up" do
      assert Health.check_jobs() == %{name: :jobs, status: :ok, detail: nil}
    end

    @tag req: ["NFR-501"]
    test "fails when the job runner is not running" do
      check = Health.check_jobs(:no_such_supervisor)

      assert check.status == :error
      assert check.detail =~ "not running"
    end
  end

  describe "summarise/1" do
    @tag req: ["NFR-501"]
    test "one failing dependency makes the whole report unhealthy" do
      checks = [
        %{name: :database, status: :ok, detail: nil},
        %{name: :jobs, status: :error, detail: "down"}
      ]

      assert Health.summarise(checks).status == :error
    end

    @tag req: ["NFR-501"]
    test "an empty check list is healthy" do
      assert Health.summarise([]).status == :ok
    end
  end

  describe "http_status/1" do
    @tag req: ["NFR-501"]
    test "serves 200 when healthy and 503 when a dependency is down" do
      assert Health.http_status(%{status: :ok, checks: []}) == 200
      assert Health.http_status(%{status: :error, checks: []}) == 503
    end

    @tag req: ["NFR-501"]
    test "a real report round-trips to a status" do
      assert Health.ready() |> Health.http_status() == 200
    end
  end
end
