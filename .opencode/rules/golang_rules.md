# Golang Development Best Practices Guide for AI Agents

## Package Organization

- **Organize packages according to Go best practices**
- Package names should be short, concise, and lowercase (e.g., 'http', 'io')
- Use singular form for package names (e.g., 'time', not 'times')
- Avoid underscores in package names
- Package names should match their directory names
- Group related functionality in the same package
- Organize code by domain functionality, not by layer
- Follow the standard Go project layout (cmd/, pkg/, internal/)
- Use internal/ for private packages that shouldn't be imported by other projects
- Use cmd/ for main applications entry points
- Use pkg/ for code meant to be used by external applications
- Keep main packages as small as possible, with logic in importable packages

```go
project/
├── cmd/         # Command-line applications
│   ├── api/     # The API server
│   │   └── main.go
│   └── worker/  # The background worker
│       └── main.go
├── internal/    # Private libraries
│   ├── auth/    # Authentication package
│   └── db/      # Database interactions
└── pkg/         # Public libraries
    └── models/   # Data models
```

## Naming Conventions

- **Follow Go's established naming conventions**
- Use camelCase for internal or unexported names
- Use PascalCase for exported names (visible outside the package)
- Use all UPPERCASE for constants only when they're truly constant
- Acronyms should be all uppercase (e.g., 'HTTP', 'URL', 'ID')
- Getter methods should not use 'Get' prefix (e.g., 'user.Name()', not 'user.GetName()')
- Interface names should use '-er' suffix when representing a single action (e.g., 'Reader', 'Writer')
- Variable names should be short in small scopes, more descriptive in larger scopes
- Be consistent with naming patterns for similar concepts
- Test functions should be named 'Test' + function name (e.g., 'TestConnect')
- Benchmark functions should be named 'Benchmark' + function name

```go
// Good naming examples
const (
    MaxConnections = 100
    DefaultTimeout = 30 * time.Second
)

type UserService interface {
    Create(user *User) error
    FindByID(id string) (*User, error)
    Update(user *User) error
}

func (u *User) Name() string {
    return u.name
}

func TestConnect(t *testing.T) {
    // Test code
}
```

## Code Organization

- **Structure code for readability and maintainability**
- Organize functions in a file from high-level to low-level
- Group related functions together
- Keep functions focused on a single responsibility
- Limit function length (aim for < 50 lines)
- Limit parameter count (aim for ≤ 3 parameters)
- Use meaningful parameter and return value names in function declarations
- Prefer composition over inheritance
- Use structs to group related data
- Keep exported API surface minimal
- Don't export functions or types solely for testing
- Use function options pattern for functions with many optional parameters

```go
// Function options pattern example
type ServerOptions struct {
    Port int
    Host string
    ReadTimeout time.Duration
    WriteTimeout time.Duration
}

type ServerOption func(*ServerOptions)

func WithPort(port int) ServerOption {
    return func(o *ServerOptions) {
        o.Port = port
    }
}

func WithHost(host string) ServerOption {
    return func(o *ServerOptions) {
        o.Host = host
    }
}

func NewServer(options ...ServerOption) *Server {
    opts := ServerOptions{
        Port: 8080,
        Host: "localhost",
        ReadTimeout: 30 * time.Second,
        WriteTimeout: 30 * time.Second,
    }
    
    for _, option := range options {
        option(&opts)
    }
    
    return &Server{
        // Initialize server with options
    }
}
```

## Error Handling

- **Handle errors according to Go's idiomatic approach**
- Always check errors and handle them appropriately
- Return errors rather than using panic/recover for normal error flows
- Create custom error types for specific error cases
- Use errors.Is() and errors.As() for error comparison
- Wrap errors with context using fmt.Errorf with the %w verb
- Error strings should not be capitalized or end with punctuation
- Error messages should provide context but avoid redundant information
- Return early on errors to avoid deep nesting
- Use sentinel errors for expected error conditions
- In top-level APIs, consider converting errors to a common format

```go
// Custom error with wrapping
type NotFoundError struct {
    ID string
}

func (e *NotFoundError) Error() string {
    return fmt.Sprintf("resource with id %s not found", e.ID)
}

func GetUser(id string) (*User, error) {
    user, err := db.FindUser(id)
    if err != nil {
        // Wrap the error with context
        return nil, fmt.Errorf("getting user: %w", err)
    }
    if user == nil {
        return nil, &NotFoundError{ID: id}
    }
    return user, nil
}

// Error checking with early return
func ProcessUser(id string) error {
    user, err := GetUser(id)
    if err != nil {
        return err  // Return early
    }
    
    // Continue with processing
    // ...
    
    return nil
}
```

## Documentation

- **Document code thoroughly using Go's conventions**
- Every exported (public) function, type, constant, and variable must have a comment
- Comments for exported entities should start with the entity name
- Use full sentences with proper punctuation
- Include examples in documentation for complex functions
- Document package functionality in a package-level comment
- Use meaningful examples in documentation with proper output comments
- Document non-obvious behavior and edge cases
- For methods, only include the receiver name when necessary for clarification
- Keep comments up to date when code changes
- Use godoc format for documenting packages and functions

```go
// Package userservice provides functionality for managing users.
// It handles creation, retrieval, and authentication of user accounts.
package userservice

// User represents a registered user in the system.
type User struct {
    ID        string
    Email     string
    CreatedAt time.Time
}

// NewUser creates a new user with the provided email.
// It returns an error if the email is invalid or already exists.
func NewUser(email string) (*User, error) {
    // Implementation
}

// Authenticate verifies a user's credentials and returns
// a session token if successful. It returns an error if
// authentication fails.
func Authenticate(email, password string) (string, error) {
    // Implementation
}
```

## Testing

- **Follow Go's testing best practices**
- Write table-driven tests for testing multiple scenarios
- Use subtests for organizing related test cases
- Test both happy paths and error cases
- Use testify/assert or testify/require for more expressive assertions
- Keep test code clean and maintainable
- Use meaningful test names that describe the behavior being tested
- Create test helpers for common setup and teardown
- Use interfaces for mocking dependencies
- Aim for at least 80% test coverage
- Use gomock or testify/mock for generating mocks
- Use httptest for testing HTTP handlers
- Use benchmarks for performance-critical code
- Place tests in the same package as the code being tested with _test.go suffix

```go
func TestUserCreate(t *testing.T) {
    // Table-driven test
    tests := []struct {
        name     string
        email    string
        wantErr  bool
        errMsg   string
    }{
        {
            name:    "Valid email",
            email:   "test@example.com",
            wantErr: false,
        },
        {
            name:    "Invalid email",
            email:   "invalid-email",
            wantErr: true,
            errMsg:  "invalid email format",
        },
        {
            name:    "Empty email",
            email:   "",
            wantErr: true,
            errMsg:  "email cannot be empty",
        },
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            user, err := NewUser(tt.email)
            
            if tt.wantErr {
                assert.Error(t, err)
                assert.Contains(t, err.Error(), tt.errMsg)
                assert.Nil(t, user)
            } else {
                assert.NoError(t, err)
                assert.NotNil(t, user)
                assert.Equal(t, tt.email, user.Email)
            }
        })
    }
}
```

## Concurrency

- **Use Go's concurrency features safely and effectively**
- Prefer channels for communication between goroutines
- Use select for handling multiple channels
- Always use mutexes for shared memory access
- Consider sync.WaitGroup for waiting on multiple goroutines
- Use context for cancellation and timeouts
- Beware of goroutine leaks - ensure all goroutines can exit
- Consider using errgroup for handling errors from multiple goroutines
- Use buffered channels when appropriate to prevent blocking
- Prefer sync.Once for one-time initialization
- Use sync.Pool for frequently allocated and released items
- Consider worker pools for limiting concurrency
- Document concurrent access requirements for exported types

```go
// Worker pool pattern
func ProcessItems(items []Item) error {
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    
    const maxWorkers = 5
    itemsCh := make(chan Item, len(items))
    errCh := make(chan error, 1)
    
    // Start workers
    var wg sync.WaitGroup
    for i := 0; i < maxWorkers; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for item := range itemsCh {
                if err := processItem(ctx, item); err != nil {
                    select {
                    case errCh <- err:
                        // Error sent
                    default:
                        // Error channel already has an error
                    }
                    return
                }
            }
        }()
    }
    
    // Send items to workers
    for _, item := range items {
        select {
        case itemsCh <- item:
            // Item sent
        case <-ctx.Done():
            return ctx.Err()
        case err := <-errCh:
            return err
        }
    }
    
    close(itemsCh)
    
    // Wait for workers to finish
    doneCh := make(chan struct{})
    go func() {
        wg.Wait()
        close(doneCh)
    }()
    
    // Wait for completion or error
    select {
    case <-doneCh:
        return nil
    case <-ctx.Done():
        return ctx.Err()
    case err := <-errCh:
        return err
    }
}
```

## Performance

- **Optimize performance following Go idioms**
- Profile before optimizing
- Use strings.Builder for string concatenation
- Pre-allocate slices when capacity is known (make([]T, 0, capacity))
- Avoid unnecessary allocations
- Use pointers judiciously; prefer values for small structs
- Use sync.Pool for frequently allocated objects
- Minimize copying large objects
- Batch database operations
- Use efficient data structures (e.g., map for lookups)
- Use buffer pools for I/O operations
- Consider the sync/atomic package for simple shared state
- Use caching for expensive operations

```go
// Efficient string building
func BuildReport(items []Item) string {
    // Pre-allocate StringBuilder with estimated capacity
    var sb strings.Builder
    sb.Grow(len(items) * 20) // Estimate 20 bytes per item
    
    sb.WriteString("Report:\n")
    for _, item := range items {
        fmt.Fprintf(&sb, "- %s: $%.2f\n", item.Name, item.Price)
    }
    
    return sb.String()
}

// Pre-allocate slice
func FilterItems(items []Item, predicate func(Item) bool) []Item {
    // Pre-allocate result slice with same capacity
    result := make([]Item, 0, len(items))
    
    for _, item := range items {
        if predicate(item) {
            result = append(result, item)
        }
    }
    
    return result
}
```

## Dependency Management

- **Manage dependencies effectively**
- Use Go modules for dependency management
- Vendor dependencies for reproducible builds if needed
- Specify minimum version constraints in go.mod
- Regularly update dependencies for security fixes
- Avoid depending on forked versions of packages
- Keep dependencies minimal and focused
- Consider stability when choosing dependencies
- Use go.sum for dependency verification
- Run 'go mod tidy' to clean up unused dependencies
- Pin versions for stability in production code
- Document external dependencies in README

```go
// Example go.mod file
module github.com/example/myproject

go 1.19

require (
    github.com/gin-gonic/gin v1.8.1
    github.com/go-sql-driver/mysql v1.7.0
    github.com/golang-jwt/jwt/v4 v4.5.0
    github.com/stretchr/testify v1.8.2
    go.uber.org/zap v1.24.0
)

// Example command for updating dependencies
// $ go get -u ./...
// $ go mod tidy
```

## Linting

- **Use linters to enforce code quality**
- Use golangci-lint as a comprehensive linting tool
- Configure linting rules in .golangci.yml
- Enable gofmt for standard formatting
- Enable govet for detecting suspicious constructs
- Enable staticcheck for static analysis
- Enable errcheck to ensure errors are handled
- Enable gosec for security-related issues
- Enable golint or revive for style checks
- Enable gocyclo to detect complex functions
- Enable misspell to catch spelling errors
- Enable unused to detect unused code
- Run linters in CI/CD pipelines
- Use // nolint comments sparingly and with justification

```yaml
# .golangci.yml example
run:
  timeout: 5m

linters:
  enable:
    - gofmt
    - govet
    - errcheck
    - staticcheck
    - gosec
    - revive
    - gocyclo
    - misspell
    - unused
    - gosimple
    - bodyclose
    - goconst
    - unparam

output:
  format: colored-line-number

linters-settings:
  gocyclo:
    min-complexity: 15
  revive:
    rules:
      - name: exported
        disabled: false
        arguments:
          - "disableStutteringCheck"
  errcheck:
    check-type-assertions: true
  govet:
    check-shadowing: true
```

## Formatting

- **Follow Go's standard formatting practices**
- Always run gofmt or goimports on code before committing
- Use tabs for indentation (standard in Go)
- Limit line length to 100-120 characters for readability
- Group imports into stdlib, external, and internal
- Avoid long parameter lists
- Align struct fields and constant declarations for readability
- Use blank lines to separate logical sections of code
- Format error handling consistently (prefer early returns)
- Use gofumpt for stricter formatting (optional)
- Consistently position braces (Go standard: same line)

```go
// Formatted imports
import (
    "context"
    "fmt"
    "io"
    
    "github.com/pkg/errors"
    "go.uber.org/zap"
    
    "github.com/myorg/myproject/internal/config"
)

// Aligned struct definition
type Server struct {
    Name         string
    Port         int
    ReadTimeout  time.Duration
    WriteTimeout time.Duration
    Handler      http.Handler
    Logger       *zap.Logger
}

// Early return error handling
func ProcessRequest(ctx context.Context, req *Request) (*Response, error) {
    if req == nil {
        return nil, errors.New("nil request")
    }
    
    user, err := getUser(ctx, req.UserID)
    if err != nil {
        return nil, fmt.Errorf("get user: %w", err)
    }
    
    // Process the request with user
    return &Response{}, nil
}
```

## Security

- **Follow security best practices**
- Never hardcode secrets or credentials
- Use secure cryptographic libraries
- Implement proper input validation
- Use prepared statements for database queries
- Set appropriate timeouts for HTTP clients and servers
- Implement proper authentication and authorization
- Use secure random number generation (crypto/rand)
- Validate and sanitize all user input
- Use constant-time comparisons for sensitive data (crypto/subtle)
- Implement proper error handling that doesn't leak sensitive information
- Use TLS for all network communications
- Regularly update dependencies for security fixes

```go
// Secure password hashing
func HashPassword(password string) (string, error) {
    hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
    if err != nil {
        return "", fmt.Errorf("generating password hash: %w", err)
    }
    return string(hash), nil
}

// Secure random token generation
func GenerateToken(length int) (string, error) {
    b := make([]byte, length)
    if _, err := rand.Read(b); err != nil {
        return "", fmt.Errorf("generating random bytes: %w", err)
    }
    return base64.URLEncoding.EncodeToString(b), nil
}

// SQL injection prevention
func GetUserByID(ctx context.Context, db *sql.DB, id string) (*User, error) {
    // Use prepared statement with placeholder
    row := db.QueryRowContext(ctx, "SELECT id, name, email FROM users WHERE id = ?", id)
    
    var user User
    if err := row.Scan(&user.ID, &user.Name, &user.Email); err != nil {
        if err == sql.ErrNoRows {
            return nil, errors.New("user not found")
        }
        return nil, fmt.Errorf("querying user: %w", err)
    }
    
    return &user, nil
}
```

## Comments and Godoc

- **Write effective comments and documentation**
- Write comments that explain why, not what (the code shows what)
- Use godoc format for package, type, and function documentation
- Include examples for non-obvious functions
- Use clear, complete sentences
- Document exported symbols comprehensively
- Keep comments accurate and up-to-date with code changes
- Use // TODO: or // FIXME: prefixes for temporary code or known issues
- Add context to complex algorithms or design decisions
- Use informative package documentation
- Document concurrency safety and requirements

```go
// Package cache provides a thread-safe in-memory caching mechanism
// with support for expiration, max entries, and custom eviction policies.
package cache

// Cache is a thread-safe in-memory cache with expiring entries.
// All methods are safe for concurrent use.
type Cache struct {
    // fields...
}

// New creates a new Cache with the provided options.
//
// Example:
//
//     cache := New(
//         WithMaxEntries(1000),
//         WithDefaultExpiration(5 * time.Minute),
//     )
//
// The resulting cache is safe for concurrent use.
func New(options ...Option) *Cache {
    // implementation
}

// Get retrieves an entry from the cache by key.
// It returns the cached value and a boolean indicating
// whether the key was found.
func (c *Cache) Get(key string) (interface{}, bool) {
    // implementation
}
```

## Project Structure

- **Follow standard Go project structure**
- Organize your project according to the Standard Go Project Layout
- Use /cmd directory for main applications
- Use /internal for private application code
- Use /pkg for public library code
- Place all Go code under /cmd, /internal, or /pkg
- Use /api for API definitions (Swagger, Protocol Buffers)
- Use /configs for configuration file templates
- Use /scripts for build and deployment scripts
- Use /test for additional test data and tools
- Keep the root main.go minimal if used
- Use /docs for documentation
- Keep related files together in the same package

```
project/
├── README.md
├── go.mod
├── go.sum
├── api/                # API definitions (OpenAPI, Protocol Buffers)
├── cmd/                # Main applications
│   ├── server/         # API server application
│   │   └── main.go
│   └── cli/            # CLI application
│       └── main.go
├── configs/            # Configuration files
├── docs/               # Documentation
├── internal/           # Private code
│   ├── auth/           # Authentication package
│   ├── db/             # Database access
│   ├── server/         # Internal server implementation
│   └── handler/        # HTTP handlers
├── pkg/                # Public libraries
│   ├── models/         # Data models
│   └── utils/          # Utility functions
├── scripts/            # Build and CI/CD scripts
└── test/               # Additional test files and tools
```

## Recommended Tools

| Tool | Purpose |
|------|--------|
| go vet | Examines code for common mistakes |
| gofmt/goimports | Standard code formatting |
| golangci-lint | Fast, comprehensive linting |
| gotest | Test runner |
| staticcheck | Advanced static analysis |
| gosec | Security-focused linter |
| gocyclo | Cyclomatic complexity analysis |
| errcheck | Error handling verification |
| gopls | Official Go language server |
| go mod | Dependency management |
| gotests | Test boilerplate generation |
| delve | Go debugger |
