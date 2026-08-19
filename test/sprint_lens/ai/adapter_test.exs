defmodule SprintLens.AI.AdapterTest do
  @moduledoc """
  The adapter boundary (AI-004).

  AI-004 asks that "AI calls go through a provider-agnostic adapter interface
  so deployments can swap providers without app changes". The proof is this
  module plus the fact that the entire suite runs against a different adapter
  from production and nothing above the boundary knows: no test anywhere sets
  a provider, mentions a model, or knows that the reference implementation is
  a subprocess.
  """

  use SprintLens.UnitCase, async: false

  alias SprintLens.AI.Adapter
  alias SprintLens.AI.ClaudeCliAdapter
  alias SprintLens.AI.FakeAdapter

  @tag req: ["AI-004"]
  test "which provider is used is configuration, not code" do
    assert Adapter.current() == FakeAdapter

    Application.put_env(:sprint_lens, :ai_adapter, ClaudeCliAdapter)
    on_exit(fn -> Application.put_env(:sprint_lens, :ai_adapter, FakeAdapter) end)

    assert Adapter.current() == ClaudeCliAdapter
  end

  @tag req: ["AI-004"]
  test "and a deployment that configures nothing still has one" do
    Application.delete_env(:sprint_lens, :ai_adapter)
    on_exit(fn -> Application.put_env(:sprint_lens, :ai_adapter, FakeAdapter) end)

    assert Adapter.current() == FakeAdapter
  end

  @tag req: ["AI-004"]
  test "both implementations answer the same call" do
    for module <- [FakeAdapter, ClaudeCliAdapter] do
      Code.ensure_loaded!(module)

      assert function_exported?(module, :generate, 2)
      assert Adapter in module.__info__(:attributes)[:behaviour]
    end
  end
end
