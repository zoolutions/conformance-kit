# conformance-kit

Shared concurrency conformance for the zoolutions gems (zoolutions/phlex-reactive#363: tiers, finalize-at-boot pattern, settled decisions; first work item #1).
Claude's workflow comes from the `flow` and `ruby-gem` plugins (`.claude/settings.json`), which act on the facts in `## Workflow` below.

- Ruby floor 3.2. Ractor-only behaviour is gated on the running Ruby (`Ractor.store_if_absent` and `Ractor.main?` 3.4+, `Ractor#value` and `Ractor.shareable_proc` 4.0+; `#take` before 4.0). TruffleRuby and JRuby have no `Ractor`. Never raise the floor for it.
- Development dependency only: nothing here may become a runtime dependency of a consuming gem. `async`, `concurrent-ruby`, `minitest`, `rubocop_spinel` are optional: `require` inside `rescue LoadError`, skip with a stated reason.
- `bin/release`, `rakelib/release.rake`, `release.yml`'s shared jobs, `bin/labels` and `.github/LABELS.md` are the zoolutions release and labels kits (canonical copy in docs-kit, `script/labels-kit sync`): never edit them here, byte-identical across the gems. Never `gem push` by hand.
- Labels are edited in `.github/labels.yml` and applied with `bin/labels sync`, never in the GitHub UI.

## Commands

```bash
bundle exec rspec              # Full suite (Ractor examples run on Ruby 4.0, skip with a reason below)
bundle exec rubocop            # Lint
bundle exec rake               # rspec + rubocop
bin/labels infer <paths>       # Area labels for a set of changed paths
bin/release [patch|minor|major|X.Y.Z] [-n]   # Cut a release
```

## Code rules

- One concern per file: a check (`lib/conformance_kit/checks/*`), a front end (`rspec.rb`, `minitest.rb`), the store, the audit. Checks are plain Ruby with no RSpec/Minitest dependency; the front ends only adapt them.
- The kit obeys the tiers it enforces: per-Ractor lazy state through `Store.fetch(:key) { ... }`, never `CACHE = {}` or `@cache ||= {}`; no class/module ivar written after load except through `Store`.
- Gate on a capability, never a version string: `defined?(::Ractor) && ::Ractor.respond_to?(:store_if_absent)`, not `RUBY_VERSION >= "3.4"`. Before 4.0 a non-main Ractor cannot autoload: whatever a Ractor example runs must already be loaded.
- A failing check names the culprit: which reader, constant or ivar, and the class of the offending value.
- Public surface is stable (shared-example names, options, `conformance-audit` flags and exit codes, workflow inputs); nine gems use it: `~/Code/zoolutions/{daisyui,pgbus,phlex-reactive,locallingo,phlex-forms,docs-kit,glyphs,stationery,importmap-plus}`. Check their usage before changing it.
- Runs in consumers' test suites and CI, never production. Thread and fiber examples default to small bounded workloads (never loop until a race appears); `conformance-audit` walks `ObjectSpace` once, so per-object work stays O(1) and objects outside the namespace are skipped early. No speedup claim without a same-machine before/after.

## Testing

- TDD: the failing spec first, watched failing for the right reason.
- Every shared example and audit rule ships a violating fixture the check MUST catch and a conforming one it MUST pass (`spec/fixtures/`). Assert the failure in an `RSpec::Core::Sandbox` (or `Minitest::Runnable` with a captured reporter). A check never seen failing is untested.
- Force races, never hope: a `Thread.pass` or `Queue` handshake at the race window of the violating fixture. No timing assertions, no `sleep`.
- Ractor specs: tag `:ractor`, skip with a reason when `Ractor#value` is missing (below 4.0); never pass silently. Cover the Store fallback (no `store_if_absent`) on 3.4 by stubbing the capability check.
- Verify Ruby/Ractor behaviour by running it on the right Ruby (`~/.rubies/ruby-{3.2.8,4.0.6}`, a 3.4.x), never from memory. A Ractor-touching change also runs, before the PR:

```bash
PATH=$HOME/.rubies/ruby-4.0.6/bin:$PATH GEM_HOME=$HOME/.gem/ruby/4.0.6 GEM_PATH=$HOME/.gem/ruby/4.0.6:$HOME/.rubies/ruby-4.0.6/lib/ruby/gems/4.0.0 bundle exec rspec
PATH=$HOME/.rubies/ruby-3.2.8/bin:$PATH GEM_HOME=$HOME/.gem/ruby/3.2.8 GEM_PATH=$HOME/.gem/ruby/3.2.8:$HOME/.rubies/ruby-3.2.8/lib/ruby/gems/3.2.0 bundle exec rspec
```

A failure on only one Ruby is usually a capability gap, not a flaky test.

## Review focus

New check: a violating fixture proves it fails. `exe/conformance-audit`: exit codes and allowlist handling are a public contract. `.github/workflows/conformance.yml`: reusable workflow, every adopting gem calls it at a release tag. Commit scopes: `examples`, `store`, `audit`, `config`, `ci`.

## Workflow

- **Verify:** `bundle exec rubocop` · `bundle exec rspec` (or `bundle exec rake`); Ractor change: also the 4.0 and 3.2 runs (Testing)
- **Specs:** fast loop `bundle exec rspec <file>`; full suite `bundle exec rspec`; two worktrees at once: yes
- **CI:** required `Ruby 3.2`, `Ruby 3.4`, `Ruby 4.0`, `RuboCop`, `conformance / Conformance settings`, `conformance / Conformance (Ruby 4.0)`, `cubic · AI code reviewer`, plus 1 approving review; full suite on the PR; failure report none
- **Review bot:** cubic
- **Merge:** squash — `gh pr merge <PR> --squash --delete-branch`
- **PR contract:** `## Summary`, `## Test plan`; labels in the `gh pr create` call: one `type` + at least one `area` from `.github/labels.yml` (`bin/labels infer <paths>`), never `status`
- **Conflicts:** `CHANGELOG.md` — both sides' entries, newest on top, none lost; `lib/conformance_kit/version.rb` — main's unless the branch is a release-prep PR (then its bump); `Gemfile.lock` is untracked, drop it; release and labels kits (`bin/release`, `rakelib/release.rake`, `release.yml` shared jobs, `bin/labels`, `.github/LABELS.md`) — main's copy
- **Worktree setup:** `bundle install`; undo none
- **Release:** `bin/release <v>`; changelog `CHANGELOG.md`, heading `## X.Y.Z - YYYY-MM-DD`, no `[Unreleased]` (written in the feature PR); prep, lockfiles, docs, human none
- **Main health:** `gh run list --workflow main.yml --branch main --event push --limit 1 --json conclusion,headSha`
- **Upstream:** libraries we own `zoolutions/*`; scrub none
- **Bench:** none

## Agent commands

Plugins: `/flow:lfg`, `/flow:plan`, `/flow:follow-through`, `/flow:finish-prs`, `/flow:github-review-pr` (`-failures`, `-comments`), `/flow:review-pr`, `/flow:tdd`, `/flow:debug-flaky`, the `flow:fable-validator` agent; `/ruby-gem:release`, `/ruby-gem:perf`. No local commands.

**Models.** Sessions run on `opus` with `fable` as the advisor (`.claude/settings.json`). Every spawned agent names its `model:`; one that does not runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL`).
