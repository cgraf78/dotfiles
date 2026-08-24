# Authentication and Credential Operations

<!-- agent-rule-id: security-authentication-credential-operations -->
<!-- agent-rule-trigger: Investigating or changing authentication, passwords, credentials, PAM, login policy, or service accounts -->

Treat authentication as a layered system and credential changes as an explicit
mutation boundary. Begin read-only, preserve existing access, and validate with
the real client.

## Map the authentication path

- Identify every layer that can challenge or reject the request: network edge,
  reverse proxy, operating-system login, PAM, application session, token store,
  and backend service.
- Attribute a failure before changing credentials. Inspect status, challenge
  headers, relevant logs, and a direct response from the next layer when safe.
- Determine the credential's authoritative owner, precedence, consumers,
  recovery copies, and lifecycle. Metadata and presence checks should not print
  secret values.
- Prefer the existing operating-system or application-native credential
  lifecycle. A parallel password database or custom authentication stack is a
  separate design with its own recovery and rotation burden.

## Stop at the mutation boundary

- Before secret entry, password reset, credential creation, authentication
  policy replacement, or account mutation, state the exact next change and
  pause for explicit approval when it has not already been granted at that
  boundary.
- Have the user enter secrets through an interactive hidden prompt or approved
  secret store. Never request or place secrets in chat, prompts, command
  arguments, logs, captured output, Git, or durable memory.
- If the user stops the operation, immediately enumerate every change already
  made, every secret not yet created, and the available rollback evidence.
- Preserve unrelated login methods, accounts, authorization rules, and active
  sessions unless their change is explicitly in scope.

## Verify and roll back

- Validate configuration before reloading authentication services. Keep a
  readable before-state and a rollback path that does not depend on the new
  credential working.
- Verify success with the actual client login and intended identity. A file
  write, redirect, service restart, or credential-presence check is insufficient.
- Verify rollback at the privilege level required to read the affected state.
  Permission denial is an unverified check, not evidence that bytes match.
- Redact backend errors and remove temporary credential material on every
  failure path.
