# Python Development Rules for AI Agents

## 1. Introduction

This document outlines the development rules and guidelines for AI agents developed in Python. The purpose is to ensure code quality, maintainability, consistency, and reproducibility across projects. These rules cover general development practices, linting, formatting, type checking, build processes, and considerations specific to AI/ML applications. Adherence to these rules will help the AI agent generate robust and reliable Python code.

## 2. General Python Development Guidelines

### 2.1. Python Version
* **Rule:** Projects should use a clearly defined Python version. It is recommended to use one of the actively supported Python versions (e.g., Python 3.9+ as of May 2025).
* **Rationale:** Ensures compatibility and access to the latest language features and security updates.
* **Action:** Specify the Python version in `pyproject.toml` or `runtime.txt` (for some PaaS).

### 2.2. Project Structure
* **Rule:** Follow a standardized project structure. For AI/ML projects, this typically includes:
    ```
    my_ai_project/
    ├── .git/
    ├── .venv/ or venv/
    ├── data/
    │   ├── raw/          # Immutable original data
    │   ├── processed/    # Cleaned and transformed data
    │   └── interim/      # Intermediate data files
    ├── notebooks/        # Jupyter notebooks for exploration and experimentation
    ├── src/
    │   ├── my_ai_project/ # Main application/library code
    │   │   ├── __init__.py
    │   │   ├── data_processing.py
    │   │   ├── modeling.py
    │   │   ├── evaluation.py
    │   │   └── utils.py
    │   └── scripts/        # Helper scripts (e.g., data ingestion, training triggers)
    ├── tests/            # Unit, integration, and other tests
    │   ├── __init__.py
    │   └── test_*.py
    ├── models/           # Serialized trained models and model artifacts
    ├── reports/          # Generated reports, figures, and logs
    ├── .gitignore
    ├── pyproject.toml    # Project metadata, dependencies, and tool configurations
    ├── README.md
    ├── LICENSE
    └── Dockerfile        # Optional, for containerization
    ```
* **Rationale:** Improves organization, makes it easier for new contributors to understand the codebase, and facilitates standardized build and deployment processes.

### 2.3. Dependency Management
* **Rule:** Use `pyproject.toml` for specifying project dependencies and metadata, as per PEP 518, PEP 621. Employ tools like Poetry, PDM, or Hatch for managing dependencies and virtual environments. For simpler projects or when these tools aren't used, a `requirements.txt` file (generated from a `requirements.in` using `pip-tools`) is acceptable.
* **Rationale:** Ensures reproducible environments and simplifies dependency resolution. `pyproject.toml` is the modern standard.
* **Action:** Define all dependencies in `pyproject.toml` (preferred) or `requirements.txt`. Include versions, and use a lock file (`poetry.lock`, `pdm.lock`, or `requirements.txt` generated with pinned versions).

### 2.4. Virtual Environments
* **Rule:** Always use virtual environments for Python projects.
* **Rationale:** Isolates project dependencies, preventing conflicts between projects and with system-wide packages.
* **Action:** Create and activate a virtual environment before installing dependencies (e.g., `python -m venv .venv`, `poetry shell`, `pdm venv create`). The AI agent should ensure its operations are within an active virtual environment context if possible.

### 2.5. Naming Conventions
* **Rule:** Adhere to PEP 8 naming conventions:
    * `lowercase` for modules and packages.
    * `lowercase_with_underscores` for functions, methods, and variables.
    * `UPPERCASE_WITH_UNDERSCORES` for constants.
    * `CapWords` (PascalCase) for classes.
    * Protected members prefixed with a single underscore (`_protected_member`).
    * Private members (name-mangled) prefixed with double underscores (`__private_member`).
* **Rationale:** Improves code readability and consistency.

### 2.6. Commenting and Docstrings
* **Rule:** Write clear and concise comments where necessary to explain complex logic.
* **Rule:** All public modules, functions, classes, and methods must have docstrings.
* **Rule:** For AI/ML projects, use a consistent docstring format that supports type hinting and parameter descriptions, such as Google style or NumPy style.
    * **Example (Google Style):**
        ```python
        def my_function(param1: int, param2: str) -> bool:
            """Does something interesting.

            Args:
                param1: The first parameter, an integer.
                param2: The second parameter, a string.

            Returns:
                True if successful, False otherwise.

            Raises:
                ValueError: If param1 is negative.
            """
            if param1 < 0:
                raise ValueError("param1 cannot be negative")
            # ... function logic ...
            return True
        ```
* **Rationale:** Essential for code understanding, maintainability, and auto-documentation generation.

### 2.7. Testing
* **Rule:** Write unit tests for all critical components of the codebase. Aim for high test coverage.
* **Rule:** Use Pytest as the primary testing framework.
* **Rule:** Tests should be placed in the `tests/` directory and follow the `test_*.py` naming convention.
* **Rule:** For AI/ML projects, include tests for:
    * Data validation and preprocessing steps.
    * Model input/output compatibility.
    * Edge cases and known failure modes of algorithms.
    * Consistency of predictions (for non-stochastic models).
* **Rationale:** Ensures code correctness, prevents regressions, and facilitates refactoring.

### 2.8. Version Control
* **Rule:** All code must be managed using Git.
* **Rule:** Use a `.gitignore` file to exclude virtual environments, cache files, sensitive data, large data files (use Git LFS for these if necessary), and compiled artifacts.
* **Rule:** Follow a consistent branching strategy (e.g., GitFlow, GitHub Flow).
* **Rule:** Write clear, concise, and informative commit messages.
* **Rationale:** Tracks changes, facilitates collaboration, and allows for rollbacks.

## 3. Linting Rules

Linters analyze code for programmatic and stylistic errors. This helps maintain code quality and consistency.

### 3.1. Recommended Linters
* **Primary Linter & Formatter: Ruff**
    * **Rule:** Use Ruff as the primary linter and formatter. It's extremely fast and can replace Flake8, isort, pydocstyle, and even parts of Pylint and Black.
    * **Rationale:** Speed, comprehensiveness, and ease of configuration.
* **Type Checker: MyPy**
    * **Rule:** Use MyPy for static type checking. (See Section 5)
    * **Rationale:** Catches type errors before runtime, improving code reliability.
* **Security Linter: Bandit**
    * **Rule:** Use Bandit for identifying common security issues in Python code.
    * **Rationale:** Helps prevent security vulnerabilities.
* **(Optional) Deeper Analysis: Pylint**
    * **Rule:** Pylint can be used for more in-depth analysis, including code smells and convention checking, if Ruff's capabilities are deemed insufficient for a specific need.
    * **Rationale:** Provides very detailed feedback but can be slower and more verbose.

### 3.2. Configuration File
* **Rule:** Configure all linters (Ruff, MyPy, Bandit, Pylint) within the `pyproject.toml` file. Fall back to dedicated configuration files (e.g., `.pylintrc`, `mypy.ini`) only if necessary.
* **Rationale:** Centralizes project configuration.

### 3.3. Key Linting Checks to Enforce (primarily via Ruff)
* **Code Style (PEP 8):**
    * Indentation (4 spaces).
    * Maximum line length (e.g., 88 or 100 characters, configurable in Ruff).
    * Whitespace (around operators, after commas, etc.).
    * Blank lines (to separate logical sections).
    * Import formatting (see Formatting Rules).
* **Error Detection:**
    * Undefined variables.
    * Unused imports, variables, and arguments (except where explicitly allowed).
    * Duplicate keys in dictionaries.
    * Unreachable code.
    * Syntax errors.
* **Code Complexity:**
    * McCabe complexity checks (configure a reasonable threshold, e.g., 10-15).
* **Naming Conventions:**
    * Enforce PEP 8 naming conventions.
* **Docstring and Commenting Standards:**
    * Presence of docstrings for public elements (Ruff's `pydocstyle` integration).
    * Correct docstring formatting.
* **Type Hinting (enforced by MyPy, some checks by Ruff):**
    * Presence of type hints for function arguments and return values.
* **Security (enforced by Bandit):**
    * Checks for known security vulnerabilities (e.g., hardcoded passwords, SQL injection risks, unsafe deserialization).
* **AI/ML Specific (Conceptual checks, may require custom rules or manual review):**
    * Avoid hardcoded file paths for datasets or models; use relative paths or configuration variables.
    * Discourage use of `pickle` with untrusted data (Bandit can help here).
    * Ensure that random seeds are managed for reproducibility where appropriate.

### 3.4. Ignoring Rules
* **Rule:** Only ignore a linting rule on a specific line using an inline comment (e.g., `# noqa: E501` for Flake8/Ruff, `# pylint: disable=some-message` for Pylint) when there's a justifiable reason.
* **Rule:** Document the reason for ignoring the rule if it's not immediately obvious.
* **Rule:** Avoid globally disabling important rules. Prefer per-file or per-line ignores.
* **Rationale:** Maintains code quality while allowing flexibility for legitimate exceptions.

## 4. Formatting Rules

Code formatters automatically reformat code to comply with a consistent style.

### 4.1. Recommended Formatter
* **Rule:** Use **Ruff Formatter** or **Black** as the auto-formatter.
* **Rationale:** Both enforce a strict, opinionated style, minimizing debates about formatting and ensuring consistency. Ruff's formatter is integrated and very fast.

### 4.2. Integration with Linters
* **Rule:** Ensure the formatter's style is compatible with the linter's style rules (Ruff handles this well internally).
* **Rationale:** Prevents conflicts where the formatter changes code in a way the linter dislikes.

### 4.3. Line Length
* **Rule:** Set a consistent line length (e.g., 88 characters for Black compatibility, or 100 characters). This should be configured in both the formatter and linter.
* **Rationale:** Improves readability, especially on smaller screens or when viewing code side-by-side.

### 4.4. Import Sorting
* **Rule:** Use **Ruff's import sorter** (replaces `isort`) to automatically sort and group imports.
* **Rule:** Configure imports to be grouped as:
    1.  Standard library imports.
    2.  Third-party library imports.
    3.  First-party/local application imports.
    Separated by a blank line.
* **Rationale:** Improves readability and makes it easier to identify project dependencies.

## 5. Type Checking Rules

Static type checking helps detect type errors before runtime.

### 5.1. Tool
* **Rule:** Use **MyPy** for static type checking.
* **Rationale:** The de-facto standard for type checking in Python.

### 5.2. Configuration
* **Rule:** Configure MyPy in `pyproject.toml` or a `mypy.ini` file.
    ```toml
    # pyproject.toml example for MyPy
    [tool.mypy]
    python_version = "3.10"
    warn_return_any = true
    warn_unused_configs = true
    ignore_missing_imports = true # Start with this and gradually reduce
    disallow_untyped_defs = false # Start with false, move to true for new code
    # Add paths to check
    # files = ["src/"]
    ```
* **Rationale:** Centralized and version-controlled configuration.

### 5.3. Strictness Levels
* **Rule:** Gradually increase MyPy's strictness.
    * Start by ensuring MyPy runs without errors on the existing codebase, possibly with `ignore_missing_imports = true` and `disallow_untyped_defs = false`.
    * For new code, aim for stricter settings like `disallow_untyped_defs = true`.
    * Gradually add type hints to existing code and enable stricter checks (`warn_incomplete_stub`, `disallow_any_generics`, etc.).
* **Rationale:** Allows for incremental adoption of type checking without overwhelming developers.

### 5.4. Importance in AI/ML
* **Rule:** Prioritize adding type hints for data structures (e.g., NumPy arrays, Pandas DataFrames with `pandas-stubs`), function signatures involving data transformations, and model inputs/outputs.
* **Rationale:** Critical for data integrity, catching integration errors early, and making complex data pipelines more understandable and maintainable. Libraries like `beartype` can also be used for runtime type checking if static analysis is insufficient.

## 6. Build Rules

These rules govern how the Python application or library is packaged and prepared for distribution or deployment.

### 6.1. Build System
* **Rule:** Use `pyproject.toml` with a PEP 517 compliant build backend (e.g., `hatchling`, `setuptools`, `flit_core`, `poetry-core`). Tools like Hatch, Poetry, or PDM manage this automatically.
* **Rule:** For complex task automation (beyond just packaging), use tools like `Makefile`, `nox`, or `tox`.
* **Rationale:** Standardized and modern approach to Python packaging.

### 6.2. Packaging
* **Rule:** Build projects into **wheels** (`.whl`) as the primary distribution format. Source distributions (`sdist`) can also be provided.
* **Rule:** Ensure `MANIFEST.in` (if using Setuptools without full `pyproject.toml` adoption) or equivalent in `pyproject.toml` correctly includes all necessary non-code files (e.g., data files, templates).
* **Rationale:** Wheels are a pre-compiled format that installs faster and more reliably.

### 6.3. Dependency Pinning for Reproducibility
* **Rule:** Always use a lock file (`poetry.lock`, `pdm.lock`, or `requirements.txt` generated with pinned versions, e.g., by `pip-compile`) to ensure reproducible builds.
* **Rationale:** Guarantees that the same versions of dependencies are used across all environments and builds.

### 6.4. Build Environment
* **Rule:** Builds should be performed in isolated, clean environments (e.g., using `tox`, Docker, or CI runners).
* **Rationale:** Prevents contamination from the local development environment and ensures build consistency.

### 6.5. AI/ML Model Serialization/Packaging
* **Rule:** For AI models, establish a clear process for model serialization (e.g., `joblib`, `pickle` (with caution), ONNX, native framework saving like TensorFlow SavedModel or PyTorch `torch.save`).
* **Rule:** Version control model artifacts (or their URIs if stored externally) alongside the code that produced them. Tools like DVC or MLflow can assist with this.
* **Rule:** Package models with necessary metadata: training parameters, dataset versions, performance metrics.
* **Rationale:** Ensures models are reproducible, deployable, and their lineage can be tracked.

### 6.6. Docker for Reproducible Environments
* **Rule:** If containerization is used, create a `Dockerfile` to define the application environment.
* **Rule:** Follow Dockerfile best practices:
    * Use official Python base images.
    * Use multi-stage builds to keep final images small.
    * Copy only necessary files into the image.
    * Minimize the number of layers.
    * Run containers as non-root users.
    * Ensure the Python environment within the Docker image uses pinned dependencies.
* **Rationale:** Provides highly reproducible and portable environments for development, testing, and deployment.

## 7. Continuous Integration (CI) / Continuous Deployment (CD) Guidelines

### 7.1. Automated Linting, Formatting, and Testing
* **Rule:** Integrate linting, formatting checks, type checking, and automated tests into a CI pipeline (e.g., GitHub Actions, GitLab CI, Jenkins).
* **Rule:** Fail the CI build if any linting, formatting, type, or test checks fail.
* **Rationale:** Enforces quality standards automatically and catches issues early.

### 7.2. Automated Builds and Packaging
* **Rule:** Automate the build and packaging process in the CI pipeline upon successful checks on main branches or tags.
* **Rationale:** Ensures consistent and reliable creation of distributable artifacts.

### 7.3. Environment Consistency
* **Rule:** Strive for consistency between CI, development, and production environments. Use pinned dependencies and containerization (Docker) to achieve this.
* **Rationale:** Reduces "works on my machine" issues.

### 7.4. Secrets Management
* **Rule:** Never hardcode secrets (API keys, passwords, etc.) in the codebase.
* **Rule:** Use environment variables or dedicated secrets management tools (e.g., HashiCorp Vault, AWS Secrets Manager, GitHub Actions secrets) to manage sensitive information.
* **Rationale:** Critical for security.

## 8. AI Agent Specific Considerations

These guidelines are tailored for an AI agent generating Python code, particularly for AI/ML tasks.

### 8.1. Reproducibility
* **Rule:** The agent should generate code that emphasizes reproducibility:
    * Explicitly set random seeds (NumPy, Python's `random`, ML frameworks) at the beginning of scripts or notebooks intended for reproducible experiments.
    * Log versions of key libraries, especially those involved in data processing and modeling.
    * Encourage or facilitate the versioning of data (e.g., through naming conventions, or integration with tools like DVC) and model artifacts.
* **Rationale:** Crucial for debugging, validating results, and building upon previous work in AI/ML.

### 8.2. Modularity
* **Rule:** The agent should promote modular code design:
    * Break down complex AI pipelines (data ingestion, preprocessing, feature engineering, training, evaluation, deployment) into distinct functions or classes.
    * Place these modules in appropriate files within the `src/` directory.
* **Rationale:** Improves code organization, testability, reusability, and maintainability.

### 8.3. Configuration Management
* **Rule:** For AI/ML projects, manage configurations (e.g., hyperparameters, file paths, model settings) externally from the code:
    * Use configuration files (YAML, TOML, JSON) or environment variables.
    * Libraries like Hydra or Pydantic can be used for robust configuration management.
    * The agent should generate code that loads configurations rather than hardcoding them.
* **Rationale:** Facilitates easy modification of parameters without code changes, and supports systematic experimentation.

### 8.4. Experiment Tracking
* **Rule:** While the agent itself might not *implement* tracking, it should generate code that is amenable to experiment tracking.
    * Log key metrics, parameters, and artifacts in a structured way.
    * This can be simple print statements, CSV logging, or ideally, integration with tools like MLflow or Weights & Biases.
* **Rationale:** Essential for comparing experiments, understanding model performance, and debugging.

### 8.5. Resource Management
* **Rule:** When generating code that involves significant computation or memory (e.g., training deep learning models, processing large datasets):
    * Encourage the use of context managers (`with` statement) for resources that need explicit cleanup.
    * Consider efficient data loading and batching.
    * Be mindful of potential memory leaks if generating complex object-oriented code.
* **Rationale:** Ensures efficient use of resources and prevents crashes.

### 8.6. Ethical Considerations & Bias
* **Rule:** Although difficult for an AI agent to enforce directly, the generated code and accompanying documentation should not promote or ignore ethical concerns.
    * If the task involves sensitive data or has potential societal impact, the agent could suggest adding comments or placeholders for ethical reviews or bias checks.
* **Rationale:** Promotes responsible AI development.

## 9. Tools and Configuration Examples

### 9.1. `pyproject.toml` Example (Ruff, Black, MyPy, Build)

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "my_ai_project"
version = "0.1.0"
description = "An amazing AI project."
readme = "README.md"
requires-python = ">=3.9"
license = { file = "LICENSE" }
authors = [
    { name = "AI Agent", email = "agent@example.com" },
]
dependencies = [
    "numpy>=1.23.0",
    "pandas>=1.5.0",
    "scikit-learn>=1.2.0",
    "torch", # Example, if using PyTorch
    "tensorflow", # Example, if using TensorFlow
    "mlflow", # Example, for experiment tracking
    "python-dotenv", # For managing environment variables
    "pyyaml", # For YAML config files
]

[project.optional-dependencies]
dev = [
    "ruff",
    "mypy",
    "pytest",
    "pytest-cov",
    "bandit",
    "pre-commit", # For git hooks
    "jupyterlab",
    "pandas-stubs", # For better pandas type checking
]

[tool.hatch.version]
path = "src/my_ai_project/__init__.py"

[tool.ruff]
#line-length = 88 # Or 100, etc.
target-version = "py39" # Set to your minimum Python version

[tool.ruff.lint]
select = [
    "E",  # pycodestyle errors
    "W",  # pycodestyle warnings
    "F",  # Pyflakes
    "I",  # isort
    "N",  # pep8-naming
    "D",  # pydocstyle
    "ANN",# flake8-annotations (use sparingly, can be noisy)
    "S",  # flake8-bandit
    "C4", # flake8-comprehensions
    "B",  # flake8-bugbear
    "A",  # flake8-builtins
    "RUF",# Ruff-specific rules
]
ignore = ["ANN101", "ANN102"] # Example: ignore missing type hints for self/cls
# Allow unused arguments in specific cases if needed, e.g. for interface compatibility
# per-file-ignores = { "src/my_ai_project/interface_stubs.py" = ["ARG001"] }

[tool.ruff.lint.pydocstyle]
convention = "google" # or "numpy", "pep257"

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
# line-ending = "auto" # if not using .editorconfig

# For Black, if used separately from Ruff's formatter
# [tool.black]
# line-length = 88
# target-version = ['py39']

[tool.mypy]
python_version = "3.9"
warn_return_any = true
warn_unused_configs = true
ignore_missing_imports = true # Be cautious with this; aim to reduce its necessity
# For stricter checking, uncomment these gradually:
# disallow_untyped_defs = true
# disallow_incomplete_defs = true
# disallow_untyped_decorators = true
# check_untyped_defs = true
# strict_optional = true
# no_implicit_optional = true
plugins = [
  "numpy.typing.mypy_plugin" # If using NumPy extensively
]
# Add paths to be checked by MyPy if not specifying on command line
# files = ["src/", "tests/"]

[tool.pytest.ini_options]
minversion = "6.0"
addopts = "-ra -q --cov=src/my_ai_project --cov-report=term-missing --cov-report=xml"
testpaths = [
    "tests",
]

[tool.bandit]
# Example: exclude tests from bandit scans if they contain intentional "bad" patterns for testing
# skips = ["B101"] # Skip assert_used check
# exclude_dirs = ["tests"]
