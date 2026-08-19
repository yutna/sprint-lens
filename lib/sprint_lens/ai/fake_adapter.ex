defmodule SprintLens.AI.FakeAdapter do
  @moduledoc """
  An adapter that answers without a model (AI-004).

  This is not a mock. It is a real implementation of
  `SprintLens.AI.Adapter` that the test and e2e environments run against,
  which is what makes AI-004's "swap providers without app changes" a fact
  about this codebase rather than a claim in a document: the suite exercises
  every path above the adapter, against a different adapter from production,
  and nothing above the boundary knows.

  Its answers are derived from the input, so a test can assert that the
  content flowed rather than that something arrived. Its failures are
  switchable per test, which is how AI-006's degradation gets exercised
  without waiting for a real timeout.
  """

  @behaviour SprintLens.AI.Adapter

  @key {__MODULE__, :behaviour}

  @doc """
  Makes the next calls fail, for the process that sets it.

  Per-process rather than global: the suite is asynchronous where it can be,
  and a global switch would make one test's failure another test's surprise.
  """
  @spec fail(term()) :: :ok
  def fail(reason \\ :provider_unavailable) do
    Process.put(@key, {:fail, reason})

    :ok
  end

  @doc """
  Makes the next call take longer than it is allowed to (AI-006).
  """
  @spec time_out() :: :ok
  def time_out do
    Process.put(@key, :timeout)

    :ok
  end

  @doc """
  Makes the next call blow up rather than return, which is the failure a
  provider library is most likely to produce.
  """
  @spec raise_error(String.t()) :: :ok
  def raise_error(message \\ "the provider exploded") do
    Process.put(@key, {:raise, message})

    :ok
  end

  @doc """
  Back to answering normally.
  """
  @spec succeed() :: :ok
  def succeed do
    Process.delete(@key)

    :ok
  end

  @impl SprintLens.AI.Adapter
  def generate(request, timeout_ms) do
    case Process.get(@key) do
      {:fail, reason} -> {:error, reason}
      {:raise, message} -> raise RuntimeError, message
      :timeout -> {:error, {:timeout, timeout_ms}}
      nil -> {:ok, answer(request)}
    end
  end

  # Derived from the input rather than canned, so a test that asserts on the
  # output is asserting that the right content reached the adapter.
  defp answer(%{type: :session_summary, input: input}) do
    markdown("""
    ## Summary

    #{count(input, :cards)} cards, #{count(input, :notes)} notes.

    ### Themes

    #{bullets(input, :cards)}
    """)
  end

  defp answer(%{type: :clustering, input: input}) do
    json(%{
      groups: [
        %{label: "Suggested cluster", card_ids: input |> Map.get(:cards, []) |> Enum.map(& &1.id)}
      ]
    })
  end

  defp answer(%{type: :action_draft, input: input}) do
    markdown("Follow up on: #{Map.get(input, :topic, "the discussion")}")
  end

  defp answer(%{type: :recurring_themes, input: input}) do
    markdown("""
    ## Recurring

    #{bullets(input, :sessions)}
    """)
  end

  defp answer(%{type: :icebreakers, input: input}) do
    json(%{prompts: ["What surprised you this sprint? (#{Map.get(input, :language)})"]})
  end

  defp answer(%{type: :translation, input: input, language: language}) do
    markdown("[#{language}] #{Map.get(input, :text, "")}")
  end

  defp markdown(content), do: %{format: "markdown", content: String.trim(content)}
  defp json(data), do: %{format: "json", content: Jason.encode!(data)}

  defp count(input, key), do: input |> Map.get(key, []) |> length()

  defp bullets(input, key) do
    input
    |> Map.get(key, [])
    |> Enum.map_join("\n", fn item -> "- " <> label(item) end)
  end

  defp label(%{text: text}), do: text
  defp label(%{title: title}), do: title
end
