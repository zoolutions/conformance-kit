# Changelog

## 0.2.0

Breaking (pre-1.0): the reusable workflows `ractor.yml` and `probes.yml` are replaced by `conformance.yml`, which an org ruleset requires at a release tag. A repo opts in with `.conformance.yml`; it needs no workflow edits.

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
