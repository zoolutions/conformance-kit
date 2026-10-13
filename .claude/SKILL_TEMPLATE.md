# Command Template

Use this template when creating a new slash command for conformance-kit. See
`.claude/README.md` for the full authoring guide.

Copy the content below into `.claude/commands/{name}.md`, then fill it in.

Pick the model tier by the work the command does: `haiku` for mechanical/config
work, `sonnet` for prescriptive pattern-following passes, `opus` for
orchestration, security, review synthesis, and reasoning-heavy specialists.
Always use the tier alias, never a full model ID — aliases track the latest model
in the tier. Pin `fable` only on read-only planning commands that hand execution
to cheaper models (see `/plan`); sessions run on `opus` with `fable` as the
advisor (`.claude/settings.json`). Every agent the command spawns names its `model:`.

```markdown
---
model: sonnet
description: "{Action verbs describing what it does}. Use when {trigger phrases, contexts, file types}."
argument-hint: "{example input the user might provide}"
allowed-tools: {optional — narrow the tool allowlist, e.g. Bash(gh pr view:*), Read, Grep}
---

# {Command Title}

{One or two sentences: what this command is for and the mental model.}

## When to Use

- {Trigger context 1}
- {Trigger context 2}

## Workflow

1. {Step}
2. {Step}

## Project invariants to respect

- **Development dependency only** — nothing here becomes a runtime dependency of a consuming gem; optional libraries load lazily and skip with a reason.
- **Gate on the running Ruby, never the floor** — capability checks (`Ractor.respond_to?(:store_if_absent)`), never version strings; Ruby 3.2 stays supported.
- **Every check is proven both ways** — a violating fixture it catches and a conforming one it passes.
- **The kit obeys its own tiers** — its own code passes `conformance-audit` and the thread-safety cops.

## Verification

```bash
bundle exec rspec
bundle exec rubocop
```

## Checklist

- [ ] {Success criterion}
- [ ] `bundle exec rubocop` passes
```

After creating the file, add a row to the "Slash Commands" table in the repo
`AGENTS.md` so the command is discoverable and its tier is recorded.
