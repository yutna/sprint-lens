# Findings dialyzer reports that are not ours to fix.
#
# Every entry needs a reason. An ignore file that grows without explanation
# turns a static analyser into decoration.
[
  # Gettext's generated plural dispatch trips dialyzer's opaqueness check on
  # Expo.PluralForms. Thai has one plural form (nplurals: 1), which is the
  # shape that triggers it. Nothing in this repository can change it.
  {"lib/sprint_lens_web/gettext.ex", :call_without_opaque},
  # `Ecto.Multi.t()` is opaque and its struct holds a `MapSet`, which is also
  # opaque. Piping `Multi.new()` into `Multi.insert/3` — the documented usage
  # — trips the nested-opaqueness check. Nothing here can change it either.
  # Applies to every module that builds a multi.
  {"lib/sprint_lens/teams.ex", :call_without_opaque},
  {"lib/sprint_lens/retro.ex", :call_without_opaque},
  {"lib/sprint_lens/retro/board.ex", :call_without_opaque},
  {"lib/sprint_lens/admin.ex", :call_without_opaque}
]
