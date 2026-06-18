# Control Flow → Pipeline Activity Mapping

How `converters/pipeline.py` maps each SSIS control-flow task to a Fabric Data
Pipeline activity. A ⚠ means the activity is emitted with `state: InActive` and
must be reviewed/reactivated in Fabric.

| SSIS Task | Fabric Activity | Notes |
|---|---|---|
| Execute SQL Task | `Script` or `SqlServerStoredProcedure` | Stored-proc name detected automatically; ad-hoc SQL → `Script`. |
| Data Flow Task (pure source→destination) | `Copy` | Native Copy activity; source/sink tables + connections wired automatically. |
| Data Flow Task (with transforms) | `RefreshDataflow` | References the Dataflow Gen2 created for that task. |
| Expression Task (literal assignment) | `SetVariable` | Simple `@[User::Var] = "literal"`/number assignments translated, left **active**. |
| Expression Task (function-based) | `SetVariable` | ⚠ SSIS function expressions must be re-expressed in Fabric syntax. |
| ForEach Loop | `ForEach` | Inner tasks recursively converted. |
| For Loop Container | `Until` | ⚠ Loop expression becomes a TODO placeholder (SSIS vs Fabric expression syntax). |
| Sequence Container | `IfCondition` (always-true `@equals(1,1)` wrapper) | Inner tasks recursively converted. |
| Execute Package Task | `ExecutePipeline` | ⚠ Referenced pipeline may not exist yet. |
| Script Task | `Script` | ⚠ Logic must be manually ported. |
| Send Mail Task | `Office365Email` | ⚠ Connection required; From/To/CC/BCC/Subject/Body/Priority/Attachments populated. |
| Web Service Task | `WebActivity` (HTTP POST) | ⚠ SOAP endpoint URL, headers, envelope body must be updated. |
| FTP Task (Receive) | `Copy` (FTP → ADLS/lakehouse) | ⚠ Linked service + dataset config required. |
| FTP Task (Send) | `Copy` (ADLS/lakehouse → FTP) | ⚠ Linked service + dataset config required. |
| FTP Task (DeleteRemoteFile / DeleteLocalFile) | `Delete` | ⚠ Linked service config required. |
| FTP Task (directory ops / rename) | `Script` | ⚠ No direct Fabric equivalent. |
| Execute Process Task | `WebActivity` | ⚠ No direct equivalent. |
| File System Task | `Script` | ⚠ Rework using Lakehouse file APIs. |
| Bulk Insert Task | `Copy` | ⚠ Source/sink configuration required. |
| All others | `Wait` (1 s) | ⚠ Manual replacement required. |

---

## Disabled tasks

Any SSIS task with `DTS:Disabled="True"` is emitted as `state: InActive`, and its
`description` is prefixed with `[Disabled in original SSIS package]`.

---

## Variables → Pipeline parameters / variables

- `User::` variables that are **written** somewhere (Expression Task targets, For
  Loop counters, ForEach iterators) become mutable Fabric pipeline **variables**.
- `User::` variables that are only **read** become pipeline **parameters**.
- `System::` variables are skipped.

Type mapping:

| SSIS DataType | Fabric type |
|---|---|
| String, DateTime | `string` |
| Int32, Int64 | `int` |
| Double, Decimal | `float` |
| Boolean | `bool` |

---

## Precedence constraints → activity dependencies

SSIS precedence constraints (From/To/EvalOp/Value/Expression) become Fabric
activity `dependsOn` links. The parser resolves task identity by **both** GUID
and SSIS refId path (e.g. `Package\Task Name`), and reads constraints from both
top-level and container-scoped blocks, so nested ordering is preserved.

---

## Reading the result

After conversion, open the pipeline in Fabric and filter for the ⚠ (InActive)
badge. Each InActive activity's `description` field carries the original SSIS
task details needed to finish it. See
[post-migration-checklist.md](post-migration-checklist.md).
