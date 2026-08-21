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
