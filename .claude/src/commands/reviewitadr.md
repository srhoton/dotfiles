Ok. Please have the adr-compliance-reviewer agent analyze this repository for compliance with Fullbay's accepted ADRs (Architecture Decision Records) from the `fb-architecture/architecture-decisions` repository. The agent should check these five accepted ADRs:

1. **Prefixed Base62 Entity Identifiers** - Verify entity IDs follow `{prefix}_{base62id}` format (e.g., `inv_a4B9k2Xp7Q`), use SecureRandom, and implement DynamoDB conditional writes
2. **Backend For Frontend** - Verify BFF uses AWS AppSync with TypeScript Lambda resolvers and Terraform infrastructure
3. **Frontend Framework** - Verify frontend uses React with Vite bundler (not Webpack or RSPack)
4. **Micro Frontend** - Verify micro frontend architecture uses Module Federation (not Single-SPA)
5. **State Management** - Verify state management uses React Hooks for local state and Zustand for global state (not Redux, Recoil, or MobX)

Note: The Event-Driven Architecture Patterns ADR is still in "Proposed" status and should NOT be enforced yet.

Generate a detailed compliance report with specific file:line references for any violations found.
