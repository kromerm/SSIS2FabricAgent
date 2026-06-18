# Connections, Authentication & Connection-less Shells

This is where most SSIS→Fabric migrations need human follow-up. Read this before
deploying.

---

## Connection manager → Fabric connection mapping

`converters/connections.py` maps SSIS connection types to Fabric connectivity
types. Every connection is created as a **`ShareableCloud`** connection with
**dummy/placeholder credentials** so the create call succeeds.

| SSIS Type | Fabric Type |
|---|---|
| OLEDB / ADO.NET | SQL (ShareableCloud) |
| File / Flat File | File |
| HTTP | Web (Anonymous) |
| FTP | FTP |
| SMTP / others | SQL (dummy) |

> **Credentials never migrate.** Server, database, and credentials must be set in
> **Fabric → Manage connections and gateways** after migration. This is
> especially true for **synthesized project-level connections**, whose real
> server/database live in the original `.conmgr` files and are emitted as `TODO`
> placeholders.

### Project-level connections

Real packages often reference connection managers defined in separate project
`.conmgr` files (e.g. `Project.ConnectionManagers[WWI_Source_DB]` /
`{GUID}:external`) rather than inside the `.dtsx`. The tool detects these
external references and **synthesizes** named Fabric connections for them so
activities reference real connections instead of placeholders (CONN-08).

### File connections are unreachable from the cloud

File / Flat File connections point at local paths that cloud Fabric cannot reach.
They are marked **unsupported**; the activity receives the placeholder connection
ID and you must configure an **on-premises data gateway** manually.

---

## Connection-less pipeline shells (the key pattern)

**Fabric validates every connection GUID referenced in a pipeline definition.**
A made-up placeholder GUID is rejected with a `400`/`updateDefinition` error — you
cannot ship a pipeline that points at a connection that does not exist.

`converters/pipeline.py` solves this by **omitting** the connection reference
whenever the resolved ID is the dummy sentinel:

```python
_DUMMY_CONNECTION_ID = "00000000-0000-0000-0000-000000000000"

def _is_real_conn(conn_id: str) -> bool:
    return bool(conn_id) and conn_id != _DUMMY_CONNECTION_ID

def _conn_ref(conn_id: str) -> Dict[str, Any]:
    # externalReferences block ONLY for a real connection id; else {}
    return {"externalReferences": {"connection": conn_id}} if _is_real_conn(conn_id) else {}
```

- **Real connection ID** → the activity gets
  `"externalReferences": {"connection": "<guid>"}`.
- **Dummy ID** → the `externalReferences` block is omitted entirely, producing a
  **connection-less shell** activity. The pipeline still validates, saves, and
  opens; the user picks a connection in the Fabric UI afterward.

This is what makes `--no-connections` and connection-create failures
**non-fatal**: the pipeline always deploys.

### When the dummy ID is used

1. `--no-connections` was passed.
2. A connection create call **failed** (the CLI logs `[warn] Using dummy
   connection ID` and continues).
3. The connection type is **unsupported** (e.g. File).

The completion summary's `Connections created` count excludes dummies, so it
tells you exactly how many activities still need a connection wired in.

---

## Authentication modes

`fabric/client.py` authenticates with `azure-identity`. Pick the mode that fits:

| Mode | Flag | Use when |
|---|---|---|
| Interactive browser (default) | *(none)* | Normal desktop use; a browser opens for sign-in. |
| Device code | `--device-code` | Headless/remote shells, or when a browser can't open. |
| Service principal | `--service-principal` | CI/automation. Requires `--tenant` + `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` env vars. |

### Tenant selection

Add `--tenant <guid>` when the workspace lives in a **non-default or personal
tenant**. Without it, login defaults to the account's home tenant and workspace
access fails (the first auth check is `get_or_create_folder`).

> **Secret hygiene:** never paste `AZURE_CLIENT_SECRET` into a command line that
> gets logged, and never commit `--verbose` logs — they can contain tokens. If a
> service-principal secret is ever exposed, rotate it.

---

## Dry-run has no auth

`--dry-run` builds all payloads with `DRY-RUN-CONN-ID` / `DRY-RUN-DF-ID`
placeholders and never authenticates. Use it freely to inspect output before a
live deploy.
