# Changelog

## Unreleased

- `ConformanceKit::Store.fetch` on a non-main Ractor below Ruby 3.4: threads that race on the first fetch now all get the first value stored, instead of each keeping its own (found by zoolutions/docs-kit#103, whose copy of the Store had the same `||= [yield]`).

## 0.4.0

- `main_only:` takes `ancestor:` rules (with optional `ivars:`): framework class state on the gem's own subclasses (ActiveRecord, ActionController, Rails::Engine, ActiveSupport::Concern, ...) in one entry per framework instead of one per ivar per class. Constants are never covered; unused rules are listed as stale; an entry with an unknown key, or an ancestor every module has (`Object`, `Module`, ...), is a config error. `Audit::Finding` gains a `rule` member (the covering rule, or nil).
- `conformance-audit` no longer crashes on a `BasicObject` value (ActiveRecord keeps one in an unresolved model's `@primary_key`): the finding names its class through `Kernel#class`.

## 0.3.0

Breaking (pre-1.0): `conformance.yml` is a reusable workflow that each repo calls, instead of one an org ruleset requires. It runs on `workflow_call` only. A repo adds a caller pinned to a release tag (`uses: zoolutions/conformance-kit/.github/workflows/conformance.yml@vX.Y.Z`, see the README) and makes `conformance / Conformance settings` and `conformance / Conformance (Ruby 4.0)` required checks in its own branch ruleset. Repos outside zoolutions can use it the same way.

- The version handshake reads `job.workflow_ref` (the called workflow's own tag) instead of `github.workflow_ref` (the caller's).
- This repo calls its own workflow through `.github/workflows/conformance-self.yml`.

## 0.2.0

Breaking (pre-1.0): the reusable workflows `ractor.yml` and `probes.yml` are replaced by `conformance.yml`, which an org ruleset requires at a release tag. A repo opts in with `.conformance.yml`, `gem "conformance-kit", "~> 0.2"` and `gem "rubocop-thread_safety", ">= 0.8"` in its Gemfile, and `inherit_gem: { conformance-kit: config/rubocop.yml }` in `.rubocop.yml` (`conformance-kit doctor` checks all three); it needs no workflow edits.

- `.conformance.yml` 0.2 schema: `audit:` (`require`, `namespace`, `strict_autoloads`, `skip_autoloads`), `ractor:` (`ruby`, `test_command`, `env`, `setup`, `working_directory`), `probes:` (`gem_name`, `paths`, `roundhouse_app`) and the unchanged `main_only:`. Every key is validated; an unknown key or a wrong type exits 2.
- `conformance-kit` executable: `check` (doctor, `ractor.setup`, `ractor.test_command`, then `conformance-audit --strict`), `doctor [--expect X.Y]` and `config KEY`.
- `conformance-audit` reads `audit.require` and `audit.namespace` when no flags are given (flags still override); `--config` is the new name for `--allowlist`.
- `audit.strict_autoloads: true` makes `--strict` fail on unloaded autoloads not listed in `audit.skip_autoloads` (default `false`, 0.1's behaviour).
- `.github/workflows/conformance.yml`: the Ruby 4.0 conformance job (with a `postgres:18` service and the version handshake from `github.workflow_ref`) and the report-only compiler probes.

## 0.1.0

- Shared examples (`require "conformance_kit/rspec"`): `"thread-safe under contention"`, `"fiber-safe under an Async reactor"`, `"a boot-finalized configuration"` and `"runs inside a non-main Ractor"` (Ruby 4.0+, tagged `:ractor`).
- The same checks as Minitest assertions (`require "conformance_kit/minitest"`): `assert_thread_safe`, `assert_fiber_safe`, `assert_boot_finalized`, `assert_runs_in_ractor`.
- `ConformanceKit::Store.fetch(key) { init }`: per-Ractor lazy storage (`Ractor.store_if_absent` on 3.4+, a Mutex-guarded fallback below).
- `conformance-audit`: reports unshareable constants and class/module ivars under a namespace; `.conformance.yml` `main_only:` allowlist with a required `reason:`; `--strict` exits 1.
- `config/rubocop.yml` (rubocop-thread_safety) and `config/rubocop_spinel.yml` (report-only Spinel probe).
- Reusable workflows: `ractor.yml` (Ruby 4.0 Ractor examples + `conformance-audit --strict`) and `probes.yml` (report-only rubocop_spinel, spinel-compat, roundhouse).
- Gem skeleton: release kit, labels kit, CI on Ruby 3.2, 3.4 and 4.0.
