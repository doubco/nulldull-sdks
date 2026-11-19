# Changelog

All NullDull SDKs share one version. This project follows [Semantic Versioning](https://semver.org); `0.x` releases may contain breaking changes in minor versions.

## 0.1.0 (unreleased, early access)

- `SPEC.md`: the language-neutral contract for workspace API key SDKs. It covers Grid delivery, read-only Memory and Locale export, and defines errors, retries, pagination and conformance.
- `fixtures/`: shared conformance cases (`manifest.json`) and response fixtures taken from the API handlers.
- `node/`: `@nulldull/sdk`, the reference Node.js and TypeScript SDK (ESM and CJS, zero runtime dependencies, Node 18+ and browsers).
