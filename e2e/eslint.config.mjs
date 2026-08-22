// The Playwright suite is the only TypeScript in the project, and until now
// nothing checked it at all. `eslint-plugin-playwright` is the part that
// earns its place: it catches the mistakes that make a browser test pass for
// the wrong reason — a missing await on an expect, a conditional assertion, a
// focused test left behind.
import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import playwright from 'eslint-plugin-playwright'
import prettier from 'eslint-config-prettier'

export default tseslint.config(
  {
    ignores: [
      'node_modules/',
      'playwright-report/',
      'test-results/',
      'blob-report/',
      // Throwaway scripts live here because this is where `@playwright/test`
      // resolves from, and they are git-ignored under the same names. Linting
      // a file nobody will read again only ever fails somebody else's run.
      '.*.mjs',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['specs/**/*.ts'],
    ...playwright.configs['flat/recommended'],
    rules: {
      ...playwright.configs['flat/recommended'].rules,
      // A skip with a condition and a reason is a statement about where a
      // capability exists — clipboard permissions are Chromium-only under
      // Playwright — not a test somebody switched off and forgot. The
      // unconditional kind still fails.
      'playwright/no-skipped-test': ['error', { allowConditional: true }],
    },
  },
  prettier,
)
