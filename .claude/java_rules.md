# Java Rules

Only non-obvious, shop-specific decisions. Standard Java naming/exception/logging practice is assumed.

- **Build: Gradle exclusively**, always via the Gradle Wrapper (`./gradlew`). Manage dependencies with a **version catalog** (`libs.versions.toml`), not inline coordinates.
- **Framework: default to Quarkus.** Use native compilation for production where feasible. Quarkus 3 uses `jakarta.*` (not `javax.*`), and the REST extension is `quarkus-rest` (renamed from `quarkus-resteasy-reactive` in 3.9+).
- **Format: Spotless** (current 7.x) with `googleJavaFormat()`, `removeUnusedImports()`, `trimTrailingWhitespace()`, `endWithNewline()`. Do **not** add a custom `importOrder` — `googleJavaFormat()` owns import ordering and a custom order fights it. Run `./gradlew spotlessApply` before committing.
- **Tests**: JUnit 5 + **AssertJ** (fluent assertions) + **Mockito**; `@QuarkusTest` / `@InjectMock` for Quarkus; **Testcontainers** for database and external-service integration tests. Minimum 80% coverage.
- **Test naming — use `@DisplayName` in the three-part format** `methodUnderTest - scenario - expectedBehavior`. The `@DisplayName` is the primary documentation of test intent; the Java method name should be descriptive but need not follow the three-part convention.
  - `@DisplayName("getAll - service throws exception - should catch and return 500")`
  - `@DisplayName("tierPayloadToDao() - valid payload - returns mapped PricingTier")`
- **Logging: SLF4J** facade with parameterized messages (`logger.info("... order={}", id)`). Never log secrets or PII.
- **Organization**: package **by feature, not by layer**. Class ≤ 500 lines; method ≤ 50 lines.
