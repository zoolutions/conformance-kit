# Changelog

## Unreleased

- Shared examples (`require "conformance_kit/rspec"`): `"thread-safe under contention"`, `"fiber-safe under an Async reactor"`, `"a boot-finalized configuration"` and `"runs inside a non-main Ractor"` (Ruby 4.0+, tagged `:ractor`).
- The same checks as Minitest assertions (`require "conformance_kit/minitest"`): `assert_thread_safe`, `assert_fiber_safe`, `assert_boot_finalized`, `assert_runs_in_ractor`.
- `ConformanceKit::Store.fetch(key) { init }`: per-Ractor lazy storage (`Ractor.store_if_absent` on 3.4+, a Mutex-guarded fallback below).
- `conformance-audit`: reports unshareable constants and class/module ivars under a namespace; `.conformance.yml` `main_only:` allowlist with a required `reason:`; `--strict` exits 1.
- `config/rubocop.yml` (rubocop-thread_safety) and `config/rubocop_spinel.yml` (report-only Spinel probe).
- Reusable workflows: `ractor.yml` (Ruby 4.0 Ractor examples + `conformance-audit --strict`) and `probes.yml` (report-only rubocop_spinel, spinel-compat, roundhouse).
- Gem skeleton: release kit, labels kit, CI on Ruby 3.2, 3.4 and 4.0.
