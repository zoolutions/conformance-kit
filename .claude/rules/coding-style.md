# Coding Style Rules

## File Organization

**MANY SMALL FILES > FEW LARGE FILES**

- High cohesion, low coupling; 200-400 lines typical, 800 max
- One concern per file: a check (`lib/conformance_kit/checks/*`), a test-framework front end (`rspec.rb`, `minitest.rb`), the store, the audit
- Checks are plain Ruby with no RSpec/Minitest dependency; the front ends only adapt them

## Ruby Style

Lint with **RuboCop** (`bundle exec rubocop`). RuboCop owns formatting — run `rubocop -A` and review.

### The kit must obey the tiers it enforces

This gem checks other gems for unsafe shared state, so its own code must pass its own audit:

```ruby
# Good: per-Ractor lazy state through the shim, never a Mutex in a constant
def self.cache = Store.fetch(:conformance_kit_cache) { {} }

# Bad: unreadable from a non-main Ractor, and a check-then-set race
CACHE = {}
def self.cache = (@cache ||= {})
```

### Gate on the running Ruby, never on a version string, never raise the floor

```ruby
# Good: capability check
if defined?(::Ractor) && ::Ractor.respond_to?(:store_if_absent)

# Bad
if RUBY_VERSION >= "3.4"
```

- `Ractor.store_if_absent` / `Ractor.main?`: 3.4+. `Ractor#value`, `Ractor.shareable_proc`: 4.0+ (`#take` before 4.0, removed in 4.0). TruffleRuby/JRuby have no `Ractor` at all.
- Before 4.0 a non-main Ractor cannot autoload: anything a Ractor example runs must already be loaded.

### No runtime dependencies for consumers

- `async`, `concurrent-ruby`, `minitest`, `rubocop_spinel` are optional: `require` them inside a `rescue LoadError` and skip with a stated reason.
- Never add a `spec.add_dependency` that a consuming gem would inherit, beyond what the front end it chose already needs.

### Failure messages name the culprit

A check that fails must say WHICH reader, constant or ivar, and the class of the offending value, so the consumer can fix it without re-running under a debugger.

## Code Quality Checklist

- [ ] Methods small (<30 lines ideal); files focused (<800 lines)
- [ ] No class/module ivar written after load except through `Store`
- [ ] Every optional dependency is loaded lazily and skipped with a reason
- [ ] `bundle exec rubocop` passes
