# Testing Rules

## TDD Workflow

RED → GREEN → REFACTOR. Write the failing spec, watch it fail for the right reason, then the minimum code.

## A check must be proven to FAIL as well as pass

Every shared example and audit rule ships with two fixtures in `spec/fixtures/`:

- a **violating** fixture the check MUST catch (e.g. a cache whose miss path does `@cache ||= {}` with a `Thread.pass` inside, an unfrozen Array in a constant, a Proc in a class ivar)
- a **conforming** fixture it MUST pass

Assert the failure without failing this suite: run the example group in an `RSpec::Core::Sandbox` (or `Minitest::Runnable` with a captured reporter) and inspect its result. A check that has never been seen failing is untested.

## Determinism

- Races must be forced, not hoped for: put a `Thread.pass` (or a `Queue` handshake) at the race window in the violating fixture so the thread example catches it every run.
- Never assert on timing. Use handshakes (`Queue#pop`) instead of `sleep`.
- Ractor specs: tag `:ractor`, skip with a reason when `Ractor#value` is unavailable (below 4.0). Use `Ractor#value` when defined, `#take` otherwise.

## The matrix

CI runs Ruby 3.2, 3.4 and 4.0. Locally:

```bash
bundle exec rspec
PATH=$HOME/.rubies/ruby-4.0.6/bin:$PATH GEM_HOME=$HOME/.gem/ruby/4.0.6 GEM_PATH=$HOME/.gem/ruby/4.0.6:$HOME/.rubies/ruby-4.0.6/lib/ruby/gems/4.0.0 bundle exec rspec
PATH=$HOME/.rubies/ruby-3.2.8/bin:$PATH GEM_HOME=$HOME/.gem/ruby/3.2.8 GEM_PATH=$HOME/.gem/ruby/3.2.8:$HOME/.rubies/ruby-3.2.8/lib/ruby/gems/3.2.0 bundle exec rspec
```

The Store fallback (no `store_if_absent`) must be covered on 3.4 too, by stubbing the capability check.

## Test Checklist

- [ ] Spec written BEFORE the implementation; RED verified
- [ ] Violating AND conforming fixture for every check
- [ ] Ractor examples skipped with a reason below 4.0, never silently passed
- [ ] `bundle exec rspec` green; `bundle exec rubocop` passes
