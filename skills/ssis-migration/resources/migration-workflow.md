# End-to-End Migration Workflow

Three phases: **parse & review → deploy → finish in Fabric.**

---

## Phase 1 — Parse & review (dry run)

Always start here. A dry run makes **no** Fabric API calls and requires **no**
authentication, so it is safe to run against any package.

```powershell
.venv\Scripts\python.exe -m ssis2fabric `
  --dtsx MyPackage.dtsx `
  --workspace-id 12c5e906-5bfc-4ba4-bd76-c1ce68fc53c8 `
  --dry-run `
  --output-dir dry_out\
```

### What to look at in the console summary

```
============================================================
  SSIS Package Summary
============================================================
  Package name   : MyPackage
  Variables      : 3
  Connections    : 2
  Top-level tasks: 5
  Data flows     : 1
  Precedence     : 4
```

- **Connections** — every connection manager becomes a Fabric connection (or a
  synthesized project-level connection). Note any that are File/SMTP/unsupported.
- **Top-level tasks** — cross-check against the task mapping in
  [task-mapping.md](task-mapping.md). Anything that maps to an InActive activity
  is manual follow-up.
- **Data flows** — each becomes either a Copy activity (pure source→sink) or a
  Dataflow Gen2 item (has transforms).

### What gets written to `--output-dir`

| File | Contents |
|---|---|
| `connections.json` | Array of Fabric connection creation payloads. |
| `dataflow_<name>.json` | Fabric Dataflow Gen2 item definition (base64 in the body). |
| `pipeline_<name>.json` | Fabric pipeline-content.json (base64-wrapped). |

Open `pipeline_<name>.json` and confirm the activity list, parameters, and
variables look right. Decode the base64 `payload` if you need to read the inner
pipeline definition.

Add `--verbose` to trace the parse/convert internals.

---

## Phase 2 — Deploy to Fabric

Once the dry-run output looks correct, drop `--dry-run` to create items live. A
browser opens for Microsoft Entra ID sign-in on first use.

```powershell
.venv\Scripts\python.exe -m ssis2fabric `
  --dtsx MyPackage.dtsx `
  --workspace-id 12c5e906-5bfc-4ba4-bd76-c1ce68fc53c8 `
  --tenant b3273975-61bb-4d27-9cb1-4df0bb8a0018 `
  --folder "SSIS Migration" `
  --output-dir deploy_out\
```

> Keep `--output-dir` on the live run too — if pipeline creation fails, the
> converted `pipeline_<name>.json` is still on disk and can be imported manually.

### Order of operations (from `cli.py`)

1. **Parse** the DTSX → `SSISPackage` model.
2. **Convert** connection + dataflow payloads (always, even in dry-run).
3. **Resolve folder** — `get_or_create_folder`; this is also the first auth check.
4. **Create connections** (unless `--no-connections`) → collect real GUIDs.
   - Unsupported (File, etc.) or failed creates fall back to the dummy GUID
     `00000000-0000-0000-0000-000000000000`.
5. **Create Dataflow Gen2 items** (unless `--no-dataflows`) → collect real GUIDs.
6. **Build the pipeline** with the resolved connection/dataflow GUIDs and
   **create** it. Real GUIDs become `externalReferences`; dummy GUIDs become
   **connection-less shells** (the reference is omitted so the definition still
   validates). See [connections-and-auth.md](connections-and-auth.md).

### Completion summary

```
============================================================
  Migration Complete
============================================================
  Pipeline 'MyPackage'   → <guid>
  Connections created        : N
  Dataflows created          : M
```

`Connections created` / `Dataflows created` count only **real** items (dummy
placeholders are excluded), so a low number is the signal for how much manual
wiring remains.

---

## Phase 3 — Finish in Fabric

Deployment is the start, not the end. Work through
[post-migration-checklist.md](post-migration-checklist.md): wire real
connections, reactivate InActive activities, and fix `// TODO` annotations in the
Dataflow Gen2 M queries.

---

## Useful variants

| Goal | Command tail |
|---|---|
| Pipeline only (wire dataflows by hand) | `--no-dataflows` |
| Use existing workspace connections | `--no-connections` |
| Override the pipeline name | `--pipeline-name "Daily Sales Load"` |
| Headless / no browser | `--device-code` |
| CI / automation | `--service-principal --tenant <guid>` (+ `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET`) |
