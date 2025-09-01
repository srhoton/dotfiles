# React Development Best Practices Guide for AI Agents

## Core Principles

1. **Component-First Architecture**: Build reusable, composable components
2. **TypeScript Integration**: Leverage strict typing for React components and hooks
3. **Modern React Patterns**: Use hooks, functional components, and modern state management
4. **Module Federation Ready**: Design components for micro-frontend architecture
5. **Performance by Design**: Optimize for rendering performance and bundle size
6. **Security Conscious**: Follow React security best practices

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

1. **Functional Components Only**:
   ```typescript
   // Good
   interface UserCardProps {
     user: User;
     onEdit?: (user: User) => void;
     className?: string;
   }

   export const UserCard: React.FC<UserCardProps> = ({
     user,
     onEdit,
     className,
   }) => {
     return (
       <div className={cn('user-card', className)}>
         <h3>{user.name}</h3>
         <p>{user.email}</p>
         {onEdit && (
           <button onClick={() => onEdit(user)}>Edit</button>
         )}
       </div>
     );
   };
   ```

2. **Props Interface Definition**:
   - Always define explicit prop interfaces
   - Use optional properties with default values
   - Document complex props with JSDoc
   - Extend HTML element props when appropriate

   ```typescript
   interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
     label: string;
     error?: string;
     helperText?: string;
   }
   ```

3. **Component Export Pattern**:
   ```typescript
   // Component file: Button.tsx
   export const Button: React.FC<ButtonProps> = ({ ... }) => { ... };
   
   // Barrel export: components/index.ts
   export { Button } from './ui/Button';
   export { UserCard } from './UserCard';
   export type { ButtonProps, UserCardProps } from './types';
   ```

### Hooks Usage

1. **Custom Hooks for Logic Reuse**:
   ```typescript
   // hooks/useApi.ts
   export function useApi<T>(url: string) {
     const [data, setData] = useState<T | null>(null);
     const [loading, setLoading] = useState(true);
     const [error, setError] = useState<Error | null>(null);

     useEffect(() => {
       const fetchData = async () => {
         try {
           setLoading(true);
           const response = await fetch(url);
           if (!response.ok) throw new Error(`HTTP ${response.status}`);
           const result = await response.json();
           setData(result);
         } catch (err) {
           setError(err instanceof Error ? err : new Error('Unknown error'));
         } finally {
           setLoading(false);
         }
       };

       fetchData();
     }, [url]);

     return { data, loading, error };
   }
   ```

2. **State Management Patterns**:
   ```typescript
   // For complex state - use useReducer
   type Action = 
     | { type: 'SET_LOADING'; payload: boolean }
     | { type: 'SET_DATA'; payload: User[] }
     | { type: 'SET_ERROR'; payload: string };

   function userReducer(state: UserState, action: Action): UserState {
     switch (action.type) {
       case 'SET_LOADING':
         return { ...state, loading: action.payload };
       case 'SET_DATA':
         return { ...state, data: action.payload, loading: false, error: null };
       case 'SET_ERROR':
         return { ...state, error: action.payload, loading: false };
       default:
         return state;
     }
   }
   ```

3. **Effect Dependencies**:
   - Always include all dependencies in useEffect
   - Use useCallback and useMemo for optimization
   - Cleanup effects properly

   ```typescript
   useEffect(() => {
     const controller = new AbortController();
     
     const fetchData = async () => {
       try {
         const response = await fetch(url, { 
           signal: controller.signal 
         });
         // Process response
       } catch (error) {
         if (error.name !== 'AbortError') {
           setError(error);
         }
       }
     };

     fetchData();

     return () => controller.abort();
   }, [url]);
   ```

## State Management

### Context API Usage

1. **Create Typed Contexts**:
   ```typescript
   interface AuthContextValue {
     user: User | null;
     login: (credentials: LoginCredentials) => Promise<void>;
     logout: () => void;
     loading: boolean;
   }

   const AuthContext = createContext<AuthContextValue | undefined>(undefined);

   export function useAuth(): AuthContextValue {
     const context = useContext(AuthContext);
     if (context === undefined) {
       throw new Error('useAuth must be used within an AuthProvider');
     }
     return context;
   }
   ```

2. **Provider Pattern**:
   ```typescript
   export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({
     children,
   }) => {
     const [user, setUser] = useState<User | null>(null);
     const [loading, setLoading] = useState(false);

     const login = async (credentials: LoginCredentials) => {
       setLoading(true);
       try {
         const user = await authService.login(credentials);
         setUser(user);
       } finally {
         setLoading(false);
       }
     };

     const value = { user, login, logout: () => setUser(null), loading };

     return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
   };
   ```

### Zustand for Global State Management

1. **Store Structure and Best Practices**:
   ```typescript
   import { create } from 'zustand';
   import { subscribeWithSelector } from 'zustand/middleware';
   import { immer } from 'zustand/middleware/immer';
   import { persist } from 'zustand/middleware';

   interface AppState {
     // State
     theme: 'light' | 'dark';
     sidebar: boolean;
     notifications: Notification[];
     user: User | null;
     
     // Actions
     setTheme: (theme: 'light' | 'dark') => void;
     toggleSidebar: () => void;
     addNotification: (notification: Notification) => void;
     removeNotification: (id: string) => void;
     setUser: (user: User | null) => void;
   }

   export const useAppStore = create<AppState>()(
     subscribeWithSelector(
       persist(
         immer((set, get) => ({
           // Initial state
           theme: 'light',
           sidebar: false,
           notifications: [],
           user: null,
           
           // Actions
           setTheme: (theme) => set({ theme }),
           toggleSidebar: () => set((state) => { state.sidebar = !state.sidebar }),
           addNotification: (notification) => set((state) => {
             state.notifications.push({ ...notification, id: crypto.randomUUID() });
           }),
           removeNotification: (id) => set((state) => {
             state.notifications = state.notifications.filter(n => n.id !== id);
           }),
           setUser: (user) => set({ user }),
         })),
         {
           name: 'app-store',
           partialize: (state) => ({ theme: state.theme, user: state.user }),
         }
       )
     )
   );
   ```

2. **Slice Pattern for Large Stores**:
   ```typescript
   // stores/slices/authSlice.ts
   export interface AuthSlice {
     user: User | null;
     isAuthenticated: boolean;
     login: (credentials: LoginCredentials) => Promise<void>;
     logout: () => void;
   }

   export const createAuthSlice: StateCreator<
     AppState,
     [],
     [],
     AuthSlice
   > = (set, get) => ({
     user: null,
     isAuthenticated: false,
     login: async (credentials) => {
       try {
         const user = await authService.login(credentials);
         set({ user, isAuthenticated: true });
       } catch (error) {
         throw error;
       }
     },
     logout: () => set({ user: null, isAuthenticated: false }),
   });

   // stores/index.ts
   export const useAppStore = create<AppState>()((...a) => ({
     ...createAuthSlice(...a),
     ...createUISlice(...a),
     ...createNotificationSlice(...a),
   }));
   ```

3. **Store Selectors for Performance**:
   ```typescript
   // Custom selectors
   export const useAuth = () => useAppStore((state) => ({
     user: state.user,
     isAuthenticated: state.isAuthenticated,
     login: state.login,
     logout: state.logout,
   }));

   export const useTheme = () => useAppStore((state) => state.theme);
   export const useNotifications = () => useAppStore((state) => state.notifications);

   // Derived state selectors
   export const useUnreadNotifications = () => 
     useAppStore((state) => state.notifications.filter(n => !n.read));
   ```

4. **Store Persistence and Hydration**:
   ```typescript
   // Handle hydration in _app.tsx or main component
   const App: React.FC = () => {
     const [isHydrated, setIsHydrated] = useState(false);

     useEffect(() => {
       // Wait for Zustand to rehydrate
       const unsubscribe = useAppStore.persist.onFinishHydration(() => {
         setIsHydrated(true);
       });

       return unsubscribe;
     }, []);

     if (!isHydrated) {
       return <LoadingSpinner />;
     }

     return <AppRoutes />;
   };
   ```

5. **Module Federation Store Sharing**:
   ```typescript
   // Expose store through module federation
   // vite.config.ts
   federation({
     name: 'host-app',
     exposes: {
       './store': './src/stores/index.ts',
       './hooks': './src/hooks/index.ts',
     },
     shared: {
       zustand: { singleton: true },
     },
   });

   // In consuming app
   import { useAppStore } from 'host-app/store';
   
   const RemoteComponent = () => {
     const theme = useAppStore((state) => state.theme);
     return <div className={`theme-${theme}`}>Remote content</div>;
   };
   ```

## Testing Strategy

### Component Testing with Vitest and Testing Library

1. **Test Setup**:
   ```typescript
   // vitest.config.ts
   export default defineConfig({
     plugins: [react()],
     test: {
       globals: true,
       environment: 'jsdom',
       setupFiles: ['./src/test/setup.ts'],
     },
   });

   // src/test/setup.ts
   import '@testing-library/jest-dom';
   import { cleanup } from '@testing-library/react';
   import { afterEach } from 'vitest';

   afterEach(() => {
     cleanup();
   });
   ```

2. **Component Test Example**:
   ```typescript
   import { render, screen, fireEvent } from '@testing-library/react';
   import userEvent from '@testing-library/user-event';
   import { Button } from './Button';

   describe('Button', () => {
     it('renders with children', () => {
       render(<Button>Click me</Button>);
       expect(screen.getByRole('button', { name: /click me/i })).toBeInTheDocument();
     });

     it('calls onClick when clicked', async () => {
       const handleClick = vi.fn();
       const user = userEvent.setup();
       
       render(<Button onClick={handleClick}>Click me</Button>);
       
       await user.click(screen.getByRole('button'));
       
       expect(handleClick).toHaveBeenCalledOnce();
     });

     it('is disabled when disabled prop is true', () => {
       render(<Button disabled>Click me</Button>);
       expect(screen.getByRole('button')).toBeDisabled();
     });
   });
   ```

3. **Hook Testing**:
   ```typescript
   import { renderHook, act } from '@testing-library/react';
   import { useCounter } from './useCounter';

   describe('useCounter', () => {
     it('initializes with default value', () => {
       const { result } = renderHook(() => useCounter());
       expect(result.current.count).toBe(0);
     });

     it('increments count', () => {
       const { result } = renderHook(() => useCounter());
       
       act(() => {
         result.current.increment();
       });
       
       expect(result.current.count).toBe(1);
     });
   });
   ```

### Integration Testing

1. **Mock Service Workers for API Testing**:
   ```typescript
   // mocks/handlers.ts
   export const handlers = [
     http.get('/api/users', () => {
       return HttpResponse.json([
         { id: 1, name: 'John Doe', email: 'john@example.com' },
       ]);
     }),
   ];

   // Test with MSW
   it('displays users from API', async () => {
     render(<UserList />);
     
     expect(screen.getByText(/loading/i)).toBeInTheDocument();
     
     await waitFor(() => {
       expect(screen.getByText('John Doe')).toBeInTheDocument();
     });
   });
   ```

## Performance Optimization

### React Optimization Patterns

1. **Memoization**:
   ```typescript
   // Memoize expensive computations
   const ExpensiveComponent: React.FC<{ data: ComplexData[] }> = ({ data }) => {
     const processedData = useMemo(() => {
       return data.filter(item => item.active).sort((a, b) => a.priority - b.priority);
     }, [data]);

     return <DataList items={processedData} />;
   };

   // Memoize callbacks
   const UserList: React.FC<{ users: User[] }> = ({ users }) => {
     const handleUserClick = useCallback((user: User) => {
       navigate(`/users/${user.id}`);
     }, [navigate]);

     return (
       <>
         {users.map(user => (
           <UserCard key={user.id} user={user} onClick={handleUserClick} />
         ))}
       </>
     );
   };
   ```

2. **Component Splitting**:
   ```typescript
   // Lazy load components
   const AdminPanel = lazy(() => import('./AdminPanel'));
   const UserDashboard = lazy(() => import('./UserDashboard'));

   const App: React.FC = () => {
     return (
       <Suspense fallback={<LoadingSpinner />}>
         <Routes>
           <Route path="/admin" element={<AdminPanel />} />
           <Route path="/dashboard" element={<UserDashboard />} />
         </Routes>
       </Suspense>
     );
   };
   ```

3. **Virtual Scrolling for Large Lists**:
   ```typescript
   import { FixedSizeList as List } from 'react-window';

   const VirtualizedList: React.FC<{ items: Item[] }> = ({ items }) => {
     const Row = ({ index, style }: { index: number; style: CSSProperties }) => (
       <div style={style}>
         <ItemComponent item={items[index]} />
       </div>
     );

     return (
       <List
         height={400}
         itemCount={items.length}
         itemSize={60}
         overscanCount={5}
       >
         {Row}
       </List>
     );
   };
   ```

## Security Best Practices

### Input Sanitization

1. **XSS Prevention**:
   ```typescript
   // Never use dangerouslySetInnerHTML without sanitization
   import DOMPurify from 'dompurify';

   const SafeHTML: React.FC<{ html: string }> = ({ html }) => {
     const sanitizedHTML = DOMPurify.sanitize(html);
     return <div dangerouslySetInnerHTML={{ __html: sanitizedHTML }} />;
   };
   ```

2. **Form Validation**:
   ```typescript
   const LoginForm: React.FC = () => {
     const [form, setForm] = useState({ email: '', password: '' });
     const [errors, setErrors] = useState<Record<string, string>>({});

     const validateForm = (): boolean => {
       const newErrors: Record<string, string> = {};
       
       if (!form.email || !isValidEmail(form.email)) {
         newErrors.email = 'Please enter a valid email address';
       }
       
       if (!form.password || form.password.length < 8) {
         newErrors.password = 'Password must be at least 8 characters';
       }

       setErrors(newErrors);
       return Object.keys(newErrors).length === 0;
     };

     const handleSubmit = (e: React.FormEvent) => {
       e.preventDefault();
       if (validateForm()) {
         // Submit form
       }
     };

     return (
       <form onSubmit={handleSubmit}>
         <Input
           type="email"
           value={form.email}
           onChange={(e) => setForm({ ...form, email: e.target.value })}
           error={errors.email}
         />
         <Input
           type="password"
           value={form.password}
           onChange={(e) => setForm({ ...form, password: e.target.value })}
           error={errors.password}
         />
         <button type="submit">Login</button>
       </form>
     );
   };
   ```

### Authentication & Authorization

1. **Protected Routes**:
   ```typescript
   const ProtectedRoute: React.FC<{ 
     children: React.ReactNode;
     requiredRole?: string;
   }> = ({ children, requiredRole }) => {
     const { user, loading } = useAuth();

     if (loading) return <LoadingSpinner />;
     if (!user) return <Navigate to="/login" replace />;
     if (requiredRole && !user.roles.includes(requiredRole)) {
       return <Navigate to="/unauthorized" replace />;
     }

     return <>{children}</>;
   };
   ```

## Styling with Tailwind CSS

### Tailwind Configuration and Setup

1. **Base Tailwind Setup**:
   ```javascript
   // tailwind.config.js
   /** @type {import('tailwindcss').Config} */
   export default {
     content: [
       "./index.html",
       "./src/**/*.{js,ts,jsx,tsx}",
     ],
     darkMode: 'class',
     theme: {
       extend: {
         colors: {
           primary: {
             50: '#eff6ff',
             500: '#3b82f6',
             600: '#2563eb',
             900: '#1e3a8a',
           },
           gray: {
             50: '#f9fafb',
             100: '#f3f4f6',
             900: '#111827',
           }
         },
         fontFamily: {
           sans: ['Inter', 'system-ui', 'sans-serif'],
         },
         spacing: {
           '18': '4.5rem',
           '88': '22rem',
         },
         animation: {
           'fade-in': 'fadeIn 0.5s ease-in-out',
           'slide-up': 'slideUp 0.3s ease-out',
         }
       },
     },
     plugins: [
       require('@tailwindcss/forms'),
       require('@tailwindcss/typography'),
       require('@tailwindcss/aspect-ratio'),
     ],
   }
   ```

2. **Component Styling Patterns**:
   ```typescript
   // Use clsx or cn utility for conditional classes
   import { clsx, type ClassValue } from 'clsx';
   import { twMerge } from 'tailwind-merge';

   export function cn(...inputs: ClassValue[]) {
     return twMerge(clsx(inputs));
   }

   // Button component with Tailwind
   interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
     variant?: 'primary' | 'secondary' | 'danger' | 'ghost';
     size?: 'sm' | 'md' | 'lg';
     isLoading?: boolean;
   }

   const Button: React.FC<ButtonProps> = ({
     variant = 'primary',
     size = 'md',
     isLoading = false,
     className,
     children,
     disabled,
     ...props
   }) => {
     return (
       <button
         className={cn(
           // Base styles
           'inline-flex items-center justify-center rounded-md font-medium transition-colors',
           'focus:outline-none focus:ring-2 focus:ring-offset-2',
           'disabled:pointer-events-none disabled:opacity-50',
           
           // Size variants
           {
             'h-8 px-3 text-sm': size === 'sm',
             'h-10 px-4 text-sm': size === 'md',
             'h-12 px-6 text-base': size === 'lg',
           },
           
           // Color variants
           {
             'bg-primary-600 text-white hover:bg-primary-700 focus:ring-primary-500': variant === 'primary',
             'bg-gray-200 text-gray-900 hover:bg-gray-300 focus:ring-gray-500': variant === 'secondary',
             'bg-red-600 text-white hover:bg-red-700 focus:ring-red-500': variant === 'danger',
             'bg-transparent text-gray-700 hover:bg-gray-100 focus:ring-gray-500': variant === 'ghost',
           },
           
           className
         )}
         disabled={disabled || isLoading}
         {...props}
       >
         {isLoading && (
           <svg className="mr-2 h-4 w-4 animate-spin" viewBox="0 0 24 24">
             <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
             <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
           </svg>
         )}
         {children}
       </button>
     );
   };
   ```

3. **Design System with CSS Variables**:
   ```css
   /* globals.css */
   @tailwind base;
   @tailwind components;
   @tailwind utilities;

   @layer base {
     :root {
       --primary-50: 239 246 255;
       --primary-500: 59 130 246;
       --primary-600: 37 99 235;
       --gray-50: 249 250 251;
       --gray-900: 17 24 39;
       
       --radius: 0.5rem;
       --shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1);
     }

     .dark {
       --gray-50: 17 24 39;
       --gray-900: 249 250 251;
     }

     * {
       @apply border-border;
     }

     body {
       @apply bg-background text-foreground;
     }
   }

   @layer components {
     .card {
       @apply bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700;
     }

     .input {
       @apply block w-full rounded-md border-gray-300 shadow-sm focus:border-primary-500 focus:ring-primary-500;
     }
   }
   ```

4. **Dark Mode Implementation**:
   ```typescript
   // hooks/useDarkMode.ts
   export const useDarkMode = () => {
     const setTheme = useAppStore((state) => state.setTheme);
     const theme = useAppStore((state) => state.theme);

     useEffect(() => {
       if (theme === 'dark') {
         document.documentElement.classList.add('dark');
       } else {
         document.documentElement.classList.remove('dark');
       }
     }, [theme]);

     const toggleTheme = () => {
       setTheme(theme === 'light' ? 'dark' : 'light');
     };

     return { theme, toggleTheme };
   };

   // ThemeToggle component
   const ThemeToggle: React.FC = () => {
     const { theme, toggleTheme } = useDarkMode();

     return (
       <button
         onClick={toggleTheme}
         className="rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-300"
         aria-label="Toggle theme"
       >
         {theme === 'light' ? (
           <MoonIcon className="h-5 w-5" />
         ) : (
           <SunIcon className="h-5 w-5" />
         )}
       </button>
     );
   };
   ```

5. **Responsive Design Patterns**:
   ```typescript
   const ResponsiveCard: React.FC<{ children: React.ReactNode }> = ({ children }) => {
     return (
       <div className={cn(
         'card',
         // Mobile first approach
         'p-4',              // Base: 16px padding
         'sm:p-6',           // Small screens: 24px padding
         'lg:p-8',           // Large screens: 32px padding
         
         // Grid layouts
         'col-span-1',       // Base: 1 column
         'sm:col-span-2',    // Small: 2 columns
         'lg:col-span-3',    // Large: 3 columns
         
         // Flexbox layouts
         'flex flex-col',    // Base: column layout
         'lg:flex-row',      // Large: row layout
       )}>
         {children}
       </div>
     );
   };
   ```

6. **Animation and Transitions**:
   ```typescript
   const AnimatedModal: React.FC<ModalProps> = ({ isOpen, onClose, children }) => {
     return (
       <div className={cn(
         'fixed inset-0 z-50 flex items-center justify-center',
         // Background overlay
         'bg-black/50 backdrop-blur-sm',
         // Animation
         'transition-all duration-300 ease-out',
         isOpen ? 'opacity-100 scale-100' : 'opacity-0 scale-95 pointer-events-none'
       )}>
         <div className={cn(
           'card max-w-lg w-full mx-4',
           // Entrance animation
           'transform transition-all duration-300 ease-out',
           isOpen ? 'translate-y-0 opacity-100' : 'translate-y-4 opacity-0'
         )}>
           {children}
         </div>
       </div>
     );
   };
   ```

### CSS Organization Best Practices

1. **Component-Scoped Styles**:
   - Use Tailwind utilities for most styling
   - Create reusable component variants with `cn()` utility
   - Use `@layer components` for complex component patterns
   - Keep custom CSS minimal and purposeful

2. **Tailwind Plugin Extensions**:
   ```javascript
   // Custom plugin for common patterns
   const plugin = require('tailwindcss/plugin');

   module.exports = plugin(function({ addComponents, theme }) {
     addComponents({
       '.btn': {
         padding: theme('spacing.2') + ' ' + theme('spacing.4'),
         borderRadius: theme('borderRadius.md'),
         fontWeight: theme('fontWeight.medium'),
         transition: theme('transitionProperty.colors'),
       },
       '.card-gradient': {
         background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
       }
     });
   });
   ```

## Error Handling

### Error Boundaries

```typescript
interface ErrorBoundaryState {
  hasError: boolean;
  error?: Error;
  errorInfo?: ErrorInfo;
}

export class ErrorBoundary extends Component<
  { children: ReactNode; fallback?: ReactNode },
  ErrorBoundaryState
> {
  constructor(props: { children: ReactNode; fallback?: ReactNode }) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('Error caught by boundary:', error, errorInfo);
    // Log to error reporting service
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || <div>Something went wrong.</div>;
    }

    return this.props.children;
  }
}
```

## Accessibility (A11Y)

### Semantic HTML and ARIA

```typescript
const Modal: React.FC<{
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
}> = ({ isOpen, onClose, title, children }) => {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (isOpen) {
      dialog?.showModal();
    } else {
      dialog?.close();
    }
  }, [isOpen]);

  return (
    <dialog
      ref={dialogRef}
      aria-labelledby="modal-title"
      onCancel={onClose}
    >
      <div className="modal-content">
        <header>
          <h2 id="modal-title">{title}</h2>
          <button 
            onClick={onClose}
            aria-label="Close modal"
          >
            ×
          </button>
        </header>
        <main>{children}</main>
      </div>
    </dialog>
  );
};
```

## Code Quality and Linting

### ESLint Configuration for React

```javascript
// .eslintrc.js
module.exports = {
  extends: [
    'eslint:recommended',
    '@typescript-eslint/recommended',
    'plugin:react/recommended',
    'plugin:react-hooks/recommended',
    'plugin:jsx-a11y/recommended',
  ],
  plugins: [
    'react',
    'react-hooks',
    'jsx-a11y',
  ],
  rules: {
    'react/prop-types': 'off', // Using TypeScript instead
    'react/react-in-jsx-scope': 'off', // React 17+ JSX transform
    'react/jsx-uses-react': 'off',
    'react-hooks/rules-of-hooks': 'error',
    'react-hooks/exhaustive-deps': 'warn',
    'jsx-a11y/no-autofocus': 'off',
    'jsx-a11y/anchor-is-valid': [
      'error',
      {
        components: ['Link'],
        specialLink: ['hrefLeft', 'hrefRight'],
        aspects: ['invalidHref', 'preferButton'],
      },
    ],
  },
  settings: {
    react: {
      version: 'detect',
    },
  },
};
```

## Build and Deployment

### Production Build Optimization

```typescript
// vite.config.ts - Production optimizations
export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          'react-vendor': ['react', 'react-dom'],
          'ui-vendor': ['@headlessui/react', 'framer-motion'],
        },
      },
    },
  },
  esbuild: {
    drop: ['console', 'debugger'], // Remove in production
  },
});
```

### Environment Configuration

```typescript
// src/config/env.ts
interface AppConfig {
  apiUrl: string;
  environment: 'development' | 'staging' | 'production';
  enableAnalytics: boolean;
}

export const config: AppConfig = {
  apiUrl: import.meta.env.VITE_API_URL || 'http://localhost:3001',
  environment: import.meta.env.VITE_ENVIRONMENT || 'development',
  enableAnalytics: import.meta.env.VITE_ENABLE_ANALYTICS === 'true',
};
```

## Module Federation Specific Rules

### Component Versioning and Sharing

1. **Semantic Versioning for Components**:
   ```typescript
   // package.json
   {
     "name": "@company/shared-components",
     "version": "1.2.3",
     "federatedModules": {
       "Button": "./src/components/Button",
       "Modal": "./src/components/Modal"
     }
   }
   ```

2. **Backward Compatibility**:
   - Maintain backward compatibility for exposed components
   - Use deprecation warnings for old props
   - Document breaking changes clearly

3. **Error Boundaries for Remote Modules**:
   ```typescript
   const RemoteModule: React.FC = () => {
     return (
       <ErrorBoundary fallback={<div>Failed to load remote component</div>}>
         <Suspense fallback={<div>Loading...</div>}>
           <RemoteComponent />
         </Suspense>
       </ErrorBoundary>
     );
   };
   ```

### Shared Routing Patterns

1. **Shell App Routing Configuration**:
   ```typescript
   // Shell app - routes/index.tsx
   import { lazy } from 'react';
   import { createBrowserRouter, Navigate } from 'react-router-dom';

   // Lazy load remote applications
   const UserManagementApp = lazy(() => import('user-management/App'));
   const ProductCatalogApp = lazy(() => import('product-catalog/App'));
   const CheckoutApp = lazy(() => import('checkout/App'));

   export const router = createBrowserRouter([
     {
       path: '/',
       element: <RootLayout />,
       errorElement: <ErrorBoundary />,
       children: [
         { 
           index: true, 
           element: <Navigate to="/dashboard" replace /> 
         },
         {
           path: 'dashboard',
           element: <Dashboard />,
         },
         {
           path: 'users/*',
           element: (
             <ErrorBoundary fallback={<AppErrorFallback />}>
               <Suspense fallback={<AppLoadingSpinner />}>
                 <UserManagementApp />
               </Suspense>
             </ErrorBoundary>
           ),
         },
         {
           path: 'products/*',
           element: (
             <ErrorBoundary fallback={<AppErrorFallback />}>
               <Suspense fallback={<AppLoadingSpinner />}>
                 <ProductCatalogApp />
               </Suspense>
             </ErrorBoundary>
           ),
         },
         {
           path: 'checkout/*',
           element: (
             <ErrorBoundary fallback={<AppErrorFallback />}>
               <Suspense fallback={<AppLoadingSpinner />}>
                 <CheckoutApp />
               </Suspense>
             </ErrorBoundary>
           ),
         },
       ],
     },
   ]);
   ```

2. **Remote App Internal Routing**:
   ```typescript
   // Remote app - user-management/src/App.tsx
   import { Routes, Route, useLocation } from 'react-router-dom';

   const UserManagementApp: React.FC = () => {
     const location = useLocation();
     
     // Remove the '/users' prefix from the pathname for internal routing
     const basePath = location.pathname.replace('/users', '') || '/';

     return (
       <div className="user-management-app">
         <Routes>
           <Route index element={<UserList />} />
           <Route path="new" element={<CreateUser />} />
           <Route path=":id" element={<UserDetail />} />
           <Route path=":id/edit" element={<EditUser />} />
           <Route path="*" element={<NotFound />} />
         </Routes>
       </div>
     );
   };

   export default UserManagementApp;
   ```

3. **Navigation Service for Cross-App Navigation**:
   ```typescript
   // shared/navigation/navigationService.ts
   interface NavigationService {
     navigate: (path: string, options?: { replace?: boolean }) => void;
     goBack: () => void;
     getCurrentPath: () => string;
     subscribe: (callback: (path: string) => void) => () => void;
   }

   class BrowserNavigationService implements NavigationService {
     private subscribers: ((path: string) => void)[] = [];

     navigate(path: string, options?: { replace?: boolean }) {
       if (options?.replace) {
         window.history.replaceState({}, '', path);
       } else {
         window.history.pushState({}, '', path);
       }
       this.notifySubscribers(path);
     }

     goBack() {
       window.history.back();
     }

     getCurrentPath(): string {
       return window.location.pathname;
     }

     subscribe(callback: (path: string) => void): () => void {
       this.subscribers.push(callback);
       return () => {
         const index = this.subscribers.indexOf(callback);
         if (index > -1) this.subscribers.splice(index, 1);
       };
     }

     private notifySubscribers(path: string) {
       this.subscribers.forEach(callback => callback(path));
     }
   }

   export const navigationService = new BrowserNavigationService();

   // Hook for using navigation service
   export const useNavigation = () => {
     return {
       navigate: navigationService.navigate.bind(navigationService),
       goBack: navigationService.goBack.bind(navigationService),
       getCurrentPath: navigationService.getCurrentPath.bind(navigationService),
     };
   };
   ```

### Cross-App Communication Patterns

1. **Event Bus for App Communication**:
   ```typescript
   // shared/events/eventBus.ts
   interface AppEvent {
     type: string;
     payload?: any;
     source: string;
     timestamp: number;
   }

   class EventBus {
     private listeners: Map<string, ((event: AppEvent) => void)[]> = new Map();

     emit(type: string, payload?: any, source?: string): void {
       const event: AppEvent = {
         type,
         payload,
         source: source || 'unknown',
         timestamp: Date.now(),
       };

       const typeListeners = this.listeners.get(type) || [];
       const allListeners = this.listeners.get('*') || [];

       [...typeListeners, ...allListeners].forEach(listener => {
         try {
           listener(event);
         } catch (error) {
           console.error('Error in event listener:', error);
         }
       });
     }

     on(type: string, listener: (event: AppEvent) => void): () => void {
       if (!this.listeners.has(type)) {
         this.listeners.set(type, []);
       }
       this.listeners.get(type)!.push(listener);

       return () => {
         const listeners = this.listeners.get(type) || [];
         const index = listeners.indexOf(listener);
         if (index > -1) listeners.splice(index, 1);
       };
     }

     off(type: string, listener: (event: AppEvent) => void): void {
       const listeners = this.listeners.get(type) || [];
       const index = listeners.indexOf(listener);
       if (index > -1) listeners.splice(index, 1);
     }

     clear(): void {
       this.listeners.clear();
     }
   }

   export const eventBus = new EventBus();

   // React hook for using event bus
   export const useEventBus = () => {
     const emit = (type: string, payload?: any) => {
       eventBus.emit(type, payload, 'react-hook');
     };

     const useEventListener = (type: string, handler: (event: AppEvent) => void) => {
       useEffect(() => {
         const unsubscribe = eventBus.on(type, handler);
         return unsubscribe;
       }, [type, handler]);
     };

     return { emit, useEventListener };
   };
   ```

2. **Inter-App Communication Examples**:
   ```typescript
   // User management app - notify when user is updated
   const EditUser: React.FC = () => {
     const { emit } = useEventBus();
     
     const handleUserUpdate = async (user: User) => {
       await updateUser(user);
       
       // Notify other apps about the user update
       emit('user:updated', { user, updatedBy: 'user-management' });
     };

     return <UserForm onSubmit={handleUserUpdate} />;
   };

   // Product catalog app - listen for user updates
   const ProductList: React.FC = () => {
     const [products, setProducts] = useState<Product[]>([]);
     const { useEventListener } = useEventBus();

     // Listen for user updates to refresh product ownership
     useEventListener('user:updated', (event) => {
       const { user } = event.payload;
       // Refresh products if they're owned by the updated user
       if (products.some(p => p.ownerId === user.id)) {
         refetchProducts();
       }
     });

     return <div>{/* Product list */}</div>;
   };
   ```

3. **Shared State Management Between Apps**:
   ```typescript
   // Global store that can be shared across micro-frontends
   interface GlobalState {
     currentUser: User | null;
     theme: 'light' | 'dark';
     notifications: Notification[];
     shoppingCart: CartItem[];
   }

   interface GlobalActions {
     setCurrentUser: (user: User | null) => void;
     setTheme: (theme: 'light' | 'dark') => void;
     addNotification: (notification: Omit<Notification, 'id'>) => void;
     addToCart: (item: CartItem) => void;
     removeFromCart: (itemId: string) => void;
   }

   // Create a global store that persists across app boundaries
   export const useGlobalStore = create<GlobalState & GlobalActions>()(
     subscribeWithSelector(
       persist(
         immer((set, get) => ({
           // State
           currentUser: null,
           theme: 'light',
           notifications: [],
           shoppingCart: [],

           // Actions
           setCurrentUser: (user) => set({ currentUser: user }),
           setTheme: (theme) => set({ theme }),
           addNotification: (notification) => set((state) => {
             state.notifications.push({
               ...notification,
               id: crypto.randomUUID(),
               createdAt: new Date(),
             });
           }),
           addToCart: (item) => set((state) => {
             const existingItem = state.shoppingCart.find(i => i.productId === item.productId);
             if (existingItem) {
               existingItem.quantity += item.quantity;
             } else {
               state.shoppingCart.push(item);
             }
           }),
           removeFromCart: (itemId) => set((state) => {
             state.shoppingCart = state.shoppingCart.filter(item => item.id !== itemId);
           }),
         })),
         {
           name: 'global-app-state',
           partialize: (state) => ({
             currentUser: state.currentUser,
             theme: state.theme,
             shoppingCart: state.shoppingCart,
           }),
         }
       )
     )
   );

   // Sync store changes with event bus
   export const syncStoreWithEvents = () => {
     const store = useGlobalStore.getState();
     
     // Emit events when store changes
     useGlobalStore.subscribe(
       (state) => state.currentUser,
       (user, previousUser) => {
         if (user !== previousUser) {
           eventBus.emit('global:user-changed', { user, previousUser });
         }
       }
     );

     useGlobalStore.subscribe(
       (state) => state.theme,
       (theme, previousTheme) => {
         if (theme !== previousTheme) {
           eventBus.emit('global:theme-changed', { theme, previousTheme });
         }
       }
     );
   };
   ```

### Dependency and Version Management

1. **Shared Dependencies Configuration**:
   ```typescript
   // vite.config.ts - Host app
   federation({
     name: 'shell-app',
     remotes: {
       'user-management': 'http://localhost:3001/assets/remoteEntry.js',
       'product-catalog': 'http://localhost:3002/assets/remoteEntry.js',
       'checkout': 'http://localhost:3003/assets/remoteEntry.js',
     },
     shared: {
       // Critical: ensure single instances of these
       react: { singleton: true, requiredVersion: '^18.0.0' },
       'react-dom': { singleton: true, requiredVersion: '^18.0.0' },
       'react-router-dom': { singleton: true, requiredVersion: '^6.0.0' },
       zustand: { singleton: true, requiredVersion: '^4.0.0' },
       
       // Shared utilities and design system
       '@company/design-system': { singleton: true },
       '@company/shared-utils': { singleton: true },
       
       // Styling
       tailwindcss: { singleton: true },
       
       // Optional shared libraries
       'date-fns': { requiredVersion: '^2.0.0' },
       axios: { requiredVersion: '^1.0.0' },
     },
   })

   // vite.config.ts - Remote app
   federation({
     name: 'user-management',
     filename: 'remoteEntry.js',
     exposes: {
       './App': './src/App.tsx',
       './UserList': './src/components/UserList.tsx',
       './UserDetail': './src/components/UserDetail.tsx',
     },
     shared: {
       react: { singleton: true },
       'react-dom': { singleton: true },
       'react-router-dom': { singleton: true },
       zustand: { singleton: true },
       '@company/design-system': { singleton: true },
       '@company/shared-utils': { singleton: true },
     },
   })
   ```

2. **Type Safety Across Federated Modules**:
   ```typescript
   // types/federation.d.ts
   declare module 'user-management/App' {
     const UserManagementApp: React.ComponentType;
     export default UserManagementApp;
   }

   declare module 'user-management/UserList' {
     interface UserListProps {
       onUserSelect?: (user: User) => void;
       filters?: UserFilters;
     }
     const UserList: React.ComponentType<UserListProps>;
     export default UserList;
   }

   declare module 'product-catalog/App' {
     const ProductCatalogApp: React.ComponentType;
     export default ProductCatalogApp;
   }

   // Shared types package
   // @company/shared-types/src/index.ts
   export interface User {
     id: string;
     email: string;
     name: string;
     role: UserRole;
     createdAt: Date;
     updatedAt: Date;
   }

   export interface Product {
     id: string;
     name: string;
     price: number;
     category: string;
     ownerId: string;
   }

   export interface AppEvent {
     type: string;
     payload?: any;
     source: string;
     timestamp: number;
   }
   ```

## Recommended Tools and Libraries

| Category | Tool | Purpose |
|----------|------|---------|
| Build | Vite | Fast development and building |
| Module Federation | @originjs/vite-plugin-federation | Micro-frontend architecture |
| Testing | Vitest + Testing Library | Unit and integration testing |
| State Management | Zustand | Global state management |
| Styling | Tailwind CSS | Utility-first CSS framework |
| CSS Utilities | clsx + tailwind-merge | Conditional class management |
| Forms | React Hook Form | Form handling and validation |
| Animation | Framer Motion | Animations and transitions |
| UI Components | Headless UI / Radix UI | Accessible component primitives |
| Icons | Lucide React / Heroicons | Icon libraries |
| Routing | React Router | Client-side routing |
| API | TanStack Query | Server state management |
| Dev Tools | React DevTools | Development debugging |
| Type Safety | TypeScript | Static type checking |
| Linting | ESLint + React plugins | Code quality enforcement |
| Formatting | Prettier | Code formatting |
| Testing Mocks | MSW | API mocking for testing |

This ruleset should be followed in conjunction with the existing TypeScript rules for maximum effectiveness.