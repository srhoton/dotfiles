# Java Development Best Practices Guide for AI Agents

## Build System

- **Use Gradle exclusively** as the build system
- Implement the Gradle Wrapper for consistent build environment
- Use version catalogs for dependency management
- Keep Gradle version updated to latest stable release

```gradle
// Example build.gradle
plugins {
    id 'java'
    id 'io.quarkus'
    id 'com.diffplug.spotless' version '6.22.0'
}
```

## Framework

- **Default to Quarkus** as the primary framework
- Leverage Quarkus extensions ecosystem for additional functionality
- Use Quarkus native compilation for production deployments when possible
- Follow Quarkus best practices for configuration and dependency injection

```java
@Path("/items")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class ItemResource {

    @Inject
    ItemService service;
    
    @GET
    public List<Item> getAll() {
        return service.findAll();
    }
}
```

## Code Style & Linting

- **Use Spotless for linting and formatting**
- Configure with Google Java Style Guide rules
- Enforce consistent code formatting across the project
- Run Spotless checks as part of CI/CD pipeline

```gradle
spotless {
    java {
        googleJavaFormat()
        importOrder 'java', 'javax', 'org', 'com', ''
        removeUnusedImports()
        trimTrailingWhitespace()
        endWithNewline()
    }
}
```

## Naming Conventions

- Follow standard Java naming conventions:
  - `CamelCase` for class names
  - `camelCase` for method and variable names
  - `UPPER_SNAKE_CASE` for constants
  - `lowerCamelCase` for package names
- Use descriptive and meaningful names
- Avoid abbreviations except for standard ones (e.g., HTTP, URL)

## Code Organization

- Organize packages by feature, not by layer
- Keep classes focused on single responsibility (SRP)
- Limit class size to maximum 500 lines
- Limit method size to maximum 50 lines
- Use interfaces for defining contracts

## Documentation

- Add Javadoc for all public classes and methods
- Document non-obvious behavior and edge cases
- Include meaningful examples in documentation when appropriate
- Keep documentation updated when code changes

```java
/**
 * Processes a payment transaction.
 * 
 * @param paymentRequest The payment details
 * @return A transaction receipt with status information
 * @throws PaymentException If the payment processing fails
 */
public TransactionReceipt processPayment(PaymentRequest paymentRequest) throws PaymentException {
    // Implementation
}
```

## Logging

- Use SLF4J as logging facade
- Configure appropriate log levels (ERROR, WARN, INFO, DEBUG, TRACE)
- Include contextual information in log messages
- Use structured logging for machine-parseable logs
- Don't log sensitive information

```java
private static final Logger logger = LoggerFactory.getLogger(PaymentService.class);

public void processPayment(PaymentRequest request) {
    logger.info("Processing payment for order={} with amount={}", 
                request.getOrderId(), 
                request.getAmount());
    
    try {
        // Process payment
        logger.debug("Payment processed successfully");
    } catch (Exception e) {
        logger.error("Payment processing failed for order={}", request.getOrderId(), e);
        throw e;
    }
}
```

## Testing

- Write unit tests for all business logic
- Use JUnit 5 for testing framework
- Employ AssertJ for fluent assertions
- Use Mockito for mocking dependencies
- Aim for minimum 80% code coverage
- Implement integration tests for external dependencies
- Use test containers for database and service testing

```java
@QuarkusTest
public class ItemResourceTest {

    @InjectMock
    ItemService itemService;

    @Test
    public void testGetAllItems() {
        // Given
        List<Item> expectedItems = Arrays.asList(new Item(1L, "Test Item"));
        when(itemService.findAll()).thenReturn(expectedItems);
        
        // When/Then
        given()
          .when().get("/items")
          .then()
             .statusCode(200)
             .body("size()", is(1))
             .body("[0].name", is("Test Item"));
    }
}
```

## Exception Handling

- Create custom exceptions for domain-specific errors
- Use unchecked exceptions for unrecoverable errors
- Implement global exception handlers for REST APIs
- Avoid catching generic Exception class
- Don't swallow exceptions without proper handling

```java
@Provider
public class GlobalExceptionHandler implements ExceptionMapper<Exception> {

    private static final Logger logger = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @Override
    public Response toResponse(Exception exception) {
        if (exception instanceof EntityNotFoundException) {
            return Response.status(Response.Status.NOT_FOUND)
                    .entity(new ErrorResponse("Entity not found", exception.getMessage()))
                    .build();
        }
        
        logger.error("Unhandled exception", exception);
        return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                .entity(new ErrorResponse("Internal server error", "An unexpected error occurred"))
                .build();
    }
}
```

## Security

- Follow OWASP Top 10 guidelines
- Implement proper input validation
- Use parameterized queries for database access
- Never store sensitive data in plain text
- Use secure hashing for passwords (Argon2, bcrypt)
- Implement proper authentication and authorization
- Use HTTPS for all communications
- Implement request throttling and rate limiting
- Regularly scan dependencies for vulnerabilities

```java
// Input validation example
public void processUserInput(String userInput) {
    if (userInput == null || !userInput.matches("[a-zA-Z0-9_]+")) {
        throw new IllegalArgumentException("Invalid input format");
    }
    
    // Process validated input
}

// Password hashing example
@Inject
PasswordEncoder passwordEncoder;

public void registerUser(UserRegistration registration) {
    User user = new User();
    user.setUsername(registration.getUsername());
    user.setPasswordHash(passwordEncoder.encode(registration.getPassword()));
    userRepository.save(user);
}
```

## Performance

- Optimize database queries
- Use caching appropriately
- Implement pagination for large data sets
- Use asynchronous processing for long-running tasks
- Profile and optimize critical paths

```java
@Path("/items")
public class ItemResource {

    @Inject
    ItemService service;
    
    @GET
    public List<Item> getAll(@QueryParam("page") @DefaultValue("0") int page,
                             @QueryParam("size") @DefaultValue("20") int size) {
        return service.findAllPaginated(page, size);
    }
}
```

## Concurrency

- Use Java concurrency utilities instead of low-level threading
- Leverage CompletableFuture for asynchronous operations
- Be careful with shared mutable state
- Use thread-safe collections when needed
- Consider using reactive programming for high-concurrency scenarios

## Dependency Management

- Keep dependencies updated
- Use version catalogs in Gradle
- Explicitly specify versions for better control
- Regularly check for security vulnerabilities
- Limit transitive dependencies

```gradle
dependencies {
    // Use version catalog
    implementation(libs.quarkus.core)
    implementation(libs.quarkus.resteasy.reactive)
    
    // Testing
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.assertj.core)
    testImplementation(libs.quarkus.test)
}
```

## Recommended Tools

| Tool | Purpose |
|------|--------|
| Gradle | Build automation |
| Spotless | Code formatting and linting |
| SonarQube | Code quality and security analysis |
| JaCoCo | Code coverage |
| Quarkus Dev Mode | Live code reloading |
| OWASP Dependency Check | Security vulnerability scanning |
| JUnit 5 | Testing framework |
| AssertJ | Fluent assertions |
| Mockito | Mocking framework |
| Testcontainers | Integration testing with containers |