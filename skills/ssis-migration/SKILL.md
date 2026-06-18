---
name: ssis-migration
description: >-
  Migrate SQL Server Integration Services (SSIS) .dtsx packages to Microsoft
  Fabric Data Factory items using the ssis2fabric Python CLI in this repo. Parses
  an SSIS package and creates an equivalent Fabric Data Pipeline, Dataflow Gen2
  items, and Shareable Connections via the Fabric REST API. Tasks that cannot be
  fully auto-converted are emitted as InActive placeholders so the pipeline still
  saves and opens in Fabric for manual follow-up. Covers the dry-run review loop,
  authentication modes (interactive, device code, service principal, non-default
  tenant), connection-less pipeline shells, and the post-migration wiring
  checklist.
  WHEN: "migrate SSIS to Fabric", "convert a .dtsx", "port SSIS package to Fabric
  Data Factory", "ssis2fabric", "turn my SSIS package into a Fabric pipeline",
  "move SSIS control flow / data flow to Fabric", "deploy a converted SSIS
  pipeline to a Fabric workspace", "dry-run an SSIS conversion".
  Triggers: "ssis to fabric", "dtsx to fabric pipeline", "convert dtsx",
  "ssis2fabric run", "fabric data factory migration", "ssis dataflow gen2".
domain: ssis, dtsx, microsoft-fabric, data-factory, data-pipeline, dataflow-gen2, migration
source: ssis2fabric repo (cli.py, parser.py, converters/*.py, fabric/client.py, README.md, specs/ssis2fabric-requirements.md)
---

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

## Golden rules

1. **Always dry-run first.** `--dry-run --output-dir <dir>` parses, converts, and
   writes the JSON artifacts locally with **no** Fabric API calls and **no**
   authentication. Review the output before touching a live workspace.
2. **Validate the workspace GUID.** A malformed `--workspace-id` yields an opaque
   `400 BadRequest` from Fabric. The CLI pre-checks the 8-4-4-4-12 format.
3. **Connections rarely migrate cleanly.** SSIS credentials are never carried
   over. Connections are created with placeholder credentials (or omitted as
   connection-less shells); the user **must** wire real server/database/
   credentials in Fabric afterward. See
   [connections-and-auth.md](resources/connections-and-auth.md).
4. **Expect InActive activities.** Treat them as a TODO list, not a failure — the
   pipeline still deploys. See
   [post-migration-checklist.md](resources/post-migration-checklist.md).
5. **Non-default / personal tenants need `--tenant`.** Without it, interactive
   login defaults to the home tenant and workspace access fails.

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

## When NOT to use this skill

- **Authoring a new `.dtsx` or a converter test fixture** → use
  [ssis-authoring](../ssis-authoring/SKILL.md).
- **Building Fabric pipelines from scratch** (not from SSIS) → use the Fabric
  data-factory authoring skills directly.
- **Migrating Synapse / Databricks / HDInsight Spark workloads** → use the
  dedicated `synapse-migration` / `databricks-migration` / `hdinsight-migration`
  skills.
