# conformance-kit

Concurrency conformance for Ruby gems. Built for the zoolutions gems and usable by any gem: [audit a gem without adding anything to it](#try-it-on-any-gem), [copy the checks into your own tests](#a-conformance-case-without-the-kit), or adopt the kit. A gem that adopts it is held to explicit tiers, each with a mechanical gate:

| Tier | Meaning | Gate |
|---|---|---|
| 1 thread-safe | no unguarded shared mutable state on the request/broadcast path | `config/rubocop.yml` (rubocop-thread_safety) + `"thread-safe under contention"` |
| 2 fiber-safe | correct under a fiber scheduler (Falcon/Async): request state fiber-local, no `Thread.main[]` misuse | `"fiber-safe under an Async reactor"` |
| 3 Ractor-clean | the gem adds no Ractor blocker beyond its dependencies': config shareable after boot, per-Ractor caches, no locks in constants | `"a boot-finalized configuration"`, `conformance-audit --strict`, the Ruby 4.0 `"runs inside a non-main Ractor"` canary (`conformance.yml`) |
| 4 compiler-probed | Spinel/Roundhouse readiness is measured, never gated | the probes job of `conformance.yml` (report-only) |

Background, the finalize-at-boot pattern and the settled decisions: [zoolutions/phlex-reactive#363](https://github.com/zoolutions/phlex-reactive/issues/363).

## Try it on any gem

No Gemfile change and no `.conformance.yml`: install the kit, then name the gem to load and the namespace to audit.

```bash
gem install conformance-kit
conformance-audit --require loofah --namespace Loofah
```

```
conformance-audit: 42 findings in Loofah (0 allowlisted main-only; 38 modules audited, 0 unloaded autoloads skipped)
  Loofah::Elements::BLOCK_LEVEL (constant) Set: a Set that is not frozen: freeze it at boot (Ractor.make_shareable)
  ...
  Loofah::Scrubbers::MAP (constant) Hash: a Hash that is not frozen: freeze it at boot (Ractor.make_shareable)
report only: --strict fails on these
```

That is loofah 2.25.2 on Ruby 4.0.7: every finding is state a non-main Ractor cannot read. `--require` takes a gem or feature name (required from the load path, so any installed gem) or a file path, and repeats (`--require rack --require rack/mock_request`). Without `--strict` it only reports. What it can and can't see, and its exit codes: [`conformance-audit`](#conformance-audit).

## A conformance case without the kit

When a new development dependency is not an option (a framework, a gem that keeps its bundle small), the two checks that matter most fit in the gem's own tests. This is the shape of the case to attach to a compatibility pull request: it fails before the fix, passes after it, and fails again on the next constant that stops being shareable.

```ruby
# Minitest
require "minitest/autorun" # or your test_helper

class RactorConformanceTest < Minitest::Test
  # State that is main-only on purpose, each with why.
  MAIN_ONLY = { "MyGem::REGISTRY" => "apps add to it at boot" }.freeze

  def setup
    skip "needs Ruby 4.0 (Ractor#value)" unless defined?(Ractor) && Ractor.method_defined?(:value)
  end

  # The entry point runs inside a non-main Ractor and gives the main Ractor's answer.
  def test_runs_inside_a_non_main_ractor
    assert_equal MyGem.render("<p>hi</p>"), Ractor.new { MyGem.render("<p>hi</p>") }.value
  end

  # Every constant under MyGem is shareable, so the next mutable one fails here.
  def test_constants_are_shareable
    unshareable = constants_under(MyGem).reject { |name, value| MAIN_ONLY.key?(name) || Ractor.shareable?(value) }
    assert_empty unshareable.map { |name, value| "#{name} (#{value.class})" }
  end

  private

  def constants_under(mod)
    mod.constants(false).reject { mod.autoload?(_1) }.flat_map do |name|
      value = mod.const_get(name, false)
      own = value.is_a?(Module) && value.name == "#{mod.name}::#{name}"
      [["#{mod.name}::#{name}", value], *(own ? constants_under(value) : [])]
    end
  end
end
```

```ruby
# RSpec
RSpec.describe "MyGem in a Ractor" do
  main_only = { "MyGem::REGISTRY" => "apps add to it at boot" }.freeze

  before { skip "needs Ruby 4.0 (Ractor#value)" unless defined?(Ractor) && Ractor.method_defined?(:value) }

  it "runs the entry point inside a non-main Ractor" do
    expect(Ractor.new { MyGem.render("<p>hi</p>") }.value).to eq(MyGem.render("<p>hi</p>"))
  end

  it "keeps every constant under MyGem shareable" do
    walk = lambda do |mod|
      mod.constants(false).reject { mod.autoload?(_1) }.flat_map do |name|
        value = mod.const_get(name, false)
        own = value.is_a?(Module) && value.name == "#{mod.name}::#{name}"
        [["#{mod.name}::#{name}", value], *(own ? walk.call(value) : [])]
      end
    end
    unshareable = walk.call(MyGem).reject { |name, value| main_only.key?(name) || Ractor.shareable?(value) }
    expect(unshareable.map { |name, value| "#{name} (#{value.class})" }).to be_empty
  end
end
```

A failure names the constant and its class, e.g. `Expected ["MyGem::Html::ESCAPES (Hash)"] to be empty.` The Ractor block must not use outer local variables: write its input inline, or reach it through a constant.

What these two leave out, and the kit covers:

- class and module instance variables (a `@cache ||= {}` memo);
- which value inside a constant is the problem: they name `MyGem::SETTINGS (Hash)`, the audit names `[:hooks] is a Proc that is never shareable`;
- unloaded autoloads, which they skip without a word (the audit lists them);
- races between threads and fibers.

Neither sees a constant the gem defines under another namespace, such as an Active Job adapter in `ActiveJob::QueueAdapters`: walk that namespace too, or pass it to `--namespace`.

## Adding it to a gem

**A development dependency only.** Nothing here becomes a runtime dependency of your gem, and the kit adds none to your bundle: `async`, `minitest`, `rubocop-thread_safety` and `rubocop_spinel` are used only when you already have them. Ruby 3.2+; Ractor-only behaviour is gated on the running Ruby, never on a version floor.

```ruby
# Gemfile
group :development, :test do
  gem "conformance-kit", "~> 0.4", require: false
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
require "minitest/autorun" # the kit never loads Minitest itself
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

On Ruby 3.4+ this is `Ractor.store_if_absent` (atomic, one value per Ractor). Below 3.4 the main Ractor (and an engine without `Ractor`) uses one Mutex-guarded Hash, and a non-main Ractor keeps its own values in Ractor-local storage, unlocked: two threads of that one Ractor can race to build a value, as with `||=`. Keys are Symbols; prefix them with your gem's name.

## `conformance-audit`

```bash
bundle exec conformance-audit --strict                                         # audit.require + audit.namespace from .conformance.yml
bundle exec conformance-audit --require ./lib/my_gem --namespace MyGem --strict # flags override them
```

Requires the files (an entry starting with `./`, `../`, `~` or `/` is a path; any other is required by name from the load path, as a gem, unless it names an existing file), walks every loaded module under the namespaces (`--require` and `--namespace` repeat; without them it reads `audit.require` and `audit.namespace`), and reports each public constant and class/module instance variable whose value is not `Ractor.shareable?`, with the path to the offending object and the fix:

```
conformance-audit: 2 findings in MyGem (1 allowlisted main-only; 14 modules audited, 0 unloaded autoloads skipped)
  MyGem::LOCK (constant) Thread::Mutex: a Thread::Mutex that is main-only: keep per-Ractor state in ConformanceKit::Store, or allowlist it main_only
  MyGem::Config.@colors (module ivar) Hash: [:primary] is an Array that is not frozen: freeze it at boot (Ractor.make_shareable)
```

Limits, so a green run means what it says:

- Unloaded autoload constants are skipped and listed, never loaded mid-walk: require (or eager-load) everything the audit should see. The header counts the modules audited and the autoloads skipped. With `audit.strict_autoloads: true`, `--strict` also fails on every skipped autoload not listed in `audit.skip_autoloads`, so a green run means every autoload not deliberately skipped was audited.
- `private_constant`s are invisible to it (Ruby has no public way to enumerate them). `config/rubocop.yml` and the boot-finalized example are the gates for those.

| Exit | Meaning |
|---|---|
| 0 | no unallowlisted findings; or findings without `--strict` (report only); or no `Ractor` on this engine |
| 1 | unallowlisted findings under `--strict` (or, with `audit.strict_autoloads`, unlisted unloaded autoloads) |
| 2 | usage error, no namespace from either the flags or `audit.namespace`, a namespace that is not defined or not a module, a file that cannot be required, or an invalid `.conformance.yml` |

### `.conformance.yml`

One file per repo says what it is held to. It is read from the working directory (or `--config PATH`; `--allowlist PATH` still works). `audit.require` and `ractor.working_directory` are relative to the file; `ractor.setup`, `ractor.test_command`, `probes.paths` and `probes.roundhouse_app` run in (or are relative to) `ractor.working_directory`. Every key is validated: an unknown key or a wrong type is an error (exit 2) naming the file and the key.

```yaml
audit:
  require: [./lib/my_gem, ./spec/support/eager_load.rb]   # files to require (list)
  namespace: [MyGem]                                       # constants to audit (list)
  strict_autoloads: true                                   # optional, default false
  skip_autoloads:                                          # optional; each needs a reason
    - name: MyGem::Optional
      reason: only loads with pgbus present
ractor:
  ruby: "4.0"                                  # default "4.0" (quote it)
  test_command: bundle exec rspec --tag ractor # default; Minitest gems set their own
  env:                                         # optional string map, applied before setup/test_command
    PGBUS_DATABASE_URL: postgres://postgres:postgres@localhost:5432/pgbus_test
  setup: bin/conformance-db-setup              # optional command run once before test_command
  working_directory: .                         # default "."
probes:
  gem_name: my_gem                             # required for the probes job
  paths: [lib]                                 # default [lib]
  roundhouse_app: spec/dummy                   # optional
main_only:
  - name: MyGem::Registry.@lock                # class/module ivar: Owner.@ivar
    reason: guards boot-time registration; no non-main Ractor ever registers
  - name: MyGem::LOCK                          # constant: Owner::NAME
    reason: ...
  - ancestor: Rails::Engine                    # framework state on the gem's own subclasses
    ivars: ["@called_from", "@initializers", "@instance"]  # only the framework's ivars
    reason: Rails::Engine's own class state, set by Rails at boot on the main Ractor
  - ancestor: ActionController::Base           # without ivars: every ivar on its subclasses
    reason: ActionController's own class state, set by Rails on the main Ractor
```

`main_only:` is state that is deliberately main-only: every entry needs a `reason:`. Entries inside the audited namespaces that no longer turn up are listed as stale, and so are `audit.skip_autoloads` entries that are no longer unloaded autoloads.

An `ancestor:` entry covers the class state a framework keeps on the gem's own classes, which would otherwise take one `name:` entry per ivar per class (a Rails engine easily needs a hundred): every class/module ivar on a module that inherits from, includes or is extended with that constant. It never covers a constant. Prefer `ivars:`: it narrows the rule to the framework's own ivars, so state the gem keeps on the same classes is still audited. Without `ivars:`, that state is allowlisted too, so use the bare form only for classes the gem adds no state to. A `name:` entry for an ivar a rule also covers keeps its own reason. A rule that covered nothing, or whose constant isn't loaded (never loaded by the audit, even if it is a declared autoload), is listed as stale. `BasicObject`, `Object`, `Kernel`, `Module` and `Class` are rejected as ancestors (every module has them), and so is any unknown key in an entry, so a typo cannot widen a rule. `audit.skip_autoloads` takes `name:` entries only.

`strict_autoloads: true` needs `audit.require` to load everything, e.g. a file that calls your Zeitwerk loader's `eager_load!`. In a Rails engine, `MyGem::Engine.eager_load!` is a no-op (Rails 7+): call `Zeitwerk::Loader.eager_load_namespace(MyGem)` after booting the dummy app instead, and reference constants in `autoload_once_paths` explicitly.

## RuboCop

```yaml
# .rubocop.yml
inherit_gem:
  conformance-kit: config/rubocop.yml
```

Turns on the six `rubocop-thread_safety` cops (`ClassAndModuleAttributes`, `ClassInstanceVariable`, `MutableClassInstanceVariable` with `EnforcedStyle: literals`, `NewThread`, `DirChdir`, `RackMiddlewareInstanceVariable`) plus `LazySynchronizationPrimitive` (which needs rubocop-thread_safety 0.8+). Exclude a file or line only with a comment saying why it is safe.

`config/rubocop_spinel.yml` runs only `Spinel/Unsupported` (rubocop_spinel). It is for the report-only probe, never your lint: it flags `class << self`.

## Enforcement

Conformance runs as **one reusable workflow in this repo**, `.github/workflows/conformance.yml`. Any repo can call it, inside zoolutions or not. A repo opts in with

1. `.conformance.yml` (above),
2. the Gemfile lines (`conformance-kit ~> 0.4`, `rubocop-thread_safety >= 0.8`),
3. `inherit_gem: { conformance-kit: config/rubocop.yml }` in `.rubocop.yml`,
4. a caller, pinned to a release tag:

```yaml
# .github/workflows/conformance.yml
name: Conformance

on:
  pull_request:
  merge_group:

permissions:
  contents: read

jobs:
  conformance:
    uses: zoolutions/conformance-kit/.github/workflows/conformance.yml@v0.4.2
```

To make it a merge requirement, add `conformance / Conformance settings` and `conformance / Conformance (Ruby 4.0)` to the required status checks in the repo's branch ruleset. Require both: if the settings job fails, the gate is skipped, and a skipped check does not block a merge. The prefix is the caller's job id (`conformance` above) and the Ruby is `ractor.ruby`, so the names change with either. Leave the probes out: they never fail. A repo or org that only allows selected actions must allow `zoolutions/conformance-kit/.github/workflows/conformance.yml@*`.

The workflow has three jobs:

- **Conformance settings** reads `ractor.ruby` and `ractor.working_directory`.
- **Conformance (Ruby `ractor.ruby`)**, the gate: the version handshake, then `bundle exec conformance-kit check`. A `postgres:18` service (user and password `postgres`, port 5432) is always up; the workflow exports nothing, so `ractor.env` and `ractor.setup` wire it.
- **Compiler probes (report-only)**: `rubocop_spinel` (gem-installed in the probe, never in your Gemfile), `spinel-compat probe <probes.gem_name> --dir .` and, when `probes.roundhouse_app` is set, `roundhouse check` (the release tarball, checked against a pinned SHA-256). Every probe continues on error; the reports go to the run summary and a `conformance-probes` artifact. It never fails a build, and it skips with a notice when `probes.gem_name` is unset.

### Staying current

Dependabot bumps both pins, the `uses:` tag (`github-actions`) and the gem (`bundler`), in **one** pull request through a multi-ecosystem group. It can still open one with a single pin when only one ecosystem has an update so far (the tag is out but RubyGems hasn't published the gem yet): the version handshake then fails that pull request until the other pin catches up, so check both before merging. The `allow` lists keep it to the kit; drop them to have Dependabot maintain everything else too.

```yaml
# .github/dependabot.yml
version: 2
multi-ecosystem-groups:
  conformance-kit:
    schedule: { interval: weekly }
    labels: ["dependencies", "devops"]        # your repo's own type + area labels
updates:
  - package-ecosystem: github-actions
    directory: /
    multi-ecosystem-group: conformance-kit
    patterns: ["zoolutions/conformance-kit*"]
    allow:
      - dependency-name: "zoolutions/conformance-kit*"
  - package-ecosystem: bundler
    directory: /
    multi-ecosystem-group: conformance-kit
    patterns: ["conformance-kit"]
    allow:
      - dependency-name: conformance-kit
```

### `conformance-kit check`, the local equivalent

```bash
bundle exec conformance-kit check    # doctor, ractor.setup, ractor.test_command, then conformance-audit --strict
bundle exec conformance-kit doctor   # the static checks only
bundle exec conformance-kit config probes.gem_name
```

`check` stops at the first failing stage, names it, and exits with its status. Run it before adding the caller: what passes here passes the workflow (on the same Ruby).

`doctor` checks that `.conformance.yml` exists, is valid and sets `audit.namespace`; that `.rubocop.yml` inherits `conformance-kit: config/rubocop.yml`; and that `rubocop-thread_safety` resolves at `>= 0.8`. Each problem names its fix. `--expect X.Y` also checks the resolved `conformance-kit` is at least `X.Y`.

`config KEY` prints a dotted key's value (a list joined with spaces, `ractor.env` as `NAME=value` lines, an unset key as an empty line); an unknown key exits 2.

| Exit | Meaning |
|---|---|
| 0 | ok |
| 1 | a check failed (`check` exits with the failing stage's status) |
| 2 | usage error or an invalid `.conformance.yml` |

### The version handshake

The behaviour a repo is held to comes from the `conformance-kit` in its lockfile; only the plumbing comes from the workflow tag. So that a stale lockfile cannot pass a newer workflow vacuously, the workflow reads its own tag from `job.workflow_ref` (the called workflow's ref; `github.workflow_ref` is the caller's) and fails with "bump conformance-kit to ~> X.Y" when the repo resolves anything older than `X.Y`. The version is derived, never stored. When the caller pins anything other than a `vX.Y.Z` tag (a branch, a commit SHA, or this repo's own `./` caller) the handshake is skipped with a notice, and so it is on GitHub Enterprise Server, which has no `job.workflow_ref`.

## Development

```bash
bundle exec rake   # rspec + rubocop; CI runs Ruby 3.2, 3.4 and 4.0
```

Every check is proven both ways against `spec/fixtures/`: a violating fixture it must catch and a conforming one it must pass. The kit audits itself (`.conformance.yml`, strict, nothing skipped), and `conformance.yml` runs on its own pull requests.
