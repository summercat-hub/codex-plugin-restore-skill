# Diagnosis Reference

## Contents

- Evidence hierarchy
- Complete-inventory rule
- Failure matrix
- Marketplace integrity
- Cache aliases
- Provider-switch risks
- Repair boundaries
- Verification and rollback

## Evidence hierarchy

Prefer evidence in this order:

1. Current official OpenAI documentation and recent `openai/codex` issues.
2. Current CLI marketplace and installed-plugin state.
3. Current `config.toml` plugin sections.
4. Valid versioned caches containing `.codex-plugin/plugin.json`.
5. Timestamped configuration backups.
6. Sanitized desktop logs and user-observed UI state.

Use a union for discovery, then use the hierarchy to resolve conflicts. The UI is not authoritative for whether files or capabilities exist.

## Complete-inventory rule

An audit is incomplete until it scans every immediate marketplace directory under `~/.codex/plugins/cache`, not merely the marketplace implicated by the first symptom.

Classify a plugin as actionable prior-install evidence when at least one current strong signal exists:

- current `[plugins."name@marketplace"]` section;
- version directory with a valid `.codex-plugin/plugin.json`;
- CLI `installed` entry.

A backup section alone is historical evidence. Promote it to an actionable restoration target only when its marketplace is still registered/healthy or another current signal corroborates it. Otherwise report it as `historical-only`. This prevents temporary repair marketplaces from being resurrected after an official source supersedes them.

Do not count plugins found only in a marketplace source or CLI `available` list. Those prove availability, not prior installation.

The first repair can change CLI state and reveal a second broken marketplace. Always re-run the complete inventory after each repair pass.

## Failure matrix

| Prior evidence | Cache | Marketplace integrity | CLI installed | UI | Interpretation |
|---:|---:|---:|---:|---:|---|
| No | No | Healthy | No | Available | Never proven installed |
| Yes | Yes | Missing/broken | No | No | Marketplace restoration required |
| Yes | Yes | Healthy | No | No/install button | Installed-state drift or account sync |
| Yes | Yes | Healthy | Yes | No | Desktop filtering/display issue |
| Yes | Yes | Healthy | Yes | Yes | Healthy |

## Marketplace integrity

A local marketplace is healthy only when:

- its configured source exists;
- `.agents/plugins/marketplace.json` exists and parses;
- the CLI lists the marketplace;
- the manifest exposes the expected plugin directories.

### Primary runtime

The official Workspace Runtime commonly provides Documents, PDF, Spreadsheets, Presentations, and Template Creator. Discover the actual manifest dynamically.

### Bundled Windows marketplace

A Codex update can leave `~/.codex/.tmp/bundled-marketplaces/openai-bundled` partial, sometimes containing only Chrome and no marketplace manifest. Meanwhile the current AppX package can contain a complete official marketplace.

If the configured temporary root is missing or invalid and the current package root has a valid manifest, back up configuration and re-register `openai-bundled` to the package root. Restore only plugins with prior-install evidence. Do not install every plugin listed by the package.

### Remote catalog or account filtering

When local marketplaces and installed state are healthy but the online store is empty, check ChatGPT versus API-key login, subscription, workspace role, App enablement, rollout, region, and remote catalog errors. Local repair cannot grant server entitlements.

## Cache aliases

Some account-managed curated plugins are cached under a directory such as `openai-curated-remote` while their canonical plugin IDs use `@openai-curated`.

Normalize `name@marketplace-remote` to `name@marketplace` only when the base marketplace is registered or the plugin is corroborated by config/CLI evidence. Preserve the raw cache path in the report.

Snapshot hashes and `latest` links are versions, not marketplace names. Deduplicate the same canonical plugin across cache variants.

## Provider-switch risks

Provider/profile managers may rewrite `config.toml` instead of merging unknown blocks. This can remove marketplace registrations or plugin sections while leaving cache files intact.

Compare current and backup configurations for:

- `[marketplaces.*]` blocks;
- `[plugins."name@marketplace"]` blocks;
- provider definitions and `model_provider`;
- feature flags and `CODEX_HOME` changes.

Do not assert causation from timing alone. Prevent recurrence with separate `CODEX_HOME` values or a profile manager that preserves unknown TOML blocks.

## Repair boundaries

Do not use these as generic repairs:

- deleting plugin caches, authentication, or global state;
- installing the entire available catalog;
- repeatedly repairing the AppX package;
- copying unofficial code over an official marketplace;
- replacing a healthy different-source marketplace automatically;
- treating plus-menu absence as proof that an `@`-selectable plugin is broken.

## Verification and rollback

After repair, re-run the comprehensive inspector. Confirm the evidence-derived count, marketplace integrity, installed/enabled state, and unresolved classifications.

If behavior worsens:

1. Close Codex Desktop.
2. Restore the timestamped `config.toml` backup.
3. Restart Codex Desktop.
4. Re-run inspection and compare results.

Never report success solely because a command exited with code zero.
