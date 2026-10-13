# conformance-kit

Concurrency conformance for the zoolutions gems. A gem that adopts it is held to explicit tiers, each with a mechanical gate:

| Tier | Meaning | Gate |
|---|---|---|
| 1 thread-safe | no unguarded shared mutable state on the request/broadcast path | `rubocop-thread_safety` + the thread-contention shared example |
| 2 fiber-safe | correct under a fiber scheduler (Falcon/Async) | the Async-reactor shared example |
| 3 Ractor-clean | the gem adds no Ractor blocker beyond its dependencies' | `conformance-audit` + the Ruby 4.0 Ractor canary |
| 4 compiler-probed | Spinel/Roundhouse readiness is measured, never gated | report-only probe workflow |

Work in progress: see the tracking issue. Background: zoolutions/phlex-reactive#363.
