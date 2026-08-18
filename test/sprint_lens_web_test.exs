defmodule SprintLensWebTest do
  use SprintLens.UnitCase, async: true

  describe "static_paths/0" do
    test "serves only the asset directories, never source or uploads" do
      paths = SprintLensWeb.static_paths()

      assert "assets" in paths
      assert "favicon.ico" in paths
      assert "robots.txt" in paths
      refute "uploads" in paths
    end
  end

  describe "__using__ entry points" do
    # These return quoted expressions injected by `use SprintLensWeb, :thing`.
    # Asserting they build keeps a typo in one of them from only surfacing the
    # first time a milestone happens to use that entry point.
    for entry <- [
          :router,
          :channel,
          :controller,
          :live_view,
          :live_component,
          :html,
          :verified_routes
        ] do
      test "#{entry} returns a quoted expression" do
        assert {form, _meta, _args} = apply(SprintLensWeb, unquote(entry), [])
        assert is_atom(form)
      end
    end
  end
end
