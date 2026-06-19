---
name: ssis-migration
description: >-
  Migrate SQL Server Integration Services (SSIS) .dtsx packages to Microsoft
  Fabric Data Factory using the ssis2fabric Python CLI. Parses an SSIS package
  and creates a Fabric Data Pipeline, Dataflow Gen2 items, and Shareable
  Connections via the Fabric REST API; tasks that cannot be auto-converted become
  InActive placeholders so the pipeline still saves and opens for manual fixup.
  Supports dry-run review, auth modes (interactive, device code, service
  principal), tenant override, and connection-less pipeline shells. Use when the
  user wants to: (1) convert an SSIS .dtsx control flow into a Fabric Data
  Pipeline, (2) translate SSIS Data Flow tasks into Dataflow Gen2 Power Query M
  or Copy activities, (3) map SSIS connection managers to Fabric connections and
  deploy the pipeline to a workspace, (4) dry-run and review a conversion before
  touching Fabric. Triggers: "migrate SSIS to Fabric", "ssis to fabric", "convert
  dtsx", "dtsx to fabric pipeline", "ssis2fabric", "port SSIS to Fabric Data
  Factory", "ssis dataflow gen2", "I have an SSIS package", "I have a package
  called", "move my package to Fabric".
---

> **Update Check — ONCE PER SESSION (mandatory)**
> The first time this skill is used in a session, run the **check-updates** skill before proceeding.
> - **GitHub Copilot CLI / VS Code**: invoke the `check-updates` skill.
> - **Claude Code / Cowork / Cursor / Windsurf / Codex**: compare local vs remote package.json version.
> - Skip if the check was already performed earlier in this session.

> **CRITICAL NOTES**
> 1. **Assume the user is an SSIS expert but new to Fabric.** Guide them — don't expect them to know workspace IDs, tenants, connections, or `.dtsx` paths up front. Run the intake interview and the readiness gate below before invoking the tool.
> 2. **If the user names a package but not its location** (e.g. "I have a package called Foobar"), locate it before asking the user: search the workspace for `Foobar.dtsx` (file search / glob). Confirm a single match, disambiguate multiple matches, and only ask for the path if none are found.
> 3. To find a Fabric workspace ID from its name: list all workspaces, then JMESPath-filter by `displayName`.
> 4. To find an item ID (pipeline / dataflow / connection): list items of that type in the workspace, then JMESPath-filter by name.
> 5. **Always `--dry-run --output-dir` first** — it parses and converts with NO Fabric API calls and NO auth. Review the JSON before any live run.
> 6. **Validate the `--workspace-id` GUID** (8-4-4-4-12). A malformed ID returns an opaque `400 BadRequest`.
> 7. **Connections never carry credentials.** Real connections are created with placeholder creds (or omitted as connection-less shells); the user MUST wire server / database / credentials in Fabric afterward.
> 8. **Non-default / personal tenants require `--tenant`**, or login defaults to the home tenant and workspace access fails.
> 9. **InActive activities are expected** — they are the manual follow-up list, not a failure; the pipeline still deploys.
> 10. **Re-deploys are idempotent** — items are matched by display name and updated in place (same GUID), never duplicated. After a converter fix or package edit, just re-run the same command to push updated definitions.
> 11. **Generated Dataflow Gen2 M must be valid Power Query** — never let a `// TODO` comment land **between** a function call's arguments (M `//` runs to end of line and silently truncates the call). A malformed mashup.pq makes the Dataflow fail to open in the Fabric editor.

# SSIS (.dtsx) → Microsoft Fabric Migration

## Context

This skill drives the **`ssis2fabric`** command-line tool that lives in this
repository. It reads a SQL Server Integration Services `.dtsx` package and
creates equivalent Microsoft Fabric Data Factory items in a target workspace via
the Fabric REST API.

| SSIS artifact | Fabric artifact |
|---|---|
| Package control flow | **Data Pipeline** |
| Data Flow task (pure source → destination) | **Copy activity** inside the pipeline |
| Data Flow task (with transforms) | **Dataflow Gen2** (Power Query M) |
| Connection Manager (package- *and* project-level) | **Fabric Shareable Connection** |

The guiding principle: **always produce a pipeline that saves and opens in
Fabric.** Any task that cannot be fully auto-converted is emitted with
`state: InActive` (a ⚠ badge in the Fabric UI) and a `description` that captures
the original SSIS task so an engineer can finish it by hand.

> This is a sibling of the [ssis-authoring](../ssis-authoring/SKILL.md) skill.
> `ssis-authoring` *creates* `.dtsx` packages (and test fixtures); **this** skill
> *migrates* an existing `.dtsx` package into Fabric. If the user wants to build
> a package or a converter test, use `ssis-authoring`. If they want to move a
> real package into a Fabric workspace, use this skill.

---

## Guided migration (act as the migration agent)

The typical user is **an SSIS developer who is new to Microsoft Fabric**. They
know their packages cold but may not know what a workspace ID, tenant, or Fabric
connection is. Do not dump CLI flags on them. Instead, **drive the migration
conversationally**: find out what they have, fill in the Fabric-side gaps
yourself, teach as you go, and only run the tool once the inputs are valid.

### Step 1 — Locate the package

When the user refers to a package by name without a path (e.g. *"I have a
package called CustomerLoad"*):

1. **Search before asking.** Glob the workspace for `*CustomerLoad*.dtsx`.
2. **One match** → confirm it: *"Found `CustomerLoad.dtsx` in `etl/` — use that?"*
3. **Multiple matches** → list them and ask which one.
4. **No match** → *then* ask for the full path, or offer to convert a package
   they point to outside the workspace.

### Step 2 — Intake interview (collect the required inputs)

Gather what the tool needs, resolving Fabric concepts on the user's behalf:

| Input | How to obtain it (don't just ask cold) |
|---|---|
| `.dtsx` path | Located in Step 1. |
| Target **workspace** | Ask for the workspace **name**, then resolve the GUID yourself (list workspaces → filter by `displayName`). |
| **Tenant** | Only raise if the workspace is in a personal / non-home tenant. Explain why it's needed. |
| **Auth mode** | Default to interactive browser login. Suggest `--device-code` for remote shells, `--service-principal` only for CI. |
| **Scope** | Ask whether to include connections and dataflows now, or stabilize the control-flow pipeline first (`--no-connections` / `--no-dataflows`). |

Translate Fabric concepts into SSIS terms as needed — e.g. *"a Dataflow Gen2 is
the Fabric equivalent of your Data Flow Task; a Fabric Connection is like a
Connection Manager, minus the stored credentials."*

### Step 3 — Readiness gate (before running Python)

Do **not** invoke the tool until all of these hold. If any fail, go back and
resolve it with the user:

- [ ] `.dtsx` file located and readable.
- [ ] Workspace **name resolved to a valid GUID** (8-4-4-4-12).
- [ ] Tenant decided (default vs. `--tenant`).
- [ ] Auth mode chosen.
- [ ] **Dry-run completed and reviewed** with the user (`--dry-run --output-dir`).

### Step 4 — Convert, then finish in Fabric

Run the live deploy, then walk the user through the post-migration list: wiring
connection credentials and reactivating InActive activities (these are expected —
frame them as the follow-up checklist, not a failure).

---

## Prerequisite Knowledge

Unlike the `az rest`-based Fabric skills, `ssis-migration` drives a
self-contained Python CLI that handles its own Microsoft Entra ID authentication
(via `azure-identity`) and all Fabric REST calls. There is therefore no
dependency on the shared `common/*-CORE.md` auth/CLI recipes. Reference material
lives in-repo:

- [README.md](../../README.md) — full tool usage, options, and SSIS→Fabric mapping tables.
- [specs/ssis2fabric-requirements.md](../../specs/ssis2fabric-requirements.md) — the product requirements / behavior contract.
- Source of truth for mappings: `ssis2fabric/parser.py`, `ssis2fabric/converters/*.py`, `ssis2fabric/fabric/client.py`.

---

## Must / Prefer / Avoid

### MUST DO
- **Dry-run first.** Run `--dry-run --output-dir <dir>`, read the package summary, and inspect the generated JSON before any live deploy.
- **Validate the workspace GUID** (8-4-4-4-12) before deploying; a malformed ID returns an opaque `400 BadRequest`.
- **Keep `--output-dir` on live runs too**, so a failed pipeline create still leaves an importable `pipeline_<name>.json` on disk.
- **Treat InActive activities and `// TODO` M steps as the post-migration checklist** — work [post-migration-checklist.md](resources/post-migration-checklist.md).

### PREFER
- **`--tenant <guid>`** whenever the workspace is in a non-default or personal tenant.
- **`--device-code`** for headless / remote shells; **`--service-principal`** (with `--tenant` + `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET`) for CI.
- **`--no-dataflows`** to stabilize the control-flow pipeline first, then add dataflows; **`--no-connections`** when the target connections already exist in the workspace.

### AVOID
- **Don't hand-edit real connection GUIDs into the pipeline definition** — Fabric validates every GUID; let the tool emit connection-less shells instead (see [connections-and-auth.md](resources/connections-and-auth.md)).
- **Don't commit `--verbose` logs** — they can contain auth tokens. If a service-principal secret is exposed, rotate it.
- **Don't expect credentials to migrate** — they never do; wire them in Fabric afterward.

---

## How to run the tool

Invoke via the module (works from a source checkout) or the console script
(after `pip install`):

```powershell
# From a source checkout using the repo virtual environment
.venv\Scripts\python.exe -m ssis2fabric --dtsx MyPackage.dtsx --workspace-id <guid> --dry-run --output-dir dry_out\

# After pip install
ssis2fabric --dtsx MyPackage.dtsx --workspace-id <guid> --folder "SSIS Migration"
```

Both forms behave identically (CLI-10).

---

## Migration workflow (3 phases)

1. **Parse & review** — dry-run, read the package summary, inspect the JSON.
2. **Deploy** — authenticate and create connections, dataflows, and the pipeline.
3. **Finish in Fabric** — wire connections and reactivate InActive activities.

Full step-by-step commands, expected output, and decision points are in
[migration-workflow.md](resources/migration-workflow.md).

---

## Table of contents

| Topic | Reference |
|---|---|
| End-to-end migration workflow (3 phases, commands, expected output) | [migration-workflow.md](resources/migration-workflow.md) |
| Control Flow task → Pipeline activity mapping | [task-mapping.md](resources/task-mapping.md) |
| Data Flow component → Dataflow Gen2 (Power Query M) mapping | [dataflow-mapping.md](resources/dataflow-mapping.md) |
| Connections, authentication, and connection-less shells | [connections-and-auth.md](resources/connections-and-auth.md) |
| Post-migration checklist & troubleshooting | [post-migration-checklist.md](resources/post-migration-checklist.md) |

---

## CLI flags (quick reference)

| Flag | Description |
|---|---|
| `--dtsx PATH` | **Required.** Path to the `.dtsx` file. |
| `--workspace-id GUID` | **Required.** Target Fabric workspace GUID. |
| `--tenant GUID` | Entra tenant to authenticate against (use for non-default/personal tenants). |
| `--device-code` | Device-code login instead of interactive browser. |
| `--service-principal` | SP auth; requires `--tenant` + `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET`. |
| `--folder NAME` | Place created items in a named workspace folder. |
| `--pipeline-name NAME` | Override the pipeline display name (default: SSIS package name). |
| `--dry-run` | Parse + convert, no Fabric API calls, no auth. |
| `--verbose` / `-v` | Print HTTP request/response details. |
| `--output-dir DIR` | Save converted JSON artifacts locally. |
| `--no-connections` | Skip connection creation (pipeline uses placeholder/omitted refs). |
| `--no-dataflows` | Skip Dataflow Gen2 creation. |

---

## Examples

**Dry-run review (no auth, no API calls):**

```powershell
.venv\Scripts\python.exe -m ssis2fabric `
  --dtsx MyPackage.dtsx `
  --workspace-id 12c5e906-5bfc-4ba4-bd76-c1ce68fc53c8 `
  --dry-run --output-dir dry_out\
```

**Live deploy into a folder, personal tenant, keeping local artifacts:**

```powershell
.venv\Scripts\python.exe -m ssis2fabric `
  --dtsx MyPackage.dtsx `
  --workspace-id 12c5e906-5bfc-4ba4-bd76-c1ce68fc53c8 `
  --tenant b3273975-61bb-4d27-9cb1-4df0bb8a0018 `
  --folder "SSIS Migration" --output-dir deploy_out\
```

**Connection-less pipeline shell (connections already exist in the workspace):**

```powershell
ssis2fabric --dtsx MyPackage.dtsx --workspace-id <guid> --no-connections
```

Full command variants and expected console output are in
[migration-workflow.md](resources/migration-workflow.md).

---

## When NOT to use this skill

- **Authoring a new `.dtsx` or a converter test fixture** → use
  [ssis-authoring](../ssis-authoring/SKILL.md).
- **Building Fabric pipelines from scratch** (not from SSIS) → use the Fabric
  data-factory authoring skills directly.
- **Migrating Synapse / Databricks / HDInsight Spark workloads** → use the
  dedicated `synapse-migration` / `databricks-migration` / `hdinsight-migration`
  skills.
