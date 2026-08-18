defmodule SprintLens.Cldr do
  @moduledoc """
  Locale-aware formatting for dates, times and numbers (FR-908).

  Values are always stored as ISO 8601 in UTC; this module exists only for the
  presentation edge. Thai and English are the two locales the UI supports
  (FR-906), with Thai the default.
  """

  use Cldr,
    otp_app: :sprint_lens,
    locales: ["th", "en"],
    default_locale: "th",
    providers: [Cldr.Number, Cldr.DateTime, Cldr.Calendar],
    gettext: SprintLensWeb.Gettext,
    generate_docs: false
end
