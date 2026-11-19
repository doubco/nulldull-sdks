# Shared fixtures

Conformance data reused by every SDK's test suite. See [SPEC.md, section 11](../SPEC.md#11-conformance) for the format.

- `manifest.json`: the cases. Each case gives the client config, the canonical call, the exact HTTP requests expected with canned responses, and the expected result or error.
- `grid/`, `memory/`, `locale/`: response bodies, shaped exactly like the API handlers' output. Locale exports were produced by the real codecs.
- `errors/`: error bodies (`{code, message?, detail?, ...}`).

The keys and IDs are fake. Never put real keys here.
