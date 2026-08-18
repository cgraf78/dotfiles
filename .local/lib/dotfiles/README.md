# Dotfiles Client Runtime

This tree contains executable policy owned by the dotfiles client. The
standalone `dot` checkout supplies repository convergence, extension workers,
and the public XDG/UI library; this directory supplies the application and
machine policy those generic interfaces execute.

## Layout

- `pre-sync.d/` prepares client prerequisites before repository network or
  checkout mutation. The SSH alias hook is intentionally client-owned.
- `merge-hooks.d/` contains application merge hooks and their private support.
- `doctor.d/` contains application and environment health checks.
- `git-hooks/` and `sley-hooks/` contain commit-policy adapters invoked by Git
  and Sley directly.
- `shell-loader.sh`, `launcher-real.sh`, `windows.sh`, and
  `shdeps-assets.sh` are client helpers used outside the extension workers.
- `dot-cutover.lock` is the single fleet rollout authority. In `phase=prepare`,
  Shdeps installs the reviewed standalone checkout and its public API, then a
  successful client convergence publishes private, topology-versioned host
  readiness. The retained `legacy-dot-launcher.sh` remains the only selected
  runtime until a separate revision changes the phase.
- `dot-client-readiness.sh` validates the regular adapter, public API link,
  standalone revision, and parsed client configuration before publishing that
  proof. A failure leaves the rescue authoritative and is retried by the next
  scheduled update.
- `tests/` owns the retained dotfiles consumer and integration suite.

Executable extensions use only the versioned public hook or doctor API. They
may load client support with `dot_hook_source` or `dot_doctor_source`; they do
not source private files from the standalone checkout.
