# React Development Best Practices Guide for AI Agents

## Core Principles

1. **Functional Components Only**: All React components must be written as functional components - no class-based components allowed
2. **Component-First Architecture**: Build reusable, composable components
3. **TypeScript Integration**: Leverage strict typing for React components and hooks
4. **Modern React Patterns**: Use hooks and modern state management
5. **Module Federation Ready**: Design components for micro-frontend architecture
6. **Performance by Design**: Optimize for rendering performance and bundle size
7. **Security Conscious**: Follow React security best practices

## Project Structure

### Standard React Project Layout

```
src/
├── components/           # Reusable UI components
│   ├── ui/              # Basic UI components (Button, Input, etc.)
│   ├── forms/           # Form-specific components
│   ├── layout/          # Layout components (Header, Footer, etc.)
│   └── index.ts         # Barrel exports
├── hooks/               # Custom React hooks
├── contexts/            # React Context providers
├── pages/               # Page-level components
├── services/            # API and external service integrations
├── utils/               # Utility functions
├── types/               # TypeScript type definitions
├── assets/              # Static assets (images, fonts, etc.)
├── styles/              # Global styles and themes
├── __tests__/           # Test files
├── mocks/               # Mock data and handlers
└── federation/          # Module federation specific exports
    ├── exposes/         # Components exposed to other apps
    └── remotes/         # Remote component imports
```

## Vite Configuration for Module Federation

### Core Vite Setup

```typescript
// vite.config.ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import federation from '@originjs/vite-plugin-federation'

export default defineConfig({
  plugins: [
    react(),
    federation({
      name: 'host-app',
      remotes: {
        'remote-app': 'http://localhost:3001/assets/remoteEntry.js',
      },
      exposes: {
        './Button': './src/components/ui/Button',
        './UserProfile': './src/components/UserProfile',
      },
      shared: {
        react: {
          singleton: true,
          requiredVersion: '^18.0.0',
        },
        'react-dom': {
          singleton: true,
          requiredVersion: '^18.0.0',
        },
      },
    }),
  ],
  build: {
    target: 'esnext',
    minify: false,
    cssCodeSplit: false,
  },
})
```

### Module Federation Best Practices

1. **Expose Components Thoughtfully**:
   ```typescript
   // Good - Clean component interface
   export interface ButtonProps {
     variant?: 'primary' | 'secondary' | 'danger';
     size?: 'sm' | 'md' | 'lg';
     disabled?: boolean;
     onClick?: (event: React.MouseEvent<HTMLButtonElement>) => void;
     children: React.ReactNode;
   }

   export const Button: React.FC<ButtonProps> = ({
     variant = 'primary',
     size = 'md',
     disabled = false,
     onClick,
     children,
     ...props
   }) => {
     return (
       <button
         className={cn('btn', `btn-${variant}`, `btn-${size}`)}
         disabled={disabled}
         onClick={onClick}
         {...props}
       >
         {children}
       </button>
     );
   };
   ```

2. **Version Compatibility**:
   - Always specify compatible React versions in shared dependencies
   - Use semantic versioning for exposed components
   - Document breaking changes in component APIs

3. **Error Boundaries for Remote Components**:
   ```typescript
   export const RemoteComponentWrapper: React.FC<{
     children: React.ReactNode;
     fallback?: React.ReactNode;
   }> = ({ children, fallback = <div>Failed to load component</div> }) => {
     return (
       <ErrorBoundary fallback={fallback}>
         <Suspense fallback={<LoadingSpinner />}>
           {children}
         </Suspense>
       </ErrorBoundary>
     );
   };
   ```

## Component Development Rules

### Component Structure

1. **Functional Components Only** - No class-based components allowed
2. **Props Interface Definition** - Always define explicit TypeScript interfaces for props
3. **Component Export Pattern** - Use named exports with barrel exports for clean imports

### Hooks Usage

1. **Custom Hooks** - Extract reusable logic into custom hooks
2. **State Management** - Use useState for simple state, useReducer for complex state
3. **Effect Dependencies** - Always include all dependencies and cleanup effects properly
4. **Performance Hooks** - Use useCallback and useMemo to optimize re-renders

## State Management

### Context API
- Create typed contexts with custom hooks for access
- Use Provider pattern for wrapping components
- Throw errors when context is used outside of provider

### Zustand for Global State
- Use for global application state management
- Apply middleware: immer for immutability, persist for storage, subscribeWithSelector for granular subscriptions
- Implement slice pattern for large stores
- Create custom selectors for performance optimization

## Testing Strategy

### Component Testing
- Use Vitest with React Testing Library
- Test user interactions and component behavior
- Use MSW (Mock Service Worker) for API mocking
- Test hooks with renderHook utility
- Maintain minimum 80% code coverage

## Performance Optimization

### React Optimization Patterns
- Use React.memo for expensive component re-renders
- Use useMemo for expensive computations
- Use useCallback for stable function references
- Implement code splitting with lazy loading
- Use virtual scrolling for large lists (react-window)
- Optimize bundle size with tree shaking

## Security Best Practices

### Input Sanitization
- Always sanitize HTML content with DOMPurify before rendering
- Validate all form inputs on both client and server
- Never trust user input
- Use proper encoding for different contexts

### Authentication & Authorization
- Implement protected routes with role-based access
- Store tokens securely (httpOnly cookies preferred)
- Implement CSRF protection
- Use secure headers (CSP, X-Frame-Options, etc.)

## Styling with Tailwind CSS

### Tailwind Configuration
- Use Tailwind CSS as the primary styling solution
- Configure dark mode with 'class' strategy
- Extend theme with custom colors, spacing, and animations
- Use official Tailwind plugins (forms, typography, aspect-ratio)

### Component Styling Patterns
- Use cn() utility (clsx + tailwind-merge) for conditional classes
- Create variant-based component styles
- Implement responsive design with mobile-first approach
- Use CSS variables for theming

### Design System
- Use CSS variables for theming
- Implement dark mode with class-based switching
- Create reusable component classes with @layer
- Use mobile-first responsive design
- Implement smooth animations and transitions

## Error Handling

### Error Boundaries
- Use react-error-boundary package for functional error boundaries
- Implement fallback UI for error states
- Log errors to monitoring services
- Provide user-friendly error messages
- Implement error recovery mechanisms

## Accessibility (A11Y)

### Semantic HTML and ARIA
- Use semantic HTML elements (nav, main, article, section)
- Provide proper ARIA labels and descriptions
- Ensure keyboard navigation support
- Implement focus management for modals and overlays
- Test with screen readers
- Maintain proper heading hierarchy

## Code Quality and Linting

### ESLint Configuration
- Extend recommended React and TypeScript configs
- Enable react-hooks rules
- Enable jsx-a11y for accessibility
- Disable prop-types (using TypeScript)
- Configure for React 17+ JSX transform
- Use Prettier for formatting

## Build and Deployment

### Production Optimization
- Configure code splitting with manualChunks
- Remove console and debugger statements in production
- Optimize bundle size with tree shaking
- Use environment variables for configuration
- Implement proper caching strategies
- Enable gzip/brotli compression

## Module Federation

### Component Sharing
- Use semantic versioning for exposed components
- Maintain backward compatibility
- Wrap remote components in error boundaries and suspense
- Share singleton dependencies (React, React-DOM)
- Document breaking changes clearly

### Routing Patterns
- Use React Router v6 with createBrowserRouter
- Lazy load remote applications
- Implement nested routing for micro-frontends
- Handle cross-app navigation with navigation service

### Cross-App Communication
- Implement event bus for decoupled communication
- Use shared Zustand store for global state
- Create typed event interfaces
- Handle errors in event listeners gracefully
- Sync store changes with event bus
### Dependency Management
- Configure shared dependencies with singleton: true for React ecosystem
- Use semantic versioning for shared libraries
- Create type definitions for federated modules
- Share design system and utilities across apps
- Maintain consistent versions across micro-frontends

## Recommended Tools

| Category | Tool | Purpose |
|----------|------|---------|
| Build | Vite | Fast development and building |
| Testing | Vitest + Testing Library | Unit and integration testing |
| State | Zustand | Global state management |
| Styling | Tailwind CSS | Utility-first CSS framework |
| Forms | React Hook Form | Form handling and validation |
| Animation | Framer Motion | Animations and transitions |
| UI Components | Headless UI / Radix UI | Accessible component primitives |
| Routing | React Router v6 | Client-side routing |
| API | TanStack Query | Server state management |
| TypeScript | TypeScript 5+ | Static type checking |
| Linting | ESLint + React plugins | Code quality enforcement |
| Mocks | MSW | API mocking for testing |
| Error Boundaries | react-error-boundary | Functional error boundaries |
| Module Federation | @originjs/vite-plugin-federation | Micro-frontend architecture |

## Key Requirements

1. **ALL components must be functional components - NO class components**
2. Use hooks for all state management and side effects
3. Always use TypeScript with strict mode enabled
4. Follow functional programming principles
5. Implement proper error boundaries using react-error-boundary package
6. Test all components with Vitest and Testing Library