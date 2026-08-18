# Findings dialyzer reports that are not ours to fix.
#
# Every entry needs a reason. An ignore file that grows without explanation
# turns a static analyser into decoration.
[
  # Gettext's generated plural dispatch trips dialyzer's opaqueness check on
  # Expo.PluralForms. Thai has one plural form (nplurals: 1), which is the
  # shape that triggers it. Nothing in this repository can change it.
  {"lib/sprint_lens_web/gettext.ex", :call_without_opaque}
]
