# Ripgrep Config

This directory contains the base ripgrep config referenced by
`RIPGREP_CONFIG_PATH` in the shell environment layer. It keeps ordinary search
policy independent of an installed editor.

The editor overlay selects its own additive configuration with hyperlink
routing and the small argument-adapting command that it requires. Route
parsing and opener behavior remain in `termnav`.
