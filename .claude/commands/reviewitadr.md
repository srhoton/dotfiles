Ok. Please have the adr-compliance-reviewer agent analyze this repository for compliance with Fullbay's accepted ADRs (Architecture Decision Records). The agent should check:

1. **ADR-001: Prefixed Base62 Entity Identifiers** - Verify entity IDs follow `{prefix}_{base62id}` format, use SecureRandom, and implement DynamoDB conditional writes
2. **ADR-002: Backend For Frontend** - Verify BFF uses AWS AppSync with TypeScript Lambda resolvers and Terraform infrastructure
3. **ADR-003: Frontend Framework** - Verify frontend uses React with Vite bundler and functional components only
4. **ADR-004: Micro Frontend** - Verify micro frontend architecture uses Module Federation (not Single-SPA)
5. **ADR-005: State Management** - Verify state management uses React Hooks for local state and Zustand for global state (not Redux)

Generate a detailed compliance report with specific file:line references for any violations found.
