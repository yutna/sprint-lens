defmodule SprintLens.Retro.SessionTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.Retro.Session

  describe "phases/0" do
    @tag req: ["FR-206"]
    test "are the six the spec lists, in order" do
      assert Session.phases() == [:checkin, :brainstorm, :group, :vote, :discuss, :wrapup]
    end
  end

  describe "states/0" do
    @tag req: ["FR-205"]
    test "are created, active and closed" do
      assert Session.states() == [:created, :active, :closed]
    end
  end

  describe "next_phase/1 and previous_phase/1" do
    @tag req: ["FR-206"]
    test "walk the six phases in order" do
      assert Session.next_phase(:checkin) == :brainstorm
      assert Session.next_phase(:discuss) == :wrapup
      assert Session.previous_phase(:brainstorm) == :checkin
      assert Session.previous_phase(:wrapup) == :discuss
    end

    @tag req: ["FR-206"]
    test "stop at the ends rather than wrapping around" do
      assert Session.next_phase(:wrapup) == nil
      assert Session.previous_phase(:checkin) == nil
    end

    @tag req: ["FR-206"]
    test "accept a session as well as a phase" do
      session = %Session{phase: "group"}

      assert Session.next_phase(session) == :vote
      assert Session.previous_phase(session) == :brainstorm
    end

    @tag req: ["FR-206"]
    test "an unknown phase has no neighbours" do
      assert Session.next_phase(:nonsense) == nil
      assert Session.previous_phase(:nonsense) == nil
    end
  end

  describe "ahead?/2" do
    @tag req: ["FR-206"]
    test "recognises a phase further along, which is what skipping means" do
      session = %Session{phase: "brainstorm"}

      assert Session.ahead?(session, :vote)
      refute Session.ahead?(session, :checkin)
      refute Session.ahead?(session, :brainstorm)
    end

    @tag req: ["FR-206"]
    test "is false for a phase that does not exist" do
      refute Session.ahead?(%Session{phase: "checkin"}, :nonsense)
      refute Session.ahead?(%Session{phase: "nonsense"}, :vote)
    end
  end

  describe "phase/1 and state/1" do
    @tag req: ["FR-205", "FR-206"]
    test "read the stored strings as atoms" do
      assert Session.phase(%Session{phase: "vote"}) == :vote
      assert Session.state(%Session{state: "closed"}) == :closed
    end

    @tag req: ["FR-205"]
    test "are nil for anything unrecognised" do
      assert Session.phase(%Session{phase: "nonsense"}) == nil
      assert Session.state(%Session{state: nil}) == nil
    end
  end

  describe "phase/1 and state/1 with atoms" do
    @tag req: ["FR-205", "FR-206"]
    test "pass an atom straight through, so callers need not care which they hold" do
      assert Session.phase(:vote) == :vote
      assert Session.state(:closed) == :closed
    end
  end

  describe "reveal_changeset/2" do
    @tag req: ["FR-209", "FR-404"]
    test "sets the two reveal flags independently" do
      changeset = Session.reveal_changeset(%Session{}, %{cards_revealed: true})

      assert Ecto.Changeset.get_field(changeset, :cards_revealed)
      refute Ecto.Changeset.get_field(changeset, :votes_revealed)
    end
  end

  describe "create_changeset/2" do
    @tag req: ["FR-201"]
    test "requires a title, a team and a facilitator" do
      changeset = Session.create_changeset(%Session{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors.title
      assert errors.team_id
      assert errors.facilitator_id
    end

    @tag req: ["FR-204"]
    test "generates a join code" do
      changeset =
        Session.create_changeset(%Session{}, %{title: "Retro", team_id: 1, facilitator_id: 1})

      code = Ecto.Changeset.get_field(changeset, :join_code)
      assert String.length(code) == 6
      assert code =~ ~r/^[A-Z0-9]+$/
    end

    @tag req: ["FR-204"]
    test "keeps a join code that has already been assigned" do
      session = %Session{join_code: "ABC123"}

      changeset =
        Session.create_changeset(session, %{title: "R", team_id: 1, facilitator_id: 1})

      assert Ecto.Changeset.get_field(changeset, :join_code) == "ABC123"
    end

    @tag req: ["FR-401"]
    test "refuses a vote budget outside the usable range" do
      changeset =
        Session.create_changeset(%Session{}, %{
          title: "Retro",
          team_id: 1,
          facilitator_id: 1,
          vote_budget: 0
        })

      assert %{vote_budget: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-210"]
    test "the anonymous mode is set at creation" do
      changeset =
        Session.create_changeset(%Session{}, %{
          title: "Retro",
          team_id: 1,
          facilitator_id: 1,
          is_anonymous: true
        })

      assert Ecto.Changeset.get_field(changeset, :is_anonymous)
    end
  end

  describe "generate_join_code/0" do
    @tag req: ["FR-204"]
    test "avoids characters that are confusable when read aloud" do
      codes = Enum.map(1..200, fn _ -> Session.generate_join_code() end)

      refute Enum.any?(codes, &String.contains?(&1, ["O", "0", "I", "1", "L"]))
    end

    @tag req: ["FR-204"]
    test "is not obviously repetitive" do
      assert Enum.uniq(Enum.map(1..50, fn _ -> Session.generate_join_code() end)) |> length() > 40
    end
  end

  describe "normalise_join_code/1" do
    @tag req: ["FR-204"]
    test "accepts what a person actually types" do
      assert Session.normalise_join_code("ab-cd 23") == "ABCD23"
      assert Session.normalise_join_code("") == ""
      assert Session.normalise_join_code(nil) == ""
    end
  end

  describe "timer_remaining/2" do
    @tag req: ["FR-208"]
    test "counts down from when the timer started, without the server ticking" do
      started = ~U[2026-08-18 09:00:00.000000Z]
      session = %Session{timer_duration_s: 300, timer_started_at: started}

      assert Session.timer_remaining(session, ~U[2026-08-18 09:00:00.000000Z]) == 300
      assert Session.timer_remaining(session, ~U[2026-08-18 09:02:00.000000Z]) == 180
    end

    @tag req: ["FR-208"]
    test "never goes below zero once the timer has expired" do
      session = %Session{
        timer_duration_s: 60,
        timer_started_at: ~U[2026-08-18 09:00:00.000000Z]
      }

      assert Session.timer_remaining(session, ~U[2026-08-18 09:05:00.000000Z]) == 0
    end

    @tag req: ["FR-208"]
    test "a paused timer keeps what was left of it" do
      session = %Session{timer_duration_s: 300, timer_started_at: nil, timer_remaining_s: 42}

      assert Session.timer_remaining(session, DateTime.utc_now()) == 42
    end

    @tag req: ["FR-208"]
    test "is nil when no timer has been set" do
      assert Session.timer_remaining(%Session{}, DateTime.utc_now()) == nil
    end
  end

  describe "timer_running?/1" do
    @tag req: ["FR-208"]
    test "distinguishes running from paused and unset" do
      assert Session.timer_running?(%Session{timer_started_at: DateTime.utc_now()})
      refute Session.timer_running?(%Session{timer_started_at: nil, timer_remaining_s: 10})
      refute Session.timer_running?(%Session{})
    end
  end

  describe "state_changeset/2" do
    @tag req: ["FR-205", "FR-215"]
    test "closing stamps the time, which the recap and retention need" do
      changeset = Session.state_changeset(%Session{state: "active"}, "closed")

      assert Ecto.Changeset.get_change(changeset, :state) == "closed"
      assert %DateTime{} = Ecto.Changeset.get_change(changeset, :closed_at)
    end

    @tag req: ["FR-205"]
    test "starting does not stamp a close time" do
      changeset = Session.state_changeset(%Session{state: "created"}, "active")

      refute Ecto.Changeset.get_change(changeset, :closed_at)
    end
  end
end
