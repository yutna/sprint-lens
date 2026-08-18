import { defineConfig, devices } from '@playwright/test'

const PORT = Number(process.env.E2E_PORT ?? 4010)
// `localhost`, not `127.0.0.1`: the app builds absolute URLs (the emailed
// sign-in link) from the endpoint's configured host, which is `localhost`.
// Browsing one and following a link to the other crosses a cookie origin
// boundary, and the session silently does not come along.
const BASE_URL = `http://localhost:${PORT}`

/**
 * Playwright drives the app the way a person would, which is the only way to
 * verify the acceptance scenarios in section 10 of the spec:
 *
 *   - 10.1 to 10.5 need several browser contexts open at once so that a
 *     facilitator and a participant can be observed staying in sync (FR-306).
 *   - 10.7 needs a real touch device at 375px with a dark colour scheme.
 *   - NFR-601 names Chrome, Edge, Firefox and Safari; chromium, firefox and
 *     webkit are the closest this suite can get to that matrix.
 *
 * Tests declare which requirements they cover with a bracketed prefix in the
 * title, for example `test('[FR-902] one column at a time', ...)`. The
 * `mix sprint_lens.trace` task reads those and fails if a requirement has no
 * test anywhere in either suite.
 */
export default defineConfig({
  testDir: './specs',
  // Every spec drives a shared SQLite database through a real server, and
  // SQLite takes one writer at a time. Files run serially for the same reason
  // the ExUnit database tests do.
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  timeout: 60_000,
  expect: {
    // FR-306 board changes must reach every participant within NFR-102's two
    // second budget. Allowing a little headroom keeps the suite from being a
    // flaky performance test, while still failing on a real regression.
    timeout: 5_000,
  },
  use: {
    baseURL: BASE_URL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    locale: 'th-TH',
    timezoneId: 'Asia/Bangkok',
  },
  projects: [
    // The mobile scenarios assert one column at a time and no sideways
    // scrolling, which are false at a desktop width — so the desktop projects
    // have to leave them alone rather than run them and fail.
    {
      name: 'chromium',
      testIgnore: /.*\.mobile\.spec\.ts/,
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      testIgnore: /.*\.mobile\.spec\.ts/,
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      testIgnore: /.*\.mobile\.spec\.ts/,
      use: { ...devices['Desktop Safari'] },
    },
    {
      // Scenario 10.7: a member on a 375px wide mobile browser, Thai, dark
      // theme, no dragging and no horizontal scrolling.
      name: 'mobile',
      testMatch: /.*\.mobile\.spec\.ts/,
      use: {
        ...devices['iPhone SE'],
        // Playwright's iPhone SE profile is the 320 px first generation, and
        // scenario 10.7 names 375 px. The touch and mobile flags come from the
        // profile; only the viewport is ours.
        viewport: { width: 375, height: 667 },
        colorScheme: 'dark',
      },
    },
  ],
  webServer: {
    command: 'cd .. && MIX_ENV=e2e mix phx.server',
    url: `${BASE_URL}/api/v1/health`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    stdout: 'pipe',
    stderr: 'pipe',
  },
})
