---
model: opus
description: Review a GitHub pull request for code quality, patterns, and best practices
argument-hint: "PR URL or number (e.g., 5 or https://github.com/zoolutions/conformance-kit/pull/5)"
---

# PR Review

Review a PR for pattern compliance and issues. Be concise.

## Workflow

1. Fetch PR details and diff: `gh pr view <PR> --json title,body,files` and `gh pr diff <PR>`
2. Categorize files by area (examples, store, audit, config, devops, dx)
3. Check for pattern violations
4. Output a structured review

## Pattern Violations to Check

```text
# WRONG -> RIGHT
Check with no violating fixture          -> A fixture it must catch AND one it must pass
Race "found" by looping until it fails   -> Force it with Thread.pass / a Queue handshake
`sleep` as a synchronization barrier     -> Queue#pop handshake
RUBY_VERSION comparison                  -> Capability check (Ractor.respond_to?(:store_if_absent))
Raising the Ruby floor for a Ractor API  -> Gate on the running Ruby; 3.2 stays supported
Ractor example silently passing < 4.0    -> skip with a stated reason
Ractor#take / #value used unconditionally -> value when defined, take otherwise
Hard require of async / minitest / rubocop_spinel -> require in rescue LoadError, skip with a reason
spec.add_dependency a consumer inherits  -> Optional, loaded lazily
@x ||= in a module / Mutex in a constant -> ConformanceKit::Store.fetch
Failure message without the culprit      -> Name the reader/constant/ivar and the value class
Editing bin/release, release.rake, bin/labels, LABELS.md -> Change docs-kit, then sync
Manual gem push                          -> bin/release
```

## Output Format

```
## Files Requiring Manual Review

| File | Reason |
|------|--------|
| lib/conformance_kit/checks/<check>.rb | New check — verify a violating fixture proves it fails |
| exe/conformance-audit | Exit codes and allowlist handling are a public contract |
| .github/workflows/conformance.yml | Reusable workflow — every adopting gem calls it at a release tag |

## Critical Issues

- `lib/conformance_kit/store.rb:NN` - fallback path untested on 3.4
- `lib/conformance_kit/rspec.rb:NN` - hard require of async

## Suggestions (non-blocking)

- Consider extracting X

## Verdict

**Request Changes** | **Approve** | **Comment** — one-line justification
```

## Tools

```text
gh pr view <PR> --json title,body,files,statusCheckRollup
gh pr diff <PR>
gh pr checks <PR>

bundle exec rubocop      -> Style checks
bundle exec rspec        -> Tests
```
