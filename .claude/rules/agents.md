# Agent Orchestration Rules

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| Explore (`model: haiku`) | Codebase exploration | Finding files across this gem, or how a CONSUMING gem (`~/Code/zoolutions/<gem>`) uses the kit |
| Plan (`model: sonnet`) | Implementation planning | A change spanning the checks, both front ends and the audit |
| general-purpose | Multi-step research | Ruby/Ractor semantics, rubocop-thread_safety or rubocop_spinel internals |
| fable-validator | Final validation | Before every PR (`/lfg` Phase 6.5) |

- Run independent explorations in parallel.
- Verify Ruby/Ractor behaviour by running it on the right Ruby (`~/.rubies/ruby-4.0.6`, `ruby-3.4.x`, `ruby-3.2.8`), never from memory: Ractor rules changed in 4.0.
- When a change affects consumers, check the nine consuming gems' usage (`~/Code/zoolutions/{daisyui,pgbus,phlex-reactive,locallingo,phlex-forms,docs-kit,glyphs,stationery,importmap-plus}`) before changing a public API.
