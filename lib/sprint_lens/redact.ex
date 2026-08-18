defmodule SprintLens.Redact do
  @moduledoc """
  Strips content that must never reach a log line.

  Two rules from the spec meet here:

    * NFR-502 — card text and personal data stay out of info-level logs.
    * AI-017 — AI requests and responses are logged with content redacted,
      keeping only type, timing, size and outcome.
    * NFR-205 — secrets never get logged.

  Anything that logs a payload passes it through `payload/1` first.
  """

  @redacted "[REDACTED]"

  # Field names whose values are either personal data, user content, or
  # secrets. Matched case-insensitively against both atom and string keys.
  @sensitive_keys ~w(
    text
    word
    note
    notes
    title
    description
    label
    hint
    content
    output
    prompt
    email
    display_name
    avatar_url
    password
    hashed_password
    secret
    token
    api_key
    authorization
    signature
  )

  @doc """
  Redacts sensitive values anywhere in a nested map or list, replacing them
  with a marker rather than dropping the key — a redacted field still tells an
  operator that the field was present.

  Values are replaced by their size where a size is meaningful, which is what
  AI-017 asks for.
  """
  @spec payload(term()) :: term()
  def payload(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, inner} ->
      if sensitive?(key) do
        {key, redact_value(inner)}
      else
        {key, payload(inner)}
      end
    end)
  end

  def payload(value) when is_list(value), do: Enum.map(value, &payload/1)
  def payload(value), do: value

  @doc """
  Whether a key names a field that must be redacted.
  """
  @spec sensitive?(atom() | String.t()) :: boolean()
  def sensitive?(key) when is_atom(key), do: sensitive?(Atom.to_string(key))
  def sensitive?(key) when is_binary(key), do: String.downcase(key) in @sensitive_keys

  @doc """
  The marker written in place of a redacted value.
  """
  @spec marker() :: String.t()
  def marker, do: @redacted

  defp redact_value(value) when is_binary(value), do: "#{@redacted} (#{byte_size(value)} bytes)"
  defp redact_value(value) when is_list(value), do: "#{@redacted} (#{length(value)} items)"
  defp redact_value(nil), do: nil
  defp redact_value(_value), do: @redacted
end
