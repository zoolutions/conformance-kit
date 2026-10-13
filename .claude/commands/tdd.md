---
model: opus
description: "Use when implementing any feature or fixing any bug — enforces RED-GREEN-REFACTOR: write failing test first, implement minimum code to pass, then refactor."
---

# TDD Command

Enforce test-driven development with RED → GREEN → REFACTOR.

## The TDD Cycle

```text
RED:      Write a failing test (it MUST fail first)
GREEN:    Write MINIMAL code to pass (nothing more)
REFACTOR: Improve code while keeping tests green
REPEAT:   Next scenario
```

## When to Use

- Adding a check (a shared example, an audit rule) or a front end (RSpec, Minitest)
- Changing `Store`, `conformance-audit`, a config file or a reusable workflow
- Fixing a bug (write the reproducing test FIRST)

## Workflow

### Step 1: Write Failing Tests (RED)

Every check needs BOTH directions (`.claude/rules/testing.md`):

```ruby
# The check must CATCH a violating fixture
RSpec.describe ConformanceKit::Checks::ThreadContention do
  it "reports the racy cache" do
    result = described_class.call(threads: 8, iterations: 50) { RacyCache.fetch(:k) }
    expect(result).not_to be_ok
    expect(result.message).to include("RacyCache")
  end

  it "passes the guarded cache" do
    expect(described_class.call(threads: 8, iterations: 50) { GuardedCache.fetch(:k) }).to be_ok
  end
end

# A shared example must FAIL inside a sandbox without failing this suite
it "fails the example group for a violating fixture" do
  RSpec::Core::Sandbox.sandboxed do |config|
    group = RSpec.describe("fixture") { it_behaves_like "thread-safe under contention" ... }
    expect(group.run).to be(false)
  end
end

# Ractor behaviour runs only where it exists
it "runs inside a non-main Ractor", :ractor do
  skip "Ractor#value needs Ruby 4.0" unless Ractor.method_defined?(:value)
end
```

### Step 2: Run — Verify FAIL

```bash
bundle exec rspec <spec_file>
# FAIL — confirms the test runs, tests the right thing, and the code doesn't already exist
```

### Step 3: Implement Minimal Code (GREEN)

### Step 4: Run — Verify PASS

```bash
bundle exec rspec <spec_file>
# N examples, 0 failures
```

### Step 5: Refactor

Improve while staying green: extract methods, improve names, reduce duplication.

### Step 6: Run Full Suite + Lint

```bash
bundle exec rspec
bundle exec rubocop
```

## Coverage Expectations

| Code | Minimum |
|------|---------|
| All code | 80% |
| every check: violating fixture caught AND conforming fixture passed | 100% |
| `Store` fallback path (no `store_if_absent`) | 100% |

## Best Practices

**DO:** test FIRST; verify RED; minimal GREEN; refactor green;
force races with a `Thread.pass` or `Queue` handshake at the race window.

**DON'T:** implement before testing; assert a race result
after a `sleep`; ship a check never seen failing; skip a Ractor example without a reason.

## Checklist

- [ ] Tests written BEFORE implementation; RED verified
- [ ] Minimal GREEN; refactored green
- [ ] Coverage meets the bar (100% on both directions of every check)
- [ ] Edge + error paths covered
- [ ] Green on Ruby 3.2, 3.4 and 4.0 (or skipped there with a stated reason)
- [ ] `bundle exec rubocop` passes
