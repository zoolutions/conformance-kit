# Performance Rules

conformance-kit runs in consumers' test suites and CI, never in production, so speed matters only where it slows a suite.

- The thread and fiber examples default to small, bounded workloads (threads × iterations configurable). Never loop until a race appears.
- `conformance-audit` walks `ObjectSpace` once per run: keep per-object work O(1) and skip objects outside the requested namespace early.
- Don't claim a speedup without a before/after measured on the same machine.
