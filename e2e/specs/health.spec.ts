import { expect, test } from '@playwright/test'

test.describe('health endpoint', () => {
  test('[NFR-501] reports readiness over critical dependencies', async ({ request }) => {
    const response = await request.get('/api/v1/health')

    expect(response.status()).toBe(200)

    const body = await response.json()
    expect(body.status).toBe('ok')

    const names = body.checks.map((check: { name: string }) => check.name)
    expect(names).toContain('database')
    expect(names).toContain('jobs')

    for (const check of body.checks) {
      expect(check.status).toBe('ok')
    }
  })

  test('[NFR-501] answers liveness without touching dependencies', async ({ request }) => {
    const response = await request.get('/api/v1/health?probe=live')

    expect(response.status()).toBe(200)
    expect(await response.json()).toEqual({ status: 'ok', checks: [] })
  })
})
