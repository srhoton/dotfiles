# TypeScript Rules

Only non-obvious, shop-specific decisions. Standard TS/testing/security practice is assumed.

## tsconfig — the non-default flags we require

Beyond `"strict": true`, these are the ones that actually change behavior and would not be guessed:

```jsonc
"noUncheckedIndexedAccess": true,      // indexing yields T | undefined
"exactOptionalPropertyTypes": true,
"noPropertyAccessFromIndexSignature": true,
"noImplicitOverride": true,
"noImplicitReturns": true,
"noFallthroughCasesInSwitch": true,
"noUnusedLocals": true,
"noUnusedParameters": true,
"allowUnreachableCode": false,
"declaration": true, "declarationMap": true, "sourceMap": true
```

Module resolution: for Node 20/22 Lambdas use `"module": "NodeNext"` / `"moduleResolution": "NodeNext"` and include `"types": ["node"]`. Do not default to `"module": "commonjs"` on new work.

`noUncheckedIndexedAccess` is the flag that most often breaks builds — index access needs a guard or non-null narrowing, not `!`.

## ESLint

Use **flat config** (`eslint.config.js` with `tseslint.config(...)`) — ESLint 9 no longer reads `.eslintrc`. Presets: `eslint.configs.recommended`, typescript-eslint **`recommended-type-checked`** (the old `recommended-requiring-type-checking` name was removed in v6), plus `plugin:security/recommended` and `plugin:sonarjs/recommended`.

Rules we set beyond the presets:
- `@typescript-eslint`: `explicit-function-return-type`, `no-explicit-any`, `no-non-null-assertion`, `strict-boolean-expressions`, `no-floating-promises`, `no-misused-promises`, `await-thenable`, `no-unnecessary-type-assertion`, `prefer-nullish-coalescing`, `prefer-optional-chain`, `prefer-readonly`, and all four `no-unsafe-{assignment,member-access,call,return}` — all `"error"`
- `@typescript-eslint/no-unused-vars: ["error", { "argsIgnorePattern": "^_" }]`
- `import/no-cycle: "error"`; `import/order` with `groups: [builtin, external, internal, parent, sibling, index]`, `newlines-between: "always"`, `alphabetize: { order: "asc" }`
- `no-console: ["error", { "allow": ["warn", "error"] }]`

## Dependencies

- **Exact versions in `package.json`** — no `^` or `~`.
- Every new Node/TS Lambda repo needs an `.npmrc` pointed at the @fullbay AWS CodeArtifact registry before the first PR (see CLAUDE.md → New Lambda Repos). A 404 on `@fullbay/*` is almost always a stale CodeArtifact token, not a missing package.

## Tests

**Vitest** (not Jest) for new work, to match the React stack. Minimum 80% coverage; 100% for critical business logic. Type-safe mocks via `satisfies`:

```ts
const mockRepository = { findById: vi.fn(), save: vi.fn() } satisfies UserRepository;
```

Test doubles must be deterministic: no `Math.random`, `Date.now()`, argless `new Date()`, or real timers in stubs/fixtures — CI runs under coverage instrumentation and flakes on them. Use `vi.useFakeTimers()`, fixed seed values, or injected clocks instead.

## Organization

- Keep files under ~300 lines; barrel exports (`index.ts`) for module boundaries.
- Prefix an interface with `I` **only** to resolve a genuine naming conflict.
- Use discriminated unions / `Result<T,E>` for expected failures; reserve exceptions for unrecoverable ones.

`tsc --noEmit` must pass before committing — it is enforced by the pre-commit hook.
