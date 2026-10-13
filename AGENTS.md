# conformance-kit

Shared concurrency conformance for the zoolutions gems (zoolutions/phlex-reactive#363).

- Ruby floor 3.2. Ractor-only behaviour is gated on the running Ruby (`Ractor.store_if_absent` 3.4+, `Ractor#value` 4.0+); never raise the floor for it.
- Development dependency only: nothing here may become a runtime dependency of a consuming gem.
- TDD: write the failing spec first. `bundle exec rspec` and `bundle exec rubocop` must pass.
- `bin/release`, `rakelib/release.rake`, `release.yml`'s shared jobs, `bin/labels` and `.github/LABELS.md` are the zoolutions release and labels kits (canonical copy in docs-kit): never edit them here.
- Every PR carries one `type` label and at least one `area` label from `.github/labels.yml` (`bin/labels infer <paths>`).
