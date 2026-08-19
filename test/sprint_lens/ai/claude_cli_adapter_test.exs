defmodule SprintLens.AI.ClaudeCliAdapterTest do
  @moduledoc """
  The reference adapter, without the model (AI-004, AI-007, AI-008).

  Everything here is real except the subprocess: a sandbox directory is
  created, a prompt is written into it, an answer comes back through a
  runner the test supplies, and the directory is removed. The one thing that
  is stubbed is the thing that would otherwise cost money and a network
  connection.
  """

  use SprintLens.UnitCase, async: false

  alias SprintLens.AI.ClaudeCliAdapter, as: Adapter

  defmodule StubRunner do
    @moduledoc false

    def run(dir, prompt, timeout_ms) do
      send(self(), {:ran, dir, prompt, timeout_ms})

      case Process.get(:stub_result) do
        nil -> {~s({"result":"## Summary\\n\\nAll good."}), 0}
        other -> other
      end
    end
  end

  setup do
    Application.put_env(:sprint_lens, :ai_cli_runner, StubRunner)
    on_exit(fn -> Application.delete_env(:sprint_lens, :ai_cli_runner) end)

    %{
      request: %{
        type: :session_summary,
        language: "th",
        scope: ~w(cards notes),
        input: %{cards: [%{id: 1, text: "Deploys are slow"}]}
      }
    }
  end

  describe "the prompt (AI-007)" do
    @tag req: ["AI-007"]
    test "says what to do, in which language, with the content as JSON", ctx do
      prompt = Adapter.build_prompt(ctx.request)

      assert prompt =~ "Draft a structured recap"
      assert prompt =~ "Answer in Thai"
      assert prompt =~ "Reply with markdown"
      assert prompt =~ ~s("text": "Deploys are slow")
    end

    @tag req: ["AI-016"]
    test "and tells the model there are no names, because there are none", ctx do
      prompt = Adapter.build_prompt(ctx.request)

      assert prompt =~ "carries no names"
      assert prompt =~ "must not speculate"
    end

    @tag req: ["AI-007"]
    test "each feature asks its own question", _ctx do
      questions =
        for type <- [
              :session_summary,
              :clustering,
              :action_draft,
              :recurring_themes,
              :icebreakers,
              :translation
            ] do
          Adapter.build_prompt(%{type: type, language: "en", input: %{}})
        end

      assert length(Enum.uniq(questions)) == 6
      assert Enum.any?(questions, &(&1 =~ "Group the cards"))
      assert Enum.any?(questions, &(&1 =~ "Translate the text"))
    end

    @tag req: ["AI-007"]
    test "and the two that want structure ask for JSON", _ctx do
      for type <- [:clustering, :icebreakers] do
        assert Adapter.build_prompt(%{type: type, language: "en", input: %{}}) =~
                 "Reply with json"
      end
    end
  end

  describe "reading the CLI's answer (AI-007)" do
    @tag req: ["AI-007"]
    test "takes the model's text out of the tool's envelope", _ctx do
      assert Adapter.parse(~s({"result":"hello","cost":0.1})) == {:ok, "hello"}
      assert Adapter.parse(~s({"content":"hello"})) == {:ok, "hello"}
    end

    @tag req: ["AI-006"]
    test "and anything else is a failure rather than a guess", _ctx do
      assert Adapter.parse(~s({"nothing":"useful"})) == {:error, :unexpected_response}
      assert Adapter.parse("not json at all") == {:error, :invalid_json}
    end
  end

  describe "what the subprocess did (AI-006)" do
    @tag req: ["AI-007"]
    test "a clean exit is the answer", ctx do
      assert {:ok, %{format: "markdown", content: "hello"}} =
               Adapter.interpret({~s({"result":"hello"}), 0}, ctx.request)
    end

    @tag req: ["AI-006"]
    test "a non-zero exit keeps the first of what it said", ctx do
      assert {:error, {:exit_status, 1, message}} =
               Adapter.interpret({"  credentials not found\n", 1}, ctx.request)

      assert message == "credentials not found"
    end

    @tag req: ["AI-006"]
    test "and a runner that gave up passes its reason through", ctx do
      assert Adapter.interpret({:error, {:timeout, 60_000}}, ctx.request) ==
               {:error, {:timeout, 60_000}}
    end
  end

  describe "generate/2 (AI-008)" do
    @tag req: ["AI-008"]
    test "runs in a fresh directory, with the prompt in a file, and cleans up", ctx do
      assert {:ok, %{content: content}} = Adapter.generate(ctx.request, 5_000)

      assert content =~ "## Summary"
      assert_received {:ran, dir, prompt, 5_000}

      assert prompt =~ "Draft a structured recap"
      assert String.contains?(dir, "sprintlens-ai-")

      # The sandbox is gone, and so is the file that was in it (AI-008).
      refute File.dir?(dir)
      refute File.exists?(Path.join(dir, Adapter.prompt_file()))
    end

    @tag req: ["AI-008"]
    test "two jobs never share a directory", ctx do
      {:ok, _first} = Adapter.generate(ctx.request, 5_000)
      assert_received {:ran, first_dir, _prompt, _timeout}

      {:ok, _second} = Adapter.generate(ctx.request, 5_000)
      assert_received {:ran, second_dir, _prompt2, _timeout2}

      refute first_dir == second_dir
    end

    @tag req: ["AI-006"]
    test "and a failure from the runner comes back as one", ctx do
      Process.put(:stub_result, {"boom", 2})

      assert {:error, {:exit_status, 2, "boom"}} = Adapter.generate(ctx.request, 5_000)
    end

    @tag req: ["AI-006"]
    test "as does an answer that is not the shape it should be", ctx do
      Process.put(:stub_result, {~s({"unexpected":true}), 0})

      assert {:error, :unexpected_response} = Adapter.generate(ctx.request, 5_000)
    end
  end
end
