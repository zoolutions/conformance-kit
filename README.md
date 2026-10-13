# conformance-kit

Concurrency conformance for the zoolutions gems. A gem that adopts it is held to explicit tiers, each with a mechanical gate:

| Tier | Meaning | Gate |
|---|---|---|
| 1 thread-safe | no unguarded shared mutable state on the request/broadcast path | `config/rubocop.yml` (rubocop-thread_safety) + `"thread-safe under contention"` |
| 2 fiber-safe | correct under a fiber scheduler (Falcon/Async): request state fiber-local, no `Thread.main[]` misuse | `"fiber-safe under an Async reactor"` |
| 3 Ractor-clean | the gem adds no Ractor blocker beyond its dependencies': config shareable after boot, per-Ractor caches, no locks in constants | `"a boot-finalized configuration"`, `conformance-audit --strict`, the Ruby 4.0 `"runs inside a non-main Ractor"` canary (`ractor.yml`) |
| 4 compiler-probed | Spinel/Roundhouse readiness is measured, never gated | `probes.yml` (report-only) |

Background, the finalize-at-boot pattern and the settled decisions: [zoolutions/phlex-reactive#363](https://github.com/zoolutions/phlex-reactive/issues/363).

**A development dependency only.** Nothing here becomes a runtime dependency of your gem, and the kit adds none to your bundle: `async`, `minitest`, `rubocop-thread_safety` and `rubocop_spinel` are used only when you already have them. Ruby 3.2+; Ractor-only behaviour is gated on the running Ruby, never on a version floor.

```ruby
# Gemfile
group :development, :test do
  gem "conformance-kit", github: "zoolutions/conformance-kit"
  gem "rubocop-thread_safety", ">= 0.8", require: false # for config/rubocop.yml
  gem "async", require: false                 # optional: runs the fiber example
end
```

## Shared examples (RSpec)

```ruby
# spec/spec_helper.rb
require "conformance_kit/rspec"
```

Each example calls `subject_call`, a callable for the operation under test:

```ruby
RSpec.describe MyGem::Cache do
  let(:subject_call) { -> { MyGem::Cache.for(:key) } }

  it_behaves_like "thread-safe under contention", threads: 8, iterations: 50, consistent: :identical
  it_behaves_like "fiber-safe under an Async reactor", fibers: 8, iterations: 50
end

RSpec.describe MyGem do
  it_behaves_like "a boot-finalized configuration",
                  readers: [MyGem.method(:colors), MyGem.method(:adapters)],
                  finalize: -> { MyGem.finalize! }
end

RSpec.describe MyGem::Token do
  let(:subject_call) { ->(payload) { MyGem::Token.verify(MyGem::Token.sign(payload)) } }

  it_behaves_like "runs inside a non-main Ractor", inputs: [{ id: 1 }]
end
```

| Example | Options | Fails when | Skipped when |
|---|---|---|---|
| `"thread-safe under contention"` | `threads:` (8), `iterations:` (50), `consistent:` | a call raises, or the results disagree | — |
| `"fiber-safe under an Async reactor"` | `fibers:` (8), `iterations:` (50), `consistent:` | a call raises inside an `Async` task, or the results disagree | `async` is not loadable |
| `"a boot-finalized configuration"` | `readers:`, `finalize:` | a reader returns a value that is not `Ractor.shareable?` (or raises) | no `Ractor` (TruffleRuby, JRuby) |
| `"runs inside a non-main Ractor"` (tagged `:ractor`) | `inputs:` ([]) | the block raises inside `Ractor.new`, captures outer variables, or returns something else than on the main Ractor | below Ruby 4.0 (`Ractor#value`) |

- `consistent:` is opt-in: `:identical` (every result is the same object, e.g. a memoized cache), `:equal` (all `==`), or a callable that receives every result and returns truthy.
- `readers:` takes `Method` objects (reported as `Owner.reader`), a `{ "name" => callable }` Hash, or bare callables (reported by source location).
- The Ractor block must be capture-free: pass values through `inputs:`, reach everything else through constants. Before 4.0 a non-main Ractor cannot autoload, so load what it touches first.

Failures name the culprit, e.g.

```
a boot-finalized configuration: 1 of 2 readers returned a value that is not Ractor-shareable:
  MyGem.colors returned Hash: [:primary] is an Array that is not frozen: freeze it at boot (Ractor.make_shareable)
```

## Assertions (Minitest)

```ruby
require "conformance_kit/minitest"

class CacheTest < Minitest::Test
  include ConformanceKit::Minitest

  def test_thread_safe = assert_thread_safe(threads: 8, iterations: 50, consistent: :identical) { MyGem::Cache.for(:key) }
  def test_fiber_safe = assert_fiber_safe(fibers: 8) { MyGem::Cache.for(:key) }
  def test_boot_finalized = assert_boot_finalized(readers: [MyGem.method(:colors)], finalize: -> { MyGem.finalize! })
  def test_ractor = assert_runs_in_ractor(inputs: [2]) { |n| MyGem.double(n) }
end
```

Same checks, same options and messages; skips use `skip` with the reason. Works on Minitest 5 and 6.

## `ConformanceKit::Store`

Per-Ractor lazy storage, the home for caches that must not live in a class ivar or a constant:

```ruby
def self.cache = ConformanceKit::Store.fetch(:my_gem_cache) { {} }
```

On Ruby 3.4+ this is `Ractor.store_if_absent` (atomic, one value per Ractor). Below 3.4, and on engines without `Ractor`, it falls back to one Mutex-guarded Hash: safe there, since a non-main Ractor cannot run your code before 4.0 anyway. Keys are Symbols; prefix them with your gem's name.

## `conformance-audit`

```bash
bundle exec conformance-audit --require ./lib/my_gem --namespace MyGem --strict
```

Requires the files, walks every loaded module under the namespaces (`--require` and `--namespace` repeat), and reports each public constant and class/module instance variable whose value is not `Ractor.shareable?`, with the path to the offending object and the fix:

```
conformance-audit: 2 findings in MyGem (1 allowlisted main-only; 14 modules audited, 0 unloaded autoloads skipped)
  MyGem::LOCK (constant) Thread::Mutex: a Thread::Mutex is main-only: keep per-Ractor state in ConformanceKit::Store, or allowlist it main_only
  MyGem::Config.@colors (module ivar) Hash: [:primary] is an Array that is not frozen: freeze it at boot (Ractor.make_shareable)
```

Limits, so a green run means what it says:

- Unloaded autoload constants are skipped and listed, never loaded mid-walk: require (or eager-load) everything the audit should see. The header counts the modules audited and the autoloads skipped.
- `private_constant`s are invisible to it (Ruby has no public way to enumerate them). `config/rubocop.yml` and the boot-finalized example are the gates for those.

| Exit | Meaning |
|---|---|
| 0 | no unallowlisted findings; or findings without `--strict` (report only); or no `Ractor` on this engine |
| 1 | unallowlisted findings under `--strict` |
| 2 | usage error, a namespace that is not defined or not a module, a file that cannot be required, or an invalid allowlist |

### `.conformance.yml`

State that is deliberately main-only, read from `.conformance.yml` in the working directory (or `--allowlist PATH`). Every entry needs a `reason:`; an entry without one is an error (exit 2).

```yaml
main_only:
  - name: MyGem::Registry.@lock     # class/module ivar: Owner.@ivar
    reason: guards boot-time registration; no non-main Ractor ever registers
  - name: MyGem::LOCK               # constant: Owner::NAME
    reason: ...
```

Entries inside the audited namespaces that no longer turn up are listed as stale.

## RuboCop

```yaml
# .rubocop.yml
inherit_gem:
  conformance-kit: config/rubocop.yml
```

Turns on the six `rubocop-thread_safety` cops (`ClassAndModuleAttributes`, `ClassInstanceVariable`, `MutableClassInstanceVariable` with `EnforcedStyle: literals`, `NewThread`, `DirChdir`, `RackMiddlewareInstanceVariable`) plus `LazySynchronizationPrimitive` (which needs rubocop-thread_safety 0.8+). Exclude a file or line only with a comment saying why it is safe.

`config/rubocop_spinel.yml` runs only `Spinel/Unsupported` (rubocop_spinel). It is for the report-only probe, never your lint: it flags `class << self`.

## Reusable workflows

```yaml
# .github/workflows/main.yml
jobs:
  ractor:
    uses: zoolutions/conformance-kit/.github/workflows/ractor.yml@main
    with:
      require: ./lib/my_gem
      namespace: MyGem

  probes:
    uses: zoolutions/conformance-kit/.github/workflows/probes.yml@main
    with:
      gem-name: my_gem
```

**`ractor.yml`** (the Tier 3 gate): the Ractor examples, then `conformance-audit --strict`.

| Input | Default | |
|---|---|---|
| `require` | required | files the audit requires (space-separated) |
| `namespace` | required | constants to audit (space-separated) |
| `ruby-version` | `4.0` | |
| `allowlist` | `.conformance.yml` | skipped when the default file is absent |
| `test-command` | `bundle exec rspec --tag ractor` | Minitest gems pass their own |
| `audit` | `true` | `false` runs only the examples |
| `working-directory` | `.` | |

**`probes.yml`** (Tier 4, report-only): `rubocop_spinel`, `spinel-compat probe <gem-name> --dir .` and, when `roundhouse-app` is set, `roundhouse check`. Every probe step continues on error; the reports go to the run summary and an artifact. It never fails a build.

| Input | Default | |
|---|---|---|
| `gem-name` | required | the gem spinel-compat probes from the checkout |
| `ruby-version` | `4.0` | |
| `paths` | `lib` | what rubocop_spinel inspects (space-separated) |
| `roundhouse-app` | `""` | a Rails app directory (e.g. `spec/dummy`); empty skips it |
| `roundhouse-version` | `v2026.9.18` | the rubys/roundhouse release to install |
| `artifact-name` | `conformance-probes` | |
| `working-directory` | `.` | |

## Development

```bash
bundle exec rake   # rspec + rubocop; CI runs Ruby 3.2, 3.4 and 4.0
```

Every check is proven both ways against `spec/fixtures/`: a violating fixture it must catch and a conforming one it must pass. The kit audits itself (`.conformance.yml`) and calls its own workflows in CI.
