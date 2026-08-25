# Agent Rule Sources

This directory is the canonical, user-facing home for agent rule and playbook
prose. Keeping the prose here makes it visible independently of the dotfiles
merge implementation while allowing the same content to be rendered for every
supported agent.

Dotfiles owns which sources are active. The public repository supplies the
base files, and active overlay repositories may add files at the same relative
paths. The standalone
[`agent-rules-sync`](https://github.com/cgraf78/agent-rules-sync) command owns
generic validation, rendering, and publication after dotfiles resolves that
policy into a manifest.

## Always-Loaded Rules

`rules.d/` contains concise Markdown fragments that every generated target
loads. Direct files aggregate in lexical order, so use a three-digit numeric
prefix such as `070-engineering-workflow.md` when order matters. An immediate
`<name>.replace/` directory remains available when overlays need one
mutually-exclusive winner rather than additive fragments.

Every rule fragment must declare at least one globally unique identifier:

```markdown
<!-- agent-rule-id: example-rule -->
```

Keep task-specific procedures out of this always-loaded budget. Put them in a
playbook and add a concise trigger to the generated routing index instead.

## On-Demand Playbooks

`playbooks.d/` contains routed Markdown guidance. Its subdirectory structure is
the public route namespace, so `git/worktrees.md` is published under that exact
route. Every playbook must declare at least one globally unique rule ID and
exactly one trigger in its opening title and metadata block:

```markdown
# Example playbook

<!-- agent-rule-id: example-playbook -->
<!-- agent-rule-trigger: Performing the example task -->
```

Dotfiles indexes only tracked base files and exact links authorized by an
active overlay manifest. Untracked files and arbitrary symlinks are excluded so
a local file cannot silently become agent policy.

## Orchestration Boundary

This tree contains prose, not fleet target selection. Target profiles remain in
`~/.config/dot/merge-hooks.d/agent-rules/targets.d/`, where dotfiles can apply
overlay ordering and `.replace` policy. The merge hook writes the resolved
rules, routes, and targets to a private generated manifest under XDG state;
`agent-rules-sync` consumes that manifest without learning dotfiles overlay
semantics.

Generated runtime rule files and the manifest are outputs. Edit the sources in
this directory, run `dot update`, and then run the focused agent-rule tests or
`dot test` rather than editing generated targets directly.
