# React Rules

Only non-obvious, shop-specific decisions. See @~/.claude/typescript_rules.md for TS/ESLint/tsconfig.

## Hard requirement

**All components are functional components — no class components, ever.** Hooks for all state and side effects.

## Stack (these are the picks; don't substitute)

| Concern | Tool |
|---|---|
| Build | Vite |
| Global state | **Zustand** |
| Server state | **TanStack Query** |
| Styling | **Tailwind CSS** |
| Forms | **React Hook Form** |
| Routing | **React Router v6** (`createBrowserRouter`) |
| Component primitives | Headless UI / Radix UI |
| Animation | Framer Motion |
| Tests | **Vitest** + React Testing Library + **MSW** |
| Error boundaries | **react-error-boundary** (functional) |
| Long lists | **react-window** (virtual scrolling) |
| HTML sanitizing | **DOMPurify** |

## Module federation (`@originjs/vite-plugin-federation`)

The non-obvious parts — a wrong config here fails at runtime, not build time:

```ts
federation({
  name: 'host-app',
  remotes: { 'remote-app': 'http://localhost:3001/assets/remoteEntry.js' },
  exposes: { './Button': './src/components/ui/Button' },
  shared: {
    react:       { singleton: true, requiredVersion: '^19.0.0' },
    'react-dom': { singleton: true, requiredVersion: '^19.0.0' },
  },
}),
build: { target: 'esnext', minify: false, cssCodeSplit: false }
```

- `singleton: true` on `react`/`react-dom` is mandatory — two React copies break hooks.
- **`build.minify: false` is a plugin requirement**, not a preference.
- Expose/consume through `src/federation/exposes/` and `src/federation/remotes/`.
- Version exposed components semantically; wrap every remote component in an error boundary + `Suspense`.
- Cross-app communication: typed event bus for decoupled events, shared Zustand store for global state; keep the two in sync.

## Zustand conventions

Middleware: `immer` (immutability), `persist` (storage), `subscribeWithSelector` (granular subscriptions). Use the **slice pattern** for large stores and custom selectors to avoid over-rendering.

## Styling conventions

- `cn()` helper (**clsx + tailwind-merge**) for conditional classes — not string concatenation.
- Dark mode via Tailwind's `'class'` strategy; CSS variables for theming.
- Official plugins: forms, typography, aspect-ratio. Mobile-first responsive.

## Layout

`src/components/{ui,forms,layout}/`, `hooks/`, `contexts/`, `pages/`, `services/`, `stores/`, `types/`, `federation/`.

## Notes

Targeting React 19: no `prop-types` (removed), avoid annotating with `React.FC`, and don't reach for `memo`/`useMemo`/`useCallback` reflexively — profile first, since the React Compiler handles most of it.
