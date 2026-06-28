---
name: codex-plugin-restore-skill
description: Audit and restore every Codex plugin with local evidence of prior installation when plugins disappear from the store, installed list, plugin picker, or @ mentions after an app update, provider/profile switch, ChatGPT/API-key transition, Codex++, cache rebuild, or marketplace corruption. Use for Codex Desktop or CLI plugin discovery failures, partial marketplace recovery, installed-state drift, missing manifests, stale official marketplace roots, and safe cross-machine plugin restoration.
---

# Codex Plugin Restore

Treat plugin restoration as an inventory reconciliation problem. Never assume one marketplace, one cache, or the current CLI list is the complete history.

## Required evidence model

Keep these states separate for every plugin:

1. Prior-install evidence: current or backup config section, versioned cache containing `.codex-plugin/plugin.json`, or current CLI installed state.
2. Marketplace health: registered root, existing directory, valid `.agents/plugins/marketplace.json`, and CLI discovery.
3. Plugin state: installed and enabled according to the CLI or account-managed desktop state.
4. UI visibility: store result, installed page, plus menu, and `@` picker. These surfaces may intentionally differ.

Do not classify every plugin in an available marketplace as previously installed. Build the expected set from the union of strong prior-install evidence.

## Workflow

### 1. Research the current failure

Search current official OpenAI documentation and recent `openai/codex` issues using exact app/CLI versions and log signatures. Prefer confirmed Windows marketplace/cache reports over generic reinstall advice.

### 2. Run the comprehensive inspection

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Inspect-CodexPluginInventory.ps1 -Json
```

The inspection must enumerate all of the following before reporting a count:

- every plugin section in the current `config.toml`;
- plugin sections in timestamped config backups;
- every versioned plugin cache under `~/.codex/plugins/cache`, including cache aliases such as `openai-curated-remote`;
- current CLI-installed and CLI-available plugins across every marketplace;
- every configured marketplace root and whether its directory and manifest are complete;
- known official candidates from Workspace Runtime and the current Codex Desktop package;
- optional user-reported visible plugin IDs for an explicit UI comparison.

Read [references/diagnosis.md](references/diagnosis.md) when interpreting conflicts, cache aliases, incomplete bundled marketplaces, or account-managed plugins.

### 3. Reconcile the complete inventory

Compute a candidate union:

```text
Expected previously installed
= current config plugin IDs
∪ backup config plugin IDs
∪ valid versioned cache plugin IDs
∪ CLI installed plugin IDs
```

Then move backup-only entries to `historical-only` when their marketplace is no longer registered and they have no cache or CLI corroboration. Do not auto-restore them. If an active official plugin with the same name exists, classify the retired entry as a superseded workaround rather than a second plugin.

Deduplicate actionable entries by canonical `name@marketplace`. Map a `*-remote` cache to the registered base marketplace only when the base marketplace exists. Report these separately:

- total expected previously installed;
- currently CLI installed and enabled;
- cached/configured but missing from CLI;
- user-visible versus not visible, when UI evidence is supplied;
- available-only plugins, which are not restoration targets.
- historical-only or superseded backup entries, which require explicit review.

Do not stop after repairing the first broken marketplace. Re-run the full reconciliation until every expected plugin is healthy or has a classified external blocker.

### 4. Inspect before mutation

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Restore-CodexPluginInventory.ps1 -InspectOnly
```

Review the proposed marketplace repairs and missing plugin-state restorations.

### 5. Repair safely

When the plan is correct, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Restore-CodexPluginInventory.ps1 -Repair -RestoreMissingPluginStates
```

The script must:

- back up `config.toml` before the first mutation;
- repair all detected known-official marketplace failures, not only `openai-primary-runtime`;
- replace a registered official root only when its current source is missing or lacks a valid manifest;
- refuse to overwrite a different, healthy marketplace source automatically;
- reinstall only plugins with strong prior-install evidence;
- preserve authentication, global state, unrelated marketplaces, and caches;
- verify the complete inventory again after repair.

For a broken Windows `openai-bundled` temporary root, prefer the valid marketplace bundled with the currently installed Codex package. Do not delete the temporary directory; re-register the official source and preserve rollback evidence.

### 6. Verify acceptance criteria

Require all applicable checks:

```powershell
codex plugin marketplace list
codex plugin list --available --json
codex login status
```

Then require:

- every strong-evidence plugin is installed/enabled or explicitly classified as account/server/UI managed;
- every registered local marketplace root exists and has a valid manifest;
- no repaired marketplace points to a partial temporary directory;
- the final expected count matches the evidence union;
- Codex Desktop is restarted once and the UI is checked separately.

Do not claim the online store is fixed from CLI success alone.

## Safety rules

- Default to inspection only.
- Back up before any configuration mutation.
- Never delete `~/.codex/plugins`, runtime caches, `auth.json`, or `.codex-global-state.json` as a generic fix.
- Never expose tokens, keys, cookies, emails, account IDs, or full logs.
- Never install every available marketplace plugin to compensate for missing history.
- Never treat cache presence alone as proof when the cache lacks a plugin manifest and no other evidence exists.
- Never replace a healthy custom marketplace with an official source merely because their names resemble each other.
- Keep provider/profile managers in a separate `CODEX_HOME` when they cannot preserve unknown TOML blocks.

## Reporting

Report:

- exact desktop and CLI versions and login mode without credentials;
- the evidence-derived total and plugin list;
- visible, restored, unresolved, and available-only counts separately;
- every marketplace root and integrity state;
- each change, backup path, and verification result;
- whether remaining failures are local, desktop-only, account/server-side, or intentionally filtered UI behavior.
