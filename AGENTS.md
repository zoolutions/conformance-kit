# conformance-kit

Shared concurrency conformance for the zoolutions gems (zoolutions/phlex-reactive#363).

- Ruby floor 3.2. Ractor-only behaviour is gated on the running Ruby (`Ractor.store_if_absent` 3.4+, `Ractor#value` 4.0+); never raise the floor for it.
- Development dependency only: nothing here may become a runtime dependency of a consuming gem.
- TDD: write the failing spec first. `bundle exec rspec` and `bundle exec rubocop` must pass.
- `bin/release`, `rakelib/release.rake`, `release.yml`'s shared jobs, `bin/labels` and `.github/LABELS.md` are the zoolutions release and labels kits (canonical copy in docs-kit): never edit them here.
- Every PR carries one `type` label and at least one `area` label from `.github/labels.yml` (`bin/labels infer <paths>`).

## Commands

```bash
bundle exec rspec              # Full suite (Ractor examples run on Ruby 4.0, skip with a reason below)
bundle exec rubocop            # Lint
bundle exec rake               # rspec + rubocop
bin/labels infer <paths>       # Area labels for a set of changed paths
bin/release [patch|minor|major|X.Y.Z] [-n]   # Cut a release
```

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/plan` | Fable-powered planning → GitHub issue or `docs/plans/` markdown (read-only; execute with `/lfg`) |
| `/lfg` | Full autonomous workflow: branch → understand → explore → plan → TDD → verify → PR |
| `/tdd` | Enforce RED → GREEN → REFACTOR |
| `/review-pr` | Review a PR for pattern compliance |
| `/github-review-pr` | Full PR pass: conflicts, then CI failures, then review comments (in that order) |
| `/github-review-failures` | Fix failing CI checks until green |
| `/github-review-comments` | Process unresolved PR review comments |

**Models.** Sessions run on `opus` with `fable` as the advisor (`.claude/settings.json`). `/plan` runs on Fable, and the `fable-validator` agent checks every finished implementation before its PR opens (`/lfg`, Phase 6.5). Commands pin their tier by alias, never by full model ID. Every spawned agent names its `model:`; one that doesn't runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL`).

## More

- `.claude/rules/` — coding style, testing, performance, git workflow, agents
- `.claude/README.md` — how to author a command
- The epic: zoolutions/phlex-reactive#363 (tiers, finalize-at-boot pattern, settled decisions)
- The first work item: #1
