# Base Core Test Modules

The focused wrappers beside this directory select modules from `core-test`:

- `cron.sh` covers base cron aggregation and filters;
- `doctor.sh` covers base doctor helpers and section discovery;
- `launchers.sh` covers the Git bootstrap launcher;
- `merges.sh` covers base merge-hook discovery and shared merge behavior;
- `static.sh` covers repository policy, CI wiring, and portability.

Editor and development assertions live in their owning public overlay
repositories. Standalone command, repository, lock, and profile-parser behavior
lives in the Dot repository.
