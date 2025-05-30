# Rust Development Best Practices Guide for AI Agents

## Core Principles

1. **Memory Safety First**: Leverage Rust's ownership system to prevent memory safety issues
2. **Zero-Cost Abstractions**: Use high-level abstractions without runtime overhead
3. **Expressive Types**: Use the type system to prevent bugs at compile time
4. **Explicit Error Handling**: Handle all errors explicitly, avoid panics in production code
5. **Performance Conscious**: Write code that's both safe and performant

## Project Structure and Organization

- **Follow Rust's conventional project structure**
- Use Cargo for project management
- Organize code into modules with clear responsibilities
- Place library code in `src/lib.rs` and executable code in `src/main.rs`
- Use `src/bin/` directory for multiple binaries
- Group related functionality in modules
- Use feature flags for optional functionality
- Follow the standard Rust project layout

```
project/
├── Cargo.toml       # Project metadata and dependencies
├── Cargo.lock       # Locked dependencies (commit for binaries, ignore for libraries)
├── src/             # Source code
│   ├── main.rs      # Binary entry point
│   ├── lib.rs       # Library entry point
│   └── module_name/ # Module directory
│       └── mod.rs   # Module definition
├── tests/           # Integration tests
├── benches/         # Benchmarks
├── examples/        # Example code
└── docs/            # Documentation
```

## Naming Conventions

- **Follow Rust's established naming conventions**
- Use `snake_case` for variables, functions, methods, modules, and file names
- Use `PascalCase` for types, traits, and enum variants
- Use `SCREAMING_SNAKE_CASE` for constants and static variables
- Use descriptive names that reflect purpose
- Prefer concise but clear names
- Use active verbs for functions that perform actions
- Use nouns for variables and parameters
- Avoid abbreviations unless they're well-known
- Prefix boolean variables with `is_`, `has_`, `should_`, etc.
- Use consistent naming patterns for similar concepts

```rust
// Good naming examples
const MAX_CONNECTIONS: usize = 100;
static DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);

struct HttpClient {
    base_url: String,
    timeout: Duration,
}

enum ConnectionState {
    Connected,
    Disconnected,
    Connecting,
}

fn process_request(request: &Request) -> Result<Response, Error> {
    // Implementation
}

let is_valid = validate_input(&input);
```

## Code Organization

- **Structure code for readability and maintainability**
- Keep functions focused on a single responsibility
- Limit function length (aim for < 50 lines)
- Use Rust's module system to organize code logically
- Group related functions and types in the same module
- Use public/private visibility appropriately
- Prefer composition over inheritance
- Use traits for shared behavior
- Keep public API surface minimal
- Use type aliases to improve readability
- Use newtype pattern to add type safety

```rust
// Newtype pattern example
pub struct UserId(pub String);
pub struct Email(pub String);

// Type alias example
type Result<T> = std::result::Result<T, Error>;

// Module organization
pub mod users {
    use super::Error;
    
    pub struct User {
        id: UserId,
        email: Email,
    }
    
    impl User {
        pub fn new(id: UserId, email: Email) -> Self {
            Self { id, email }
        }
        
        pub fn id(&self) -> &UserId {
            &self.id
        }
        
        pub fn email(&self) -> &Email {
            &self.email
        }
    }
    
    // Private helper function
    fn validate_email(email: &str) -> bool {
        // Implementation
    }
}
```

## Error Handling

- **Use Rust's Result and Option types for error handling**
- Return Result for operations that can fail
- Use Option for values that might be absent
- Create custom error types for specific error cases
- Implement the std::error::Error trait for custom errors
- Use the `?` operator for error propagation
- Provide context when propagating errors with `context` or `with_context`
- Use meaningful error messages
- Handle all error cases explicitly
- Avoid unwrap() and expect() in production code
- Use thiserror or anyhow crates for error handling

```rust
// Custom error type with thiserror
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ServiceError {
    #[error("resource not found: {id}")]
    NotFound { id: String },
    
    #[error("invalid input: {0}")]
    InvalidInput(String),
    
    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),
    
    #[error("unexpected error: {0}")]
    Other(#[from] anyhow::Error),
}

// Error handling with the ? operator
pub async fn get_user(id: &str) -> Result<User, ServiceError> {
    let user = db::find_user(id).await
        .map_err(|e| ServiceError::Database(e))?;
        
    if user.is_none() {
        return Err(ServiceError::NotFound { id: id.to_string() });
    }
    
    Ok(user.unwrap())
}

// Using anyhow for application code
use anyhow::{Result, Context};

fn process_file(path: &str) -> Result<()> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read file: {}", path))?;
        
    // Process content
    Ok(())
}
```

## Documentation

- **Document code thoroughly using Rust's documentation comments**
- Use `///` for documenting items (functions, structs, etc.)
- Use `//!` for module-level documentation
- Include examples in documentation for complex functions
- Document all public API items
- Use Markdown formatting in documentation
- Run `cargo doc` to generate documentation
- Include usage examples in documentation
- Document panics, errors, and safety considerations
- Keep documentation up to date when code changes
- Use `#[must_use]` for functions with important return values

```rust
//! User management module.
//!
//! This module provides functionality for creating, retrieving,
//! and authenticating users.

/// Represents a registered user in the system.
#[derive(Debug, Clone)]
pub struct User {
    /// Unique identifier for the user
    pub id: String,
    /// User's email address
    pub email: String,
    /// When the user was created
    pub created_at: DateTime<Utc>,
}

/// Creates a new user with the provided email.
///
/// # Arguments
///
/// * `email` - The email address for the new user
///
/// # Returns
///
/// A Result containing the new User or an error if creation fails.
///
/// # Examples
///
/// ```
/// let user = create_user("user@example.com")?;
/// assert_eq!(user.email, "user@example.com");
/// ```
///
/// # Errors
///
/// Returns an error if:
/// - The email is invalid
/// - A user with this email already exists
/// - The database operation fails
pub fn create_user(email: &str) -> Result<User, Error> {
    // Implementation
}
```

## Testing

- **Write comprehensive tests for your code**
- Use `#[test]` attribute for unit tests
- Place unit tests in the same file as the code being tested
- Use the `tests/` directory for integration tests
- Write both positive and negative test cases
- Use `#[should_panic]` for tests that expect panics
- Use test fixtures for common setup
- Use parameterized tests with macros or loops
- Mock external dependencies for unit tests
- Use `assert!`, `assert_eq!`, and `assert_ne!` macros
- Aim for high test coverage
- Use `cargo test` to run tests
- Use `#[cfg(test)]` for test-only code

```rust
// Unit test in the same file
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_create_user_valid_email() {
        let email = "test@example.com";
        let result = create_user(email);
        assert!(result.is_ok());
        let user = result.unwrap();
        assert_eq!(user.email, email);
    }
    
    #[test]
    fn test_create_user_invalid_email() {
        let result = create_user("invalid-email");
        assert!(result.is_err());
        match result {
            Err(Error::InvalidInput(msg)) => {
                assert!(msg.contains("email"));
            }
            _ => panic!("Expected InvalidInput error"),
        }
    }
    
    #[test]
    #[should_panic(expected = "null pointer")]
    fn test_panicking_function() {
        // Test a function that should panic
        unsafe_function(std::ptr::null());
    }
}

// Integration test in tests/ directory
// In tests/api_tests.rs
use my_crate::api;

#[test]
fn test_api_endpoint() {
    let client = api::Client::new("http://localhost:8080");
    let response = client.get("/status").send().unwrap();
    assert_eq!(response.status(), 200);
}
```

## Performance Optimization

- **Write efficient Rust code**
- Profile before optimizing
- Use iterators for clean, efficient data processing
- Use the `--release` flag for optimized builds
- Avoid unnecessary allocations and copies
- Use references instead of cloning when possible
- Use `Vec::with_capacity` when size is known
- Use `String::with_capacity` for building strings
- Consider using custom allocators for specific use cases
- Use `#[inline]` judiciously for small, frequently called functions
- Use `std::mem::replace` to avoid allocations
- Consider using SIMD instructions for data-parallel operations
- Use Rayon for parallel processing
- Benchmark critical code paths

```rust
// Efficient string building
fn build_report(items: &[Item]) -> String {
    // Pre-allocate with estimated capacity
    let mut result = String::with_capacity(items.len() * 20);
    
    result.push_str("Report:\n");
    for item in items {
        result.push_str(&format!("- {}: ${:.2}\n", item.name, item.price));
    }
    
    result
}

// Efficient vector operations
fn filter_items(items: &[Item], predicate: impl Fn(&Item) -> bool) -> Vec<Item> {
    // Pre-allocate result vector (conservative capacity)
    let mut result = Vec::with_capacity(items.len() / 2);
    
    for item in items {
        if predicate(item) {
            result.push(item.clone());
        }
    }
    
    result
}

// Using iterators efficiently
fn process_data(data: &[i32]) -> Vec<i32> {
    data.iter()
        .filter(|&x| x % 2 == 0)
        .map(|&x| x * 2)
        .collect()
}
```

## Memory Management

- **Leverage Rust's ownership system effectively**
- Understand ownership, borrowing, and lifetimes
- Use references (`&T`) for read-only access
- Use mutable references (`&mut T`) for in-place modification
- Minimize use of `Rc<T>` and `Arc<T>` to cases that need shared ownership
- Use `Box<T>` for heap allocation when needed
- Understand stack vs. heap allocation tradeoffs
- Use `'static` lifetime judiciously
- Avoid unnecessary clones
- Use `Cow<T>` for clone-on-write semantics
- Consider using custom lifetime parameters for flexible APIs
- Use slice patterns (`&[T]`) instead of vectors when possible
- Understand when to use `Copy` vs. `Clone` traits

```rust
// Effective ownership examples
fn process_data(data: &[u8]) -> Vec<u8> {
    // Borrow data immutably, return owned result
    data.iter().map(|&b| b * 2).collect()
}

// Using lifetimes effectively
struct Parser<'a> {
    input: &'a str,
    position: usize,
}

impl<'a> Parser<'a> {
    fn new(input: &'a str) -> Self {
        Self { input, position: 0 }
    }
    
    fn peek(&self) -> Option<char> {
        self.input[self.position..].chars().next()
    }
    
    fn consume(&mut self) -> Option<char> {
        let c = self.peek()?;
        self.position += c.len_utf8();
        Some(c)
    }
}
```

## Concurrency and Parallelism

- **Use Rust's concurrency features safely and effectively**
- Prefer message passing over shared state
- Use channels for communication between threads
- Use `std::sync` primitives for shared state
- Use `Mutex` for exclusive access to shared data
- Use `RwLock` when multiple readers are common
- Use `Arc` for sharing ownership across threads
- Use `tokio` or `async-std` for async programming
- Use `Future` trait for asynchronous operations
- Use `async`/`await` syntax for readable async code
- Use `Rayon` for data parallelism
- Avoid data races through the type system
- Be aware of deadlock possibilities
- Use `crossbeam` for advanced concurrency primitives

```rust
// Thread-safe counter
use std::sync::{Arc, Mutex};
use std::thread;

fn main() {
    let counter = Arc::new(Mutex::new(0));
    let mut handles = vec![];
    
    for _ in 0..10 {
        let counter = Arc::clone(&counter);
        let handle = thread::spawn(move || {
            let mut num = counter.lock().unwrap();
            *num += 1;
        });
        handles.push(handle);
    }
    
    for handle in handles {
        handle.join().unwrap();
    }
    
    println!("Result: {}", *counter.lock().unwrap());
}

// Async/await example
use tokio::time::{sleep, Duration};

async fn fetch_data(id: u32) -> Result<String, Error> {
    sleep(Duration::from_millis(100)).await; // Simulate network delay
    Ok(format!("Data for ID {}", id))
}

async fn process_all() -> Result<Vec<String>, Error> {
    let mut results = Vec::new();
    
    let mut handles = Vec::new();
    for i in 1..=10 {
        handles.push(tokio::spawn(fetch_data(i)));
    }
    
    for handle in handles {
        let result = handle.await??;
        results.push(result);
    }
    
    Ok(results)
}
```

## Safety and Unsafe Code

- **Minimize use of unsafe code**
- Encapsulate unsafe code in safe abstractions
- Document safety invariants for unsafe functions
- Use `unsafe` only when necessary
- Validate all preconditions before unsafe operations
- Maintain safety invariants throughout unsafe blocks
- Use `#[deny(unsafe_code)]` to prevent unsafe code in critical crates
- Thoroughly test unsafe code
- Consider formal verification for critical unsafe code
- Document why unsafe code is necessary
- Use the `unsafe` keyword as a signal, not a solution
- Understand the Rust memory model

```rust
// Safe abstraction over unsafe code
pub struct RawBuffer {
    ptr: *mut u8,
    len: usize,
    capacity: usize,
}

impl RawBuffer {
    pub fn new(capacity: usize) -> Self {
        let layout = std::alloc::Layout::array::<u8>(capacity).unwrap();
        let ptr = unsafe { std::alloc::alloc(layout) };
        if ptr.is_null() {
            std::alloc::handle_alloc_error(layout);
        }
        
        Self {
            ptr,
            len: 0,
            capacity,
        }
    }
    
    pub fn push(&mut self, byte: u8) -> Result<(), &'static str> {
        if self.len >= self.capacity {
            return Err("buffer is full");
        }
        
        unsafe {
            *self.ptr.add(self.len) = byte;
        }
        self.len += 1;
        Ok(())
    }
    
    pub fn as_slice(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
}

impl Drop for RawBuffer {
    fn drop(&mut self) {
        let layout = std::alloc::Layout::array::<u8>(self.capacity).unwrap();
        unsafe {
            std::alloc::dealloc(self.ptr, layout);
        }
    }
}
```

## Dependency Management

- **Manage dependencies effectively**
- Keep dependencies minimal and focused
- Specify version requirements precisely in Cargo.toml
- Regularly audit dependencies for security issues with `cargo audit`
- Consider vendoring dependencies for critical applications
- Use workspaces for multi-crate projects
- Use feature flags to make dependencies optional
- Prefer well-maintained, popular crates
- Review the source code of critical dependencies
- Be cautious about transitive dependencies
- Use semantic versioning for your own crates
- Document dependencies in README.md

```toml
# Example Cargo.toml with well-specified dependencies
[package]
name = "my_app"
version = "0.1.0"
edition = "2021"
authors = ["Your Name <your.email@example.com>"]
description = "A description of my application"
license = "MIT OR Apache-2.0"

[dependencies]
# Core dependencies with exact versions
serde = { version = "1.0.152", features = ["derive"] }
tokio = { version = "1.25.0", features = ["full"] }
axum = "0.6.4"

# Optional dependencies
tracing = { version = "0.1.37", optional = true }

# Development dependencies
[dev-dependencies]
criterion = "0.4.0"
mockall = "0.11.3"

# Feature flags
[features]
default = ["logging"]
logging = ["tracing"]
```

## Code Review Checklist

Before submitting code, ensure:

- [ ] All compiler warnings are addressed
- [ ] Code follows Rust naming conventions
- [ ] Public API is well-documented
- [ ] Error cases are handled appropriately
- [ ] Tests cover both success and failure cases
- [ ] No unnecessary unsafe code
- [ ] No unwrap() or expect() in production code paths
- [ ] Performance considerations addressed
- [ ] Dependencies are properly specified
- [ ] Code is formatted with rustfmt
- [ ] Clippy lints pass without warnings
- [ ] Documentation examples compile and run
- [ ] Breaking changes are documented