defmodule SprintLensWeb.ErrorHTML do
  @moduledoc """
  Renders an error page for a request that wanted HTML.

  Phoenix's generated version returns
  `Phoenix.Controller.status_message_from_template/1`, which reads the status
  out of the template name and hands back an English phrase. It is English by
  construction: it never consults Gettext, so a Thai visitor who hit a missing
  page was told "Not Found" no matter what language the rest of the interface
  was in.

  Only the statuses a person browsing this application can actually reach are
  translated. Anything else falls through to Phoenix's phrase, which is the
  right answer for a status nobody was expecting: an untranslated word beats a
  blank page.

  These are still bare phrases rather than designed pages. FR-919 asks for a
  human-readable message with a way forward, and a way forward needs a layout,
  a link and a mascot — that is the UI overhaul's work, not this one's.
  """

  use SprintLensWeb, :html

  def render(template, _assigns), do: message(template)

  defp message("400.html"), do: gettext("Bad Request")
  defp message("401.html"), do: gettext("Unauthorized")
  defp message("403.html"), do: gettext("Forbidden")
  defp message("404.html"), do: gettext("Not Found")
  defp message("422.html"), do: gettext("Unprocessable Entity")
  defp message("429.html"), do: gettext("Too Many Requests")
  defp message("500.html"), do: gettext("Internal Server Error")
  defp message(template), do: Phoenix.Controller.status_message_from_template(template)
end
