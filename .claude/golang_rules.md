# Go Rules

Only non-obvious, shop-specific decisions. Effective Go / standard error-wrapping / naming conventions are assumed.

- **Layout**: standard Go project layout — `cmd/` (entry points), `internal/` (private), `pkg/` (importable by other projects).
- **Lint: `golangci-lint`** configured in `.golangci.yml`. Enable: `gofmt, govet, errcheck, staticcheck, gosec, revive, gocyclo, misspell, unused, gosimple, bodyclose, goconst, unparam`.
  - `gocyclo: min-complexity: 15`
  - `errcheck: check-type-assertions: true`
  - Shadow checking is `govet: enable: [shadow]` — the old `govet: check-shadowing: true` key was removed and will fail to load.
- **Tests**: `testify/assert` or `testify/require` for assertions; `gomock` or `testify/mock` for mocks; `httptest` for handlers. Table-driven tests with subtests. Minimum 80% coverage.
- **Errors**: wrap with `fmt.Errorf("...: %w", err)`; compare with `errors.Is` / `errors.As` — never `==` (including `sql.ErrNoRows`). Do not use `github.com/pkg/errors`; it is archived and superseded by `%w`.
- **Formatting**: line length 100–120; `gofumpt` for stricter formatting (optional).
