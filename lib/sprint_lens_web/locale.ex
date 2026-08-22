defmodule SprintLensWeb.Locale do
  @moduledoc """
  Decides which language to render in, and renders dates, times and numbers
  according to it (FR-906, FR-907, FR-908).

  The order of preference is deliberate:

    1. the signed-in user's saved choice, so it follows them between devices
       (FR-003, FR-907);
    2. a choice made in this browser session by someone with no account yet,
       stored in the session cookie by `SprintLensWeb.LocaleController`;
    3. the browser's `accept-language`, so a first-time visitor gets something
       sensible before they have chosen anything;
    4. the organisation default, which is Thai unless an admin changes it
       (FR-802, FR-906).

  Stored values stay ISO 8601 UTC; only the rendering is localised (FR-908).
  """

  alias SprintLens.Accounts
  alias SprintLens.Cldr

  @supported ~w(th en)

  @doc """
  The languages the UI is available in.
  """
  @spec supported() :: [String.t()]
  def supported, do: @supported

  @doc """
  The organisation-wide default language (FR-802). Thai until configured
  otherwise.
  """
  @spec default() :: String.t()
  def default, do: Accounts.default_language()

  @doc """
  Picks a locale from a user, a session choice and an `accept-language`
  header, any of which may be absent.
  """
  @spec resolve(map() | nil, String.t() | nil, String.t() | nil) :: String.t()
  def resolve(user, accept_language \\ nil, session_locale \\ nil)

  def resolve(%{language: language}, accept_language, session_locale) do
    normalise(language) || resolve(nil, accept_language, session_locale)
  end

  def resolve(_user, accept_language, session_locale) do
    normalise(session_locale) || from_accept_language(accept_language) || default()
  end

  @doc """
  What a `live_session` has to carry from the request into the LiveView.

  The plug pipeline and the LiveView run in different processes, so the hook
  re-resolves the locale rather than inheriting it. For that to give the same
  answer it needs the same inputs, and one of them — the browser's
  `accept-language` — is not part of the session by default.

  It was the missing input. A signed-out visitor whose browser asks for
  English got an English first paint from the plug, and then Thai the moment
  the socket connected and the hook resolved without the header. On the sign
  in and registration pages that was a visible flicker between two languages.
  """
  @spec live_session(Plug.Conn.t()) :: %{String.t() => String.t() | nil}
  def live_session(conn) do
    %{"accept_language" => accept_language(conn)}
  end

  defp accept_language(conn) do
    case Plug.Conn.get_req_header(conn, "accept-language") do
      [header | _rest] -> header
      [] -> nil
    end
  end

  @doc """
  Makes `locale` the active one for the current process: Gettext for UI
  strings, CLDR for dates and numbers.
  """
  @spec put(String.t()) :: String.t()
  def put(locale) do
    locale = normalise(locale) || default()

    Gettext.put_locale(SprintLensWeb.Gettext, locale)
    Cldr.put_locale(locale)

    locale
  end

  @doc """
  The locale currently active on this process.
  """
  @spec current() :: String.t()
  def current, do: Gettext.get_locale(SprintLensWeb.Gettext)

  @doc """
  Whether a value names a language the UI supports.
  """
  @spec supported?(term()) :: boolean()
  def supported?(language), do: normalise(language) != nil

  @doc """
  Formats a `DateTime` for display, in the active locale (FR-908).

  Times are stored in UTC and rendered in the viewer's zone (section 11), so
  the caller passes the zone it wants; the default keeps UTC rather than
  silently guessing.

  A medium date and a short time: "22 ส.ค. 2026 08:27". A medium *time* also
  carries the seconds, and every place this is called is a due date, a closed
  date or a scheduled slot — none of which happen on a particular second, and
  all of which were reading as `08:27:22`.
  """
  @spec format_datetime(DateTime.t(), keyword()) :: String.t()
  def format_datetime(%DateTime{} = datetime, opts \\ []) do
    {zone, opts} = Keyword.pop(opts, :time_zone, "Etc/UTC")

    opts =
      opts
      |> Keyword.put_new(:date_format, :medium)
      |> Keyword.put_new(:time_format, :short)

    datetime
    |> DateTime.shift_zone!(zone)
    |> Cldr.DateTime.to_string!(Keyword.put(opts, :locale, current()))
  end

  @doc """
  Formats a `Date` for display, in the active locale (FR-908).
  """
  @spec format_date(Date.t(), keyword()) :: String.t()
  def format_date(%Date{} = date, opts \\ []) do
    opts = Keyword.put_new(opts, :format, :medium)

    Cldr.Date.to_string!(date, Keyword.put(opts, :locale, current()))
  end

  @doc """
  Formats a number for display, in the active locale (FR-908).
  """
  @spec format_number(number(), keyword()) :: String.t()
  def format_number(number, opts \\ []) do
    Cldr.Number.to_string!(number, Keyword.put(opts, :locale, current()))
  end

  # "en-GB;q=0.9, th;q=0.8" -> "en". Ignores quality ordering: with only two
  # supported languages, first mention wins and that is close enough to be
  # worth the simplicity.
  defp from_accept_language(nil), do: nil

  defp from_accept_language(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(fn part ->
      part |> String.split(";") |> hd() |> String.trim() |> String.split("-") |> hd()
    end)
    |> Enum.find_value(&normalise/1)
  end

  defp normalise(value) when is_binary(value) do
    downcased = String.downcase(value)
    if downcased in @supported, do: downcased
  end

  defp normalise(value) when is_atom(value) and not is_nil(value) do
    normalise(Atom.to_string(value))
  end

  defp normalise(_value), do: nil
end
