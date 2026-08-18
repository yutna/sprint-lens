defmodule SprintLens.LogFormatter do
  @moduledoc """
  Emits one JSON object per log line (NFR-502).

  Every line carries the request correlation id when one is in scope, so a
  single request can be followed across the HTTP entry point, the context
  layer and any job it enqueues.

  This is an Erlang `:logger` formatter, wired up in `config/config.exs` as
  `formatter: {SprintLens.LogFormatter, %{}}`.
  """

  @doc """
  Formats one log event as a JSON line.

  Metadata that cannot be represented as JSON (pids, references, functions) is
  inspected rather than dropped, so a log line never fails to render.
  """
  @spec format(:logger.log_event(), :logger.formatter_config()) :: IO.chardata()
  def format(%{level: level, msg: msg, meta: meta}, config) do
    entry =
      %{
        "level" => Atom.to_string(level),
        "time" => timestamp(meta),
        "message" => message(msg)
      }
      |> Map.merge(metadata(meta, config))

    [Jason.encode_to_iodata!(entry), ?\n]
  rescue
    # A formatter that raises takes the whole logger handler down with it, so
    # fall back to something printable rather than losing the line.
    error -> ["{\"level\":\"error\",\"message\":", inspect(Exception.message(error)), "}\n"]
  end

  @drop_metadata [
    :time,
    :gl,
    :report_cb,
    :error_logger,
    :domain,
    :ansi_color,
    :mfa,
    :file,
    :line,
    :pid,
    :crash_reason,
    :initial_call
  ]

  defp metadata(meta, config) do
    keep = Map.get(config, :metadata, :all)

    meta
    |> Map.drop(@drop_metadata)
    |> filter_keys(keep)
    |> Map.new(fn {key, value} -> {to_string(key), encodable(value)} end)
  end

  defp filter_keys(meta, :all), do: meta
  defp filter_keys(meta, keys) when is_list(keys), do: Map.take(meta, keys)

  defp timestamp(%{time: microseconds}) when is_integer(microseconds) do
    microseconds
    |> DateTime.from_unix!(:microsecond)
    |> DateTime.to_iso8601()
  end

  defp timestamp(_meta), do: nil

  defp message({:string, chardata}), do: IO.chardata_to_string(chardata)
  defp message({:report, report}) when is_map(report), do: inspect(report)
  defp message({:report, report}), do: inspect(report)

  defp message({format, args}) when is_list(format) or is_binary(format) do
    format |> :io_lib.format(args) |> IO.chardata_to_string()
  end

  defp encodable(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp encodable(nil), do: nil
  defp encodable(value) when is_atom(value), do: Atom.to_string(value)
  defp encodable(value) when is_list(value), do: Enum.map(value, &encodable/1)

  defp encodable(%{__struct__: _} = value), do: inspect(value)

  defp encodable(value) when is_map(value) do
    Map.new(value, fn {key, inner} -> {to_string(key), encodable(inner)} end)
  end

  defp encodable(value), do: inspect(value)
end
