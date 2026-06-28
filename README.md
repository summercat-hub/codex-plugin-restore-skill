# Codex Plugin Restore Skill

[简体中文](README.zh-CN.md)

`codex-plugin-restore-skill` repairs a Codex Desktop/CLI failure in which previously installed plugins disappear from the store, installed list, plugin picker, or `@` mentions. It restores the complete evidence-backed set of official plugins—not just browser-related plugins such as Chrome, Computer Use, and Browser.

The skill is designed for failures after Codex updates, provider or profile switches, ChatGPT/API-key transitions, Codex++ changes, cache rebuilds, broken marketplace registrations, or configuration drift.

## What it does

- Audits current and backup Codex configuration, versioned plugin caches, CLI state, and every configured marketplace.
- Reconstructs the expected installed-plugin inventory from strong local evidence.
- Detects missing manifests, stale or partial official marketplace roots, cache aliases, and installed-state drift.
- Repairs all detected known-official marketplace failures, then restores only plugins that have prior-install evidence.
- Re-runs the full inventory after repair and reports restored, visible, unresolved, historical-only, and available-only plugins separately.

## Why this is different

The repair is inventory-based rather than plugin-specific. A partial Windows marketplace can make one browser plugin the most obvious symptom while other official plugins—Documents, PDF, Spreadsheets, Presentations, Template Creator, GitHub integrations, and more—are missing at the same time. This skill audits every marketplace and reconciles the whole expected inventory before declaring success.

It also avoids a dangerous shortcut: installing every plugin currently available in a marketplace. Availability does not prove prior installation.

## Typical symptoms

- Installed plugins vanish after a Codex Desktop update.
- The plugin store, picker, or `@` mention list is empty or incomplete.
- Chrome, Computer Use, or Browser remains visible while other official plugins disappear.
- A marketplace points to a missing or partial temporary directory.
- Switching login/provider/profile removes plugin or marketplace entries from `config.toml`.
- Cached plugin versions still exist, but the CLI no longer reports them as installed.

## Usage

Install or copy this skill into your Codex skills directory, then ask Codex to audit and restore missing plugins. The included scripts can also be run directly from the skill directory.

Inspect the complete inventory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Inspect-CodexPluginInventory.ps1 -Json
```

Preview proposed repairs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Restore-CodexPluginInventory.ps1 -InspectOnly
```

Repair marketplaces and restore missing plugin states:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Restore-CodexPluginInventory.ps1 -Repair -RestoreMissingPluginStates
```

Review the preview before running repair mode.

## Safety model

- Does not delete plugin caches, authentication files, or Codex global state as a generic fix.
- Does not install every available plugin.
- Does not overwrite a healthy marketplace from a different source automatically.
- Preserves backup and rollback evidence before changing configuration.
- Separates local repair failures from account-, entitlement-, rollout-, region-, and server-managed visibility issues.

## Repository layout

- `SKILL.md` — agent workflow and mandatory safety rules.
- `agents/openai.yaml` — skill metadata.
- `references/diagnosis.md` — evidence hierarchy, failure matrix, and repair boundaries.
- `scripts/Inspect-CodexPluginInventory.ps1` — read-only inventory inspection.
- `scripts/Restore-CodexPluginInventory.ps1` — preview and repair workflow.

## Platform

The included automation targets Windows PowerShell and Codex Desktop/CLI installations. Some account-managed or server-side visibility problems cannot be repaired locally; the skill classifies those cases instead of forcing local changes.
