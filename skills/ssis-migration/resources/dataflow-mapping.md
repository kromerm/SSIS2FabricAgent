# Data Flow → Dataflow Gen2 (Power Query M) Mapping

When an SSIS Data Flow task contains **transformations** (not just a straight
source → destination), `converters/dataflow.py` converts it into a Fabric
**Dataflow Gen2** item whose query is a chain of Power Query **M** steps. A pure
source → destination Data Flow is converted to a pipeline **Copy** activity
instead (see [task-mapping.md](task-mapping.md)).

Each component becomes one M step. Every generated step carries a `// TODO`
annotation wherever a value cannot be derived automatically.

> **M syntax rule (critical):** a `// TODO` comment must NEVER sit **between the
> arguments of a function call** — in Power Query M, `//` runs to end of line, so
> an inline comment placed inside `Value.NativeQuery(Sql.Database(...) // TODO,
> "SELECT ...", null)` silently comments out the rest of the call (the SQL string
> and closing paren) and makes the whole query invalid. **Symptom:** the Dataflow
> Gen2 item fails to open/load in the Fabric editor. Place a TODO note on its own
> line or at end-of-line **after** the complete expression — never mid-call. The
> connection placeholders are now emitted as bare `Sql.Database("TODO_SERVER",
> "TODO_DATABASE")` (self-documenting, no inline comment).

---

## Component mapping

| SSIS Component | M Expression |
|---|---|
| OLE DB / ADO Source | `Value.NativeQuery(Source, sql)` |
| Flat File Source | `Csv.Document(File.Contents(...))` |
| Derived Column | `Table.AddColumn` |
| Aggregate | `Table.Group` |
| Sort | `Table.Sort` |
| Merge Join | `Table.NestedJoin` |
| Lookup | `Table.NestedJoin` (left outer) |
| Union All | `Table.Combine` |
| Data Conversion | `Table.TransformColumnTypes` |
| Pivot | `Table.Pivot` |
| Unpivot | `Table.UnpivotOtherColumns` |
| Conditional Split | `Table.SelectRows` |
| Destination | Comment only — actual load is done by the pipeline Copy activity |

---

## Source step details (DF-02)

- **OLEDB / ADO.NET source:** the M `Source` step uses `Sql.Database("server",
  "db")` followed by `Value.NativeQuery(Source, sql)` when a SQL statement is
  present. The server and database come from the resolved connection manager.
- **Flat File source:** `Csv.Document(File.Contents(...))`. Cloud Fabric cannot
  reach local file paths, so the file connection is flagged and the path is left
  as a TODO (configure an on-premises data gateway).

---

## Item definition encoding (DF-05)

The Dataflow Gen2 definition is **base64-encoded** and submitted as a Fabric item
definition with the correct `payloadType`. The CLI writes the decoded-friendly
JSON to `dataflow_<name>.json` when `--output-dir` is set; the `definition` block
inside contains the base64 payload that is sent to the API.

---

## What you must fix after migration

The generated M is a **scaffold**, not a finished query:

1. Open the Dataflow Gen2 item in Fabric.
2. Set a **real data source connection** (the converter uses placeholder
   server/db/credentials).
3. Walk every `// TODO` annotation — column lists, join keys, group-by keys,
   type maps, and filter predicates frequently need real values that don't exist
   in the SSIS metadata.
4. Confirm the destination is handled by the pipeline Copy activity (the M
   `Destination` step is intentionally a comment).

See [post-migration-checklist.md](post-migration-checklist.md) for the full
sequence.
