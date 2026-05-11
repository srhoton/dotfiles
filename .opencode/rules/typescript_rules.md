# TypeScript AI Development Rules and Best Practices

## Core Principles

1. **Type Safety First**: Always prioritize type safety over convenience
2. **Explicit Over Implicit**: Be explicit about types, avoid relying on type inference for public APIs
3. **Fail Fast**: Catch errors at compile time rather than runtime
4. **Security by Design**: Consider security implications in every code decision

## TypeScript Configuration

### tsconfig.json Best Practices

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "allowUnreachableCode": false,
    "allowUnusedLabels": false,
    "exactOptionalPropertyTypes": true,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "strictBindCallApply": true,
    "strictPropertyInitialization": true,
    "alwaysStrict": true
  }
}
```

## Linting Rules

### ESLint Configuration

Use these ESLint rules for TypeScript projects:

```javascript
{
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:@typescript-eslint/recommended-requiring-type-checking",
    "plugin:security/recommended",
    "plugin:sonarjs/recommended"
  ],
  "plugins": [
    "@typescript-eslint",
    "security",
    "sonarjs",
    "import",
    "promise"
  ],
  "rules": {
    // TypeScript specific
    "@typescript-eslint/explicit-function-return-type": "error",
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": ["error", { "argsIgnorePattern": "^_" }],
    "@typescript-eslint/no-non-null-assertion": "error",
    "@typescript-eslint/strict-boolean-expressions": "error",
    "@typescript-eslint/no-floating-promises": "error",
    "@typescript-eslint/no-misused-promises": "error",
    "@typescript-eslint/await-thenable": "error",
    "@typescript-eslint/no-unnecessary-type-assertion": "error",
    "@typescript-eslint/prefer-nullish-coalescing": "error",
    "@typescript-eslint/prefer-optional-chain": "error",
    "@typescript-eslint/prefer-readonly": "error",
    "@typescript-eslint/prefer-string-starts-ends-with": "error",
    "@typescript-eslint/no-unsafe-assignment": "error",
    "@typescript-eslint/no-unsafe-member-access": "error",
    "@typescript-eslint/no-unsafe-call": "error",
    "@typescript-eslint/no-unsafe-return": "error",
    
    // Import rules
    "import/no-cycle": "error",
    "import/no-unresolved": "error",
    "import/no-unused-modules": "error",
    "import/order": ["error", {
      "groups": ["builtin", "external", "internal", "parent", "sibling", "index"],
      "newlines-between": "always",
      "alphabetize": { "order": "asc" }
    }],
    
    // General best practices
    "no-console": ["error", { "allow": ["warn", "error"] }],
    "no-debugger": "error",
    "no-alert": "error",
    "no-var": "error",
    "prefer-const": "error",
    "eqeqeq": ["error", "always"],
    "curly": ["error", "all"],
    "no-throw-literal": "error",
    "prefer-promise-reject-errors": "error",
    "no-return-await": "error",
    "require-await": "error",
    "no-async-promise-executor": "error",
    "no-promise-executor-return": "error"
  }
}
```

### Code Style Rules

1. **Naming Conventions**:
   - Use PascalCase for types, interfaces, enums, and classes
   - Use camelCase for variables, functions, and methods
   - Use UPPER_SNAKE_CASE for constants
   - Prefix interfaces with 'I' only when necessary to avoid naming conflicts
   - Use descriptive names that clearly indicate purpose

2. **File Organization**:
   - One class/interface per file for major components
   - Group related types in a single file when they're tightly coupled
   - Keep files under 300 lines when possible
   - Use barrel exports (index.ts) for clean module boundaries

## Security Rules

### Input Validation

1. **Always validate external inputs**:
   ```typescript
   // Good
   function processUserInput(input: unknown): string {
     if (typeof input !== 'string') {
       throw new Error('Input must be a string');
     }
     if (input.length > 1000) {
       throw new Error('Input too long');
     }
     return sanitizeInput(input);
   }
   ```

2. **Use type guards for runtime validation**:
   ```typescript
   function isValidUser(obj: unknown): obj is User {
     return (
       typeof obj === 'object' &&
       obj !== null &&
       'id' in obj &&
       'email' in obj &&
       typeof (obj as any).id === 'string' &&
       typeof (obj as any).email === 'string'
     );
   }
   ```

### Security Best Practices

1. **Never use eval() or Function constructor**
2. **Sanitize all user inputs before processing**
3. **Use parameterized queries for database operations**
4. **Implement proper authentication and authorization checks**
5. **Never store sensitive data in plain text**
6. **Use environment variables for configuration**
7. **Implement rate limiting for APIs**
8. **Use HTTPS for all communications**
9. **Validate and sanitize file uploads**
10. **Implement proper CORS policies**

### Dependency Security

1. **Audit dependencies regularly**:
   ```bash
   npm audit
   npm audit fix
   ```

2. **Use exact versions in package.json**:
   ```json
   {
     "dependencies": {
       "express": "4.18.2",
       "typescript": "5.0.4"
     }
   }
   ```

3. **Review dependency licenses**
4. **Minimize dependency usage**
5. **Keep dependencies up to date**

## Testing Rules

### Testing Strategy

1. **Test Coverage Requirements**:
   - Minimum 80% code coverage
   - 100% coverage for critical business logic
   - All public APIs must have tests

2. **Test Types**:
   - Unit tests for individual functions/methods
   - Integration tests for module interactions
   - End-to-end tests for critical user flows

### Unit Testing Best Practices

1. **Test Structure**:
   ```typescript
   describe('UserService', () => {
     describe('createUser', () => {
       it('should create a user with valid input', async () => {
         // Arrange
         const input = { email: 'test@example.com', name: 'Test User' };
         
         // Act
         const result = await userService.createUser(input);
         
         // Assert
         expect(result).toBeDefined();
         expect(result.email).toBe(input.email);
       });
       
       it('should throw error for invalid email', async () => {
         // Arrange
         const input = { email: 'invalid-email', name: 'Test User' };
         
         // Act & Assert
         await expect(userService.createUser(input)).rejects.toThrow('Invalid email');
       });
     });
   });
   ```

2. **Testing Guidelines**:
   - Use descriptive test names that explain what is being tested
   - Follow AAA pattern (Arrange, Act, Assert)
   - Test one thing per test
   - Use beforeEach/afterEach for setup/teardown
   - Mock external dependencies
   - Test edge cases and error conditions
   - Use data-driven tests for multiple scenarios

3. **Mocking Best Practices**:
   ```typescript
   // Good - Type-safe mocking
   const mockRepository = {
     findById: jest.fn().mockResolvedValue({ id: '1', name: 'Test' }),
     save: jest.fn().mockResolvedValue(true)
   } satisfies UserRepository;
   ```

### Integration Testing

1. **Database Testing**:
   - Use test databases
   - Clean up data after each test
   - Use transactions when possible

2. **API Testing**:
   - Test all HTTP methods
   - Verify status codes
   - Validate response schemas
   - Test authentication/authorization

## Type Safety Rules

### Type Definitions

1. **Avoid any at all costs**:
   ```typescript
   // Bad
   function process(data: any): any { }
   
   // Good
   function process<T extends Record<string, unknown>>(data: T): ProcessedData<T> { }
   ```

2. **Use discriminated unions**:
   ```typescript
   type Result<T> = 
     | { success: true; data: T }
     | { success: false; error: Error };
   ```

3. **Prefer interfaces for object types**:
   ```typescript
   // Good for object shapes
   interface User {
     id: string;
     email: string;
     profile: UserProfile;
   }
   
   // Good for union types or computed types
   type UserRole = 'admin' | 'user' | 'guest';
   ```

### Type Guards and Assertions

1. **Create reusable type guards**:
   ```typescript
   function isString(value: unknown): value is string {
     return typeof value === 'string';
   }
   
   function isNonNullable<T>(value: T): value is NonNullable<T> {
     return value !== null && value !== undefined;
   }
   ```

2. **Use assertion functions**:
   ```typescript
   function assertDefined<T>(value: T | undefined, message?: string): asserts value is T {
     if (value === undefined) {
       throw new Error(message ?? 'Value is undefined');
     }
   }
   ```

## Error Handling Rules

### Error Management

1. **Create custom error classes**:
   ```typescript
   class ValidationError extends Error {
     constructor(public field: string, public value: unknown) {
       super(`Validation failed for field ${field}`);
       this.name = 'ValidationError';
     }
   }
   ```

2. **Use Result types for expected errors**:
   ```typescript
   type Result<T, E = Error> = 
     | { ok: true; value: T }
     | { ok: false; error: E };
   ```

3. **Always handle Promise rejections**:
   ```typescript
   // Good
   async function fetchData(): Promise<Result<Data>> {
     try {
       const data = await api.getData();
       return { ok: true, value: data };
     } catch (error) {
       return { ok: false, error: error instanceof Error ? error : new Error('Unknown error') };
     }
   }
   ```

## Performance Rules

1. **Avoid premature optimization**
2. **Use const assertions for literal types**:
   ```typescript
   const config = {
     apiUrl: 'https://api.example.com',
     timeout: 5000
   } as const;
   ```

3. **Prefer Map/Set over objects for collections**
4. **Use lazy evaluation when appropriate**
5. **Implement caching for expensive operations**

## Documentation Rules

1. **Document all public APIs with JSDoc**:
   ```typescript
   /**
    * Creates a new user in the system
    * @param userData - The user data to create
    * @returns The created user or an error
    * @throws {ValidationError} When userData is invalid
    * @example
    * const result = await createUser({ email: 'user@example.com', name: 'John' });
    */
   async function createUser(userData: CreateUserInput): Promise<User> {
     // Implementation
   }
   ```

2. **Use meaningful variable and function names**
3. **Add comments for complex logic**
4. **Keep README files up to date**

## Code Review Checklist

Before submitting code, ensure:

- [ ] All TypeScript compiler errors are resolved
- [ ] ESLint passes without errors
- [ ] All tests pass
- [ ] Code coverage meets requirements
- [ ] Security vulnerabilities are addressed
- [ ] Documentation is updated
- [ ] No hardcoded values or secrets
- [ ] Error handling is comprehensive
- [ ] Performance implications considered
- [ ] Breaking changes are documented
