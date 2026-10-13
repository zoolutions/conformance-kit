---
model: fable
description: "Investigates the codebase, designs a solution, and produces a durable plan artifact — a GitHub issue or a plan markdown under docs/plans/. Read-only: never edits library or app code. Use before /lfg for anything non-trivial."
argument-hint: "issue <feature or problem> | md <feature or problem> | <feature or problem>"
allowed-tools: Bash(gh issue create:*), Bash(gh issue edit:*), Bash(bin/labels infer:*), Bash(bin/labels sync), Bash(bin/labels sync --dry-run), Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh search:*), Bash(gh label list:*), Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(date:*), Read, Grep, Glob, Write, Agent, AskUserQuestion
---

# Plan — design expensive, execute cheap

You are the planning specialist. This command runs on the most capable model deliberately: the thinking happens here, the execution happens later on cheaper models (`/lfg` and `/tdd` on Opus, the CI and review-comment passes on Sonnet). That split only works if the plan is **self-contained** — an executor with none of this session's context must be able to implement it without guessing.

## Output mode from $ARGUMENTS

| $ARGUMENTS starts with | Artifact |
|------------------------|----------|
| `issue` | GitHub issue (default — feeds directly into `/lfg <issue-number>`) |
| `md` or `file` | Markdown file at `docs/plans/YYYY-MM-DD-<slug>.md` (date from `date +%F`) |
| anything else | GitHub issue |

## Hard constraints

- **Read-only for source code.** Never edit library (`lib/`, `exe/`, `config/`) or spec code, never commit, never create branches. The only file you may Write is a new plan markdown under `docs/plans/`.
- **Never reproduce secrets** (keys, tokens, credentials, the `MessageVerifier` secret) in the plan, even redacted ones you encounter while reading config.
- **Dedupe before creating an issue**: `gh issue list --search "<keywords>"` — if an existing issue covers this, extend it in your summary instead of duplicating.

## Phase 1 — Investigate

Protect this session's context: delegate mechanical exploration to cheaper subagents and keep Fable for judgment.

1. Fan out Explore agents (`subagent_type: Explore`, `model: haiku`) for file discovery and naming-convention sweeps across the gem (`lib/`, `exe/`, `config/`, `spec/`). Launch independent explorations in parallel. If the change affects consumers, point one at the consuming gems (`~/Code/zoolutions/<gem>`, listed in `.claude/rules/agents.md`) to see how they use the kit today.
2. Read the load-bearing files yourself — the ones the design decision actually hinges on. Don't design from subagent summaries alone. The parts: `lib/conformance_kit.rb`, `lib/conformance_kit/checks/`, the front ends (`rspec.rb`, `minitest.rb`), `lib/conformance_kit/store.rb`, `exe/conformance-audit`, `config/`, `.github/workflows/{ractor,probes}.yml`. Verify Ruby/Ractor behaviour by running it (`~/.rubies/ruby-{3.2.8,3.4.x,4.0.6}`), never from memory.
3. Read `AGENTS.md` and the matching `.claude/rules/*.md` (coding-style, testing, performance, git-workflow, agents) — the invariants and gotchas live there. The epic (zoolutions/phlex-reactive#363) holds the tiers and the settled decisions.
4. Check `git log` for recent related work; the design should extend it, not fight it.

## Phase 2 — Surface the unknowns (blindspot pass + interview)

Investigation tells you what the codebase says; this phase finds what the REQUEST doesn't say. Run it BEFORE designing — a wrong assumption caught here costs one question; caught in review it costs a rewrite.

1. **Blindspot pass.** Write down the unknowns you are carrying into the design:
   - decisions the request leaves open (defaults, naming, public API/config surface, rollout & upgrade story)
   - edge cases the codebase makes possible that the request never mentions
   - anything with no precedent in this repo — flag it explicitly as unknown-unknown territory
2. **Interview the user** with AskUserQuestion, one question at a time, prioritized by blast radius: architecture-changing answers first, then public API / config surface, then UX. Rules:
   - Skip anything the codebase, AGENTS.md, or an existing issue already answers.
   - 2–5 questions is the sweet spot; zero is fine when the request is genuinely unambiguous — say so rather than inventing questions.
   - Every question offers concrete options with a recommended default, never an open-ended essay prompt.
3. **Record the answers** in the plan's Decision section as `Settled in interview:` bullets — constraints the executor must not re-litigate.

## Phase 3 — Design

- Develop 2–3 candidate approaches with real tradeoffs. Pick one and say why; record why the others lost.
- The chosen design must respect the project invariants (see AGENTS.md):
  - **Development dependency only** — nothing becomes a runtime dependency of a consuming gem; optional libraries load lazily and skip with a stated reason.
  - **Gate on the running Ruby, never the floor** — capability checks, never version strings; Ruby 3.2 and no-Ractor engines stay supported.
  - **Every check is proven both ways** — a violating fixture it catches and a conforming one it passes.
  - **Public surface is stable** — shared-example names, options, `conformance-audit` flags and exit codes, and workflow inputs are used by nine gems.
- Decide the test strategy per `.claude/rules/testing.md`: unit specs per check, sandboxed example-group specs for the front ends, executable specs for `conformance-audit`. Specs are named before the implementation steps they cover (TDD), each with its violating and conforming fixture.

## Phase 4 — Emit the plan artifact

Use this structure for the issue body or markdown file. Every section is load-bearing — an executor uses Context to avoid re-discovery, Steps to act, Gates to verify, Boundaries to stop.

```markdown
# <Title>

## Problem / Goal
<What's wrong or missing, who it affects, what done looks like.>

## Context (read these first)
<Bullet list: `path/to/file.rb` — why it matters to this change. Include the checks, front ends, fixtures and specs involved, and any consuming gem the change affects. Self-contained: no references to "as discussed" or this session.>

## Decision
<Chosen approach and rationale. Then: alternatives considered and why each was rejected. Call out the behaviour on each Ruby (3.2 / 3.4 / 4.0, no-Ractor engines) explicitly. End with `Settled in interview:` bullets for every constraint the user confirmed in Phase 2 — the executor must not re-litigate these.>

## Implementation steps
<Ordered, small, each mapped to a specialist where useful (/tdd, /architect, /perf). Specs come before the code they cover. Name exact files to create or change.>

## Verification gates
<Exact commands + expected outcome:>
- `bundle exec rspec` — all green (and on Ruby 4.0 + 3.2 for Ractor-touching changes)
- `bundle exec rubocop` — no offenses

## Out of scope
<Explicit boundaries — the adjacent things an eager executor must NOT do. E.g. "do not add a runtime dependency", "do not rename a shared example consumers use".>

## Execution
Execute with `/lfg <issue-number>` (or `/lfg docs/plans/<file>.md`).
```

For GitHub issues: create with `gh issue create --title "..." --body "$(cat <<'EOF' ... EOF)"` — single-quoted heredoc delimiter, backticks unescaped (see `.claude/rules/git-workflow.md`).

### Label the issue

Every `/plan` issue is labelled — `/lfg` copies its `type` and `area` labels onto the pull request, so getting them right here is what labels the PR. The taxonomy is `.github/labels.yml`; `.github/LABELS.md` explains the groups.

1. **`plan`** — always.
2. **One type label** — `enhancement` by default; `bug` for a defect, `performance` for a speed-up, `tech-debt` for cleanup, `security` for a vulnerability or hardening, `chore` for CI/tooling/config, `documentation` for docs only, `dependencies` for bumps. When a change is two things at once, `security` beats `bug`, and `bug` beats `tech-debt`.
3. **Area labels** — `bin/labels infer <every path the plan will change>` (not files listed only as background reading), plus any area the path map can't see. Never zero.

```bash
gh issue edit <number> --add-label plan --add-label <type> --add-label <area> [--add-label <area>…]
```

(or pass the same labels as `--label` flags to `gh issue create`). If a label is missing on GitHub, run `bin/labels sync`; never `gh label create` a label that isn't in `.github/labels.yml`.

(For a plan written to a markdown file instead of an issue: put a `Labels: <type>, <area>…` line under the title so `/lfg` can carry them to the PR.)

For markdown files: Write to `docs/plans/YYYY-MM-DD-<slug>.md`. Leave it uncommitted — committing is the user's call.

## Phase 5 — Handoff

Report back: link to the issue (or file path), the chosen approach in 2–3 sentences, and the exact execute command. Stop there — do not start implementing.
