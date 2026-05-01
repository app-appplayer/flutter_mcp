# Flutter MCP — Documentation

Companion documentation that ships with the package on pub.dev.
README covers the quick-start path; the documents here go deeper into
specific areas.

## Index

- [`architecture.md`](architecture.md) — package layout, manager-based
  runtime, lifecycle, identity model, spec capability mapping.
- [`transports.md`](transports.md) — Stdio / SSE / Streamable HTTP
  client and server configuration, with the validation rules and
  common pitfalls.
- [`spec-features.md`](spec-features.md) — Phase 2 surface: sampling,
  elicitation, roots, completion, OAuth Resource Server (RFC 9728),
  structured tool output.
- [`plugins.md`](plugins.md) — `MCPPlugin` family, registration
  flow, registry inspection, auto-loading from configuration.
- [`platform-services.md`](platform-services.md) — background
  service, notifications, tray, secure storage, lifecycle, runtime
  permissions, per-platform constraints.
- [`observability.md`](observability.md) — logging, system status,
  health, performance metrics, security audit, resource leak
  tracking, internal event topics.
- [`migration-2.0.md`](migration-2.0.md) — the breaking-change
  catalogue for upgrading from 1.x.

For everything else (install, supported revisions, quick samples)
see the package's [README.md](../README.md).
