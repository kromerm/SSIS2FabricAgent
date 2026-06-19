# Post-Migration Checklist & Troubleshooting

`ssis2fabric` bootstraps the migration; it does not finish it. Work this list
after a live deploy.

---

## Checklist

1. **Open the pipeline in Fabric** and find activities showing the ⚠ badge
   (`state: InActive`).
2. **For each InActive activity:**
   - Read the `description` field — it carries the original SSIS task details.
   - Update connection references, SQL statements, or script logic.
   - Set `state` back to `Active` once it's ready.
3. **Wire connections:**
   - Connection-less shell activities (no `externalReferences`) need a connection
     selected in the activity's settings.
   - Connections created with placeholder credentials need real server/database/
     credentials in **Fabric → Manage connections and gateways**.
   - File/Flat File sources need an **on-premises data gateway**.
4. **For each Dataflow Gen2 item:**
   - Set the real data source connection.
   - Resolve every `// TODO` in the M query (columns, join keys, group keys, type
     maps, filters).
5. **Run the pipeline in Debug mode** and iterate until green.

---

## Mapping the summary to work remaining

The completion summary counts **only real** items:

```
  Connections created        : N    ← activities with a real connection
  Dataflows created          : M    ← real Dataflow Gen2 items
```

Everything not counted is a connection-less shell or a placeholder — i.e., your
manual to-do list. A run that reports `Connections created : 0` deployed a
fully connection-less pipeline shell; that is expected and intentional, not a
failure.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `400 BadRequest` immediately | Malformed `--workspace-id` | The CLI pre-validates the 8-4-4-4-12 GUID; correct the value. |
| Auth / workspace access failed at "Resolving target folder" | Wrong tenant, or no access | Add `--tenant <guid>`; confirm Contributor+ on the workspace. |
| `updateDefinition` / connection validation error | A non-existent connection GUID in the definition | Expected to be handled by connection-less shells; if you hand-edited a GUID in, remove it or use a real one. |
| Connection create `FAIL`, run continues | Dummy credentials rejected, or transient API error | The CLI falls back to the dummy ID and emits a connection-less shell; wire the connection in Fabric. |
| Task parsed as `Unknown` / mapped to `Wait` | `DTS:CreationName` not recognized by the parser | No direct Fabric equivalent — replace the InActive `Wait`/`Script` activity by hand. |
| Dataflow M full of `// TODO` | Values not derivable from SSIS metadata | Fill in real columns/keys/types in the Dataflow Gen2 editor. |
| Dataflow Gen2 item won't open / load in the Fabric editor | Invalid Power Query M — most often a `// TODO` comment placed **inside** a function call (e.g. between `Sql.Database(...)` and the rest of `Value.NativeQuery`), which comments out the rest of the line | Fixed in `converters/dataflow.py` (placeholders are bare expressions, no inline comments). If hand-editing M, keep comments on their own line or at end-of-line **after** a complete expression — never mid-call. Decode and inspect `mashup.pq` from the item definition to confirm valid M. |
| Pipeline create failed but JSON exists | API rejected the final definition | Import `pipeline_<name>.json` from `--output-dir` manually in Fabric; re-run with `--verbose` to see the HTTP error. |

---

## Tips

- **Re-running the deploy is idempotent.** Items are matched by display name:
  an existing pipeline / dataflow / connection is **updated in place** (same
  GUID) rather than duplicated. So after fixing a converter bug or editing the
  package, just re-run the same command to push updated definitions over the
  existing items — no manual cleanup needed.
- Re-run **dry-run + `--output-dir`** after editing the package to diff the
  generated JSON before redeploying.
- Use `--no-dataflows` to iterate on the control-flow pipeline alone, then add
  dataflows once the pipeline is stable.
- Use `--no-connections` to deploy a pure connection-less shell when the target
  connections already exist in the workspace and you'll wire them in the UI.
- Keep `--verbose` logs out of source control — they can contain auth tokens.
