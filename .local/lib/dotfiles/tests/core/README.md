# Base Core Test Modules

The focused `core-*-test` wrappers beside this directory select modules from
`core-test`; `core-update-test` is the exception, a standalone end-to-end
update integration that does not use these modules:

- `cron.sh` covers base cron aggregation and filters;
- `doctor.sh` covers base doctor helpers and section discovery;
- `launchers.sh` covers the Git bootstrap launcher;
- `merges.sh` covers base merge-hook discovery and shared merge behavior;
- `static.sh` covers repository policy, CI wiring, and portability.

Editor and development assertions live in their owning public overlay
repositories. Standalone command, repository, lock, and profile-parser behavior
lives in the Dot repository.
