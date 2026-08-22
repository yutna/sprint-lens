defmodule SprintLensWeb.StaticAssetsTest do
  @moduledoc """
  That every icon the layout links to is actually served.

  `Plug.Static` is configured with an explicit allowlist of top-level paths.
  A file left out of it is not a 500 and not a warning — it is a plain 404 in
  production with no other symptom, which is the quietest way for an icon set
  to look finished and be broken. So the test fetches them rather than
  comparing two lists that could both be wrong.
  """

  use SprintLensWeb.ConnCase

  # Written out rather than derived from `File.ls!/1`: the point is to catch a
  # file that exists and is not reachable, and a list built from the directory
  # would move whenever the directory did.
  @root_assets ~w(/favicon.ico /apple-touch-icon.png /site.webmanifest /robots.txt)
  @image_assets ~w(
    /images/logo-mark.svg
    /images/favicon.svg
    /images/icon-192.png
    /images/icon-512.png
    /images/og-image.png
    /images/mascot-waiting.svg
    /images/mascot-empty.svg
    /images/mascot-error.svg
    /images/mascot-done.svg
  )

  describe "the static allowlist" do
    @tag req: ["FR-911"]
    test "serves everything a browser asks for at the root", %{conn: conn} do
      for path <- @root_assets do
        assert conn |> get(path) |> response(200) != "",
               "#{path} is not served — add it to SprintLensWeb.static_paths/0"
      end
    end

    @tag req: ["FR-911"]
    test "serves every image the layout and the empty states use", %{conn: conn} do
      for path <- @image_assets do
        assert conn |> get(path) |> response(200) != "", "#{path} is not served"
      end
    end

    @tag req: ["FR-911"]
    test "and nothing outside it", %{conn: conn} do
      assert conn |> get("/mix.exs") |> response(404)
    end
  end

  describe "the typefaces" do
    # Vendored rather than fetched: `AGENTS.md` forbids the layouts
    # referencing anything external, and a retrospective tool should not tell
    # a third party who is reading it.
    @tag req: ["FR-906"]
    test "are served from this application, in both scripts", %{conn: conn} do
      for path <- ~w(
            /fonts/ibm-plex-sans-thai-400-thai.woff2
            /fonts/ibm-plex-sans-thai-400-latin.woff2
            /fonts/ibm-plex-sans-thai-600-thai.woff2
            /fonts/mitr-500-thai.woff2
            /fonts/mitr-500-latin.woff2
          ) do
        assert conn |> get(path) |> response(200) != "", "#{path} is not served"
      end
    end

    # The Open Font License requires the licence to travel with the files.
    @tag req: ["NFR-501"]
    test "ship with the licence that permits shipping them" do
      for licence <- ~w(OFL-IBMPlexSansThai.txt OFL-Mitr.txt) do
        text = File.read!("priv/static/fonts/#{licence}")

        assert text =~ "SIL Open Font License"
        assert text =~ "Copyright"
      end
    end
  end

  describe "the icons themselves" do
    @tag req: ["FR-911"]
    test "the favicon is the format its extension claims" do
      # It was a sixty-four pixel PNG called .ico, which is what the generator
      # ships. Bytes 2 and 3 of a real ICO are its type: 1 for an icon.
      assert <<0, 0, 1, 0, count, 0, _rest::binary>> = File.read!("priv/static/favicon.ico")
      assert count == 3, "expected 16, 32 and 48 pixel entries, got #{count}"
    end

    @tag req: ["FR-911"]
    test "no trace of the framework's bird is left" do
      refute File.exists?("priv/static/images/logo.svg")
    end
  end
end
