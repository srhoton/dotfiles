# Python Rules

Only non-obvious, shop-specific decisions. Standard PEP 8 / typing / testing practice is assumed.

- **Dependencies & venv: use `uv`** (`uv sync`, `uv add`, `uv run`). Commit the lockfile. Do not introduce Poetry/PDM/pip-tools into a project that doesn't already use them.
- **Lint + format: Ruff** — it replaces Flake8, isort, and pydocstyle. Configure everything in `pyproject.toml`, never in per-tool dotfiles.
  - `[tool.ruff.lint] select = ["E","W","F","I","N","D","ANN","S","C4","B","A","RUF"]`, `ignore = ["ANN101","ANN102"]`
  - `[tool.ruff.lint.pydocstyle] convention = "google"` — Google-style docstrings
  - `[tool.ruff.format] quote-style = "double"`; line length 88
- **Type checking: MyPy**, also configured in `pyproject.toml`. Add type hints to data-shape boundaries (function signatures, transforms, model/API I/O) first.
- **Security: Bandit** for static security scanning.
- **Tests: pytest**, in `tests/`, named `test_*.py`. Minimum 80% coverage.
