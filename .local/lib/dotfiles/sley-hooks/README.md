# Sley Policy Providers

This directory contains dotfiles-owned policy reached through Sley's reusable
SCM hook APIs. These files are internal providers, not PATH-visible commands or
alternative hook frameworks.

`validate-commit-msg` enforces the existing Git and Sapling commit-message
grammar. Sley supplies the generic executable-provider contract and passes one
message-file path; dotfiles selects the applicable profile through
`COMMIT_MSG_FORMAT`. Keeping the prose policy here avoids teaching Sley one
user's required sections while allowing every supported SCM integration to use
the same Sley orchestration.

The validator retains stdin, `--file`, `--format`, and `--strict` inputs for
focused policy tests and compatible internal callers. Hook integrations should
route through `sley hook validate-message --validator ...` instead of invoking
the provider directly.

The Git adapter in `../git-hooks/commit-msg` selects this provider. Private
overlay policy may select it through the same Sley API with a different format;
no private policy or vocabulary belongs in this public directory.
