defmodule SprintLens.AI.Adapter do
  @moduledoc """
  What an AI provider has to be able to do (AI-004).

  One callback, because there is only one thing this application asks of a
  model: here is a prepared request, give me back a suggestion or an error.
  Everything else — which provider, which credentials, which flags — belongs
  to the adapter and to configuration, which is the whole point of AI-004's
  "deployments can swap providers without app changes".

  The proof that the interface is provider-agnostic is that the test suite
  runs against a different adapter from production, and nothing above this
  line knows.
  """

  alias SprintLens.AI.Suggestion

  @typedoc """
  What the adapter is asked to do: which feature, in which language, over
  which content. The content has already been through
  `SprintLens.AI.Scope.build/2`, which is where AI-015 and AI-016 are
  enforced — an adapter is never handed anything it should not send.
  """
  @type request :: %{
          type: Suggestion.type(),
          language: String.t(),
          scope: [String.t()],
          input: map()
        }

  @typedoc """
  What came back: the format and content of §5.2's `output` object.
  """
  @type response :: %{format: String.t(), content: String.t()}

  @doc """
  Runs one request, or says why it could not.

  `timeout_ms` is AI-006's timeout and the adapter is responsible for
  honouring it — a provider that hangs is the failure this callback exists to
  turn into a retryable error rather than a stuck job.
  """
  @callback generate(request(), timeout_ms :: pos_integer()) ::
              {:ok, response()} | {:error, term()}

  @doc """
  The adapter this deployment uses (AI-004).
  """
  @spec current() :: module()
  def current do
    Application.get_env(:sprint_lens, :ai_adapter, SprintLens.AI.FakeAdapter)
  end
end
