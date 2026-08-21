# Requirements that cannot be proven by an automated test in this repository,
# each with the reason. `mix sprint_lens.trace` reports these as documented
# gaps rather than failures — and warns if a test later starts covering one,
# so this list cannot quietly rot.
#
# Adding an entry here is a deliberate act. The bar is "no test could
# establish this from inside the application", not "this is hard to test".

%{
  "NFR-204" =>
    "TLS termination is a deployment concern (reverse proxy / load balancer); the app cannot assert on it.",
  "NFR-301" =>
    "Legal conformance with Thailand's PDPA. The mechanisms it relies on (FR-805, NFR-303, NFR-304) are tested individually.",
  "NFR-302" =>
    "Backup ageing is a property of the deployment's backup policy. The purge mechanism itself is tested under FR-803.",
  "NFR-303" =>
    "A 30-day completion SLA cannot be observed in a test run. The erasure mechanism it bounds is tested under FR-805.",
  "NFR-403" =>
    "Backup and restore with standard tools is a deployment property. What the application commits to is that all of its state is in one database, with no extensions and no types a standard dump does not carry — true of both adapters, and structural rather than assertable.",
  "NFR-601" =>
    "Browser support matrix. Approximated by running the Playwright suite on chromium, firefox and webkit, but the 'last two major versions' claim is not assertable.",
  "NFR-603" =>
    "'No plugins or native installs required' is a property of what the app does not do; there is nothing to assert."
}
