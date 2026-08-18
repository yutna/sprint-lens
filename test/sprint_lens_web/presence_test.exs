defmodule SprintLensWeb.PresenceTest do
  use SprintLens.UnitCase, async: true

  alias SprintLensWeb.Presence

  setup do
    %{session_id: System.unique_integer([:positive])}
  end

  # Tracks from a throwaway process so the entry disappears when that process
  # exits — which is exactly how a participant closing their tab behaves.
  defp track(session_id, user_id, meta \\ %{}) do
    test = self()

    pid =
      spawn(fn ->
        Presence.track_user(self(), session_id, user_id, meta)
        send(test, :tracked)
        receive do: (:stop -> :ok)
      end)

    assert_receive :tracked
    pid
  end

  describe "topic/1" do
    @tag req: ["FR-307"]
    test "is distinct per session" do
      assert Presence.topic(1) != Presence.topic(2)
      assert Presence.topic(42) =~ "42"
    end
  end

  describe "track_user/4 and list_users/1" do
    @tag req: ["FR-307"]
    test "lists who is in the session", %{session_id: session_id} do
      track(session_id, 1, %{display_name: "Nok"})
      track(session_id, 2, %{display_name: "Ploy"})

      users = Presence.list_users(session_id)

      assert map_size(users) == 2
      assert users[1].display_name == "Nok"
      assert users[2].display_name == "Ploy"
    end

    @tag req: ["FR-213"]
    test "defaults a newly present participant to not ready", %{session_id: session_id} do
      track(session_id, 1)

      assert Presence.list_users(session_id)[1].ready == false
    end

    @tag req: ["FR-307"]
    test "counts a participant with two tabs open once", %{session_id: session_id} do
      track(session_id, 1, %{display_name: "Nok"})
      track(session_id, 1, %{display_name: "Nok"})

      assert map_size(Presence.list_users(session_id)) == 1
    end

    @tag req: ["FR-307"]
    test "keeps sessions isolated from each other", %{session_id: session_id} do
      other = System.unique_integer([:positive])

      track(session_id, 1)
      track(other, 2)

      assert Map.keys(Presence.list_users(session_id)) == [1]
      assert Map.keys(Presence.list_users(other)) == [2]
    end

    @tag req: ["FR-307"]
    test "drops a participant when their process goes away", %{session_id: session_id} do
      pid = track(session_id, 1)
      ref = Process.monitor(pid)

      send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      # Presence removal is asynchronous; retry until the tracker has caught up.
      assert eventually(fn -> Presence.list_users(session_id) == %{} end)
    end
  end

  describe "update_user/4" do
    @tag req: ["FR-213"]
    test "flips the ready flag without losing other metadata", %{session_id: session_id} do
      test = self()

      spawn(fn ->
        Presence.track_user(self(), session_id, 7, %{display_name: "Nok"})
        Presence.update_user(self(), session_id, 7, %{ready: true})
        send(test, :done)
        receive do: (:stop -> :ok)
      end)

      assert_receive :done

      meta = Presence.list_users(session_id)[7]
      assert meta.ready == true
      assert meta.display_name == "Nok"
    end
  end

  describe "ready_count/1" do
    @tag req: ["FR-213"]
    test "reports how many of the present participants are ready", %{session_id: session_id} do
      test = self()

      track(session_id, 1)
      track(session_id, 2)

      spawn(fn ->
        Presence.track_user(self(), session_id, 3, %{})
        Presence.update_user(self(), session_id, 3, %{ready: true})
        send(test, :done)
        receive do: (:stop -> :ok)
      end)

      assert_receive :done

      assert Presence.ready_count(session_id) == {1, 3}
    end

    @tag req: ["FR-213"]
    test "is zero of zero in an empty session", %{session_id: session_id} do
      assert Presence.ready_count(session_id) == {0, 0}
    end
  end

  describe "present?/2" do
    @tag req: ["FR-207"]
    test "tells whether a specific participant is connected", %{session_id: session_id} do
      track(session_id, 1)

      assert Presence.present?(session_id, 1)
      refute Presence.present?(session_id, 2)
    end
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> eventually(fun, attempts - 1)
    end
  end
end
