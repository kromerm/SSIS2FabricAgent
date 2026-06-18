---
name: ssis-authoring
description: >-
  Author valid SSIS .dtsx packages on demand and assemble them into test
  fixtures for the ssis2fabric translator. Provides minimal, copy-pasteable
  DTSX fragments for connection managers, control-flow tasks, containers, data
  flows, variables, and precedence constraints — grounded in exactly what the
  ssis2fabric parser recognizes — plus a pytest harness pattern for asserting on
  the generated Fabric pipeline / dataflow / connection JSON.
  WHEN: "create an SSIS package", "author a .dtsx", "write an SSIS test
  fixture", "build a fixture for the translator", "make a DTSX that exercises
  X", "add a test for the SSIS converter", "generate an SSIS package with a
  Data Flow / FTP task / For Loop", "test the ssis2fabric utility".
domain: ssis, dtsx, microsoft-fabric, data-factory, testing
source: ssis2fabric repo (parser.py, converters/*.py, specs/ssis2fabric-requirements.md)
---

# SSIS Authoring & Translator Test Fixtures

## Context

This skill does two things, in priority order:

1. **Author valid SSIS `.dtsx` packages from scratch.** Emit correct SSIS XML
   for any construct the translator cares about.
2. **Use those packages as test fixtures** for the `ssis2fabric` Python
   translator — drive them through the converter and assert on the Fabric JSON
   that comes out.

The single most important rule: **authored XML must match the exact strings the
parser keys on.** The parser ([ssis2fabric/parser.py](../../ssis2fabric/parser.py))
matches case-insensitive substrings of `DTS:CreationName`, connection
`CreationName`, data-flow `componentClassID`, and `DTS:Variable` `DataType`
codes. If a fragment uses the wrong `CreationName`, the task silently parses as
`Unknown` and the fixture proves nothing.

Everything below is grounded in the real parser and converters. When in doubt,
re-read [parser.py](../../ssis2fabric/parser.py),
[converters/connections.py](../../ssis2fabric/converters/connections.py),
[converters/dataflow.py](../../ssis2fabric/converters/dataflow.py), and
[converters/pipeline.py](../../ssis2fabric/converters/pipeline.py).

### Parser-valid is NOT the same as designer-valid (BIDS-load rule)

The Python parser is **lenient**; the real Visual Studio SSIS (BIDS) designer is
**strict**. A fixture that parses cleanly can still fail to open in VS with
`0xC001001D` ("expected attribute not found" — `CPackage::LoadFromXML` failed).
If an authored package must also open in the designer, follow these rules:

- **Never invent a `DTS:`-namespaced element.** The loader tries to parse every
  element in the `DTS` namespace as a *known* structural element and rejects it
  for a missing required attribute. Example of the trap: a made-up
  `<DTS:HttpConnectionManager DTS:ServerURL=...>` breaks the load — the real
  element is `<DTS:HttpConnection>` (with the URL on a `DTS:ServerURL`
  **attribute**), there is no `HttpConnectionManager`. Task data and connection
  sub-elements that aren't core DTS structure live in their **own task
  namespace** (e.g. `...dts/tasks/webservicetask`, `...dts/tasks/sendmailtask`).
- **Use the authentic, namespaced task-data form**, not a bare scaffold element.
  Real SSIS emits `SendMailTask:SendMailTaskData`, `WebServiceTaskData` (in the
  webservicetask namespace), etc. The parser was updated (`_local_attrs` /
  `_find_by_localname`) to read **both** the authentic namespaced forms and the
  bare scaffold forms, so prefer the authentic form — it parses AND loads.
- **Declare every variable a task references.** If a Web Service / Script task
  writes `User::WeatherJson`, add a matching `<DTS:Variable>`; an undeclared
  reference is an unresolved-reference load error.
- **Give each task host the standard attributes** the designer expects:
  `DTS:refId`, `DTS:CreationName` **and** `DTS:ExecutableType`, plus an empty
  `<DTS:Variables />` child. Precedence constraints load most reliably with
  refId paths (`Package\Task Name`) plus `DTS:LogicalAnd="True"`.

`WeatherToEmail.dtsx` at the repo root is the reference package that satisfies
**both** the translator and the BIDS designer.


---

## DTSX anatomy

### Namespaces

```text
DTS       = www.microsoft.com/SqlServer/Dts
SQLTask   = www.microsoft.com/sqlserver/dts/tasks/sqltask
pipeline  = www.microsoft.com/SqlServer/Dts/Pipeline
```

The parser reads attributes three ways, in order (`_attr` in parser.py):

1. `DTS:<Name>` attribute (new format)
2. bare `<Name>` attribute
3. `<DTS:Property DTS:Name="<Name>">value</DTS:Property>` child (old format)

So **new-format** packages put everything on attributes; **old-format** packages
use `DTS:Property` child elements. The parser handles both. Prefer **new format**
for fixtures — it is terser and what modern SSDT emits.

### Minimal package skeleton (new format)

```xml
<?xml version="1.0"?>
<DTS:Executable xmlns:DTS="www.microsoft.com/SqlServer/Dts"
                DTS:ExecutableType="Microsoft.Package"
                DTS:ObjectName="MyPackage"
                DTS:DTSID="{11111111-1111-1111-1111-111111111111}">
  <DTS:ConnectionManagers>
    <!-- connection manager fragments -->
  </DTS:ConnectionManagers>
  <DTS:Variables>
    <!-- variable fragments -->
  </DTS:Variables>
  <DTS:Executables>
    <!-- task / container fragments -->
  </DTS:Executables>
  <DTS:PrecedenceConstraints>
    <!-- precedence fragments -->
  </DTS:PrecedenceConstraints>
</DTS:Executable>
```

### Identity rules

- Every `DTS:DTSID` is a brace-wrapped GUID; the parser strips braces.
- Make each `DTSID` **unique** — duplicate IDs collide in precedence resolution.
- The parser resolves precedence by **both** GUID and SSIS refId path
  (`Package\Task Name`), so the `DTS:ObjectName` you give a task is also its
  addressable path segment.

---

## Connection managers

The parser reads `CreationName` into `connection_type`. The converter
([connections.py](../../ssis2fabric/converters/connections.py)) maps it to a
Fabric type by **case-insensitive substring** (`_CONN_TYPE_MAP`):

| SSIS `CreationName` substring | Fabric type | Credential | Requirement |
|---|---|---|---|
| `OLEDB` | SQL | Basic | CONN-01 |
| `ADO.NET` | SQL | Basic | CONN-01 |
| `SQLSERVER` | SQL | Basic | CONN-01 |
| `FILE` | File | Anonymous | CONN-02 |
| `FLATFILE` | File | Anonymous | CONN-02 |
| `HTTP` | HTTP/Web | Anonymous | CONN-03 |
| `FTP` | FTP | Anonymous | CONN-04 |
| `SMTP` | dummy SQL (`skipTestConnection`) | — | CONN-05 |
| `EXCEL`, `ACCESS`, `ODBC`, `XML`, `CACHE` | (see map) | — | — |

### OLEDB / SQL connection

```xml
<DTS:ConnectionManager DTS:ObjectName="LocalDB"
                       DTS:DTSID="{22222222-0000-0000-0000-000000000001}"
                       DTS:CreationName="OLEDB">
  <DTS:ObjectData>
    <DTS:ConnectionManager
        DTS:ConnectionString="Data Source=localhost;Initial Catalog=AdventureWorks;Provider=SQLNCLI11;Integrated Security=SSPI;" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

The parser extracts `server_name` from `Data Source=` and `database_name` from
`Initial Catalog=` via regex.

### Flat File / File connection

```xml
<DTS:ConnectionManager DTS:ObjectName="OrdersCsv"
                       DTS:DTSID="{22222222-0000-0000-0000-000000000002}"
                       DTS:CreationName="FLATFILE">
  <DTS:ObjectData>
    <DTS:ConnectionManager DTS:ConnectionString="C:\data\orders.csv" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

### HTTP connection

```xml
<DTS:ConnectionManager DTS:ObjectName="ApiEndpoint"
                       DTS:DTSID="{22222222-0000-0000-0000-000000000003}"
                       DTS:CreationName="HTTP">
  <DTS:ObjectData>
    <DTS:ConnectionManager DTS:ConnectionString="https://api.example.com/data">
      <DTS:HttpConnection DTS:ServerURL="https://api.example.com/data" />
    </DTS:ConnectionManager>
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

> **BIDS:** an HTTP connection manager saved by the designer nests an inner
> `<DTS:ConnectionManager DTS:ConnectionString="<url>">` inside `ObjectData`,
> and that wrapper holds a single `<DTS:HttpConnection>` element (in the **DTS
> namespace**, with the `DTS:` prefix) whose **`DTS:ServerURL` attribute**
> carries the URL. Mirror the same URL in both `DTS:ConnectionString` and
> `DTS:ServerURL`. `<DTS:HttpConnection>` **is** a valid node in this exact
> position — the `0xC0010014` failures come from putting the URL in a
> `<DTS:Property DTS:Name="ServerURL">` child, or from `<HttpConnection>` nodes
> placed outside the inner `<DTS:ConnectionManager>` wrapper. When the designer
> writes this CM it also emits two **encrypted** `<DTS:Property>` children
> (`ServerPassword`, `ProxyPassword`) under `EncryptSensitiveWithUserKey`; those
> are DPAPI blobs you must **not** hand-author (empty or foreign
> `Encrypted="1"` text aborts the load). For a scaffold / anonymous endpoint,
> set the **package** `DTS:ProtectionLevel="0"` (DontSaveSensitive) so the
> loader does not expect those encrypted blobs, and omit the password
> `<DTS:Property>` children entirely. Do **not** place an `<HttpConnection>`
> node in the `webservicetask` namespace either. The parser reads the URL from
> the `DTS:ServerURL` attribute (local-name match on
> `HttpConnection`/`HttpClientConnection`) first, then falls back to the
> `ConnectionString` and, for older hand-authored fixtures, a `ServerURL`
> property element.

### FTP connection

The FTP branch reads the server from `cm.server_name`, `cm.url`,
`properties["ServerName"]`, or a `ServerName=...` token in the connection
string. The most reliable fixture form sets a `DTS:ServerName` attribute **and**
a matching `ServerName=` token in the connection string:

```xml
<DTS:ConnectionManager DTS:ObjectName="Ftp_Server"
                       DTS:DTSID="{22222222-0000-0000-0000-000000000004}"
                       DTS:CreationName="FTP">
  <DTS:ObjectData>
    <DTS:ConnectionManager DTS:ServerName="ftp.example.com"
        DTS:ConnectionString="ServerName=ftp.example.com;ServerPort=21;" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

### SMTP connection (falls through to dummy SQL — CONN-05)

```xml
<DTS:ConnectionManager DTS:ObjectName="MailServer"
                       DTS:DTSID="{22222222-0000-0000-0000-000000000005}"
                       DTS:CreationName="SMTP">
  <DTS:ObjectData>
    <DTS:ConnectionManager DTS:ConnectionString="SmtpServer=smtp.example.com;UseWindowsAuthentication=False;" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

---

## Variables

`User::` variables are extracted; `System::` variables are silently skipped.
`DataType` is a numeric code (`_parse_variables` map):

| Code | Type | Fabric param type |
|---|---|---|
| 3 | Int32 | int |
| 5 | Double | float |
| 7 | DateTime | string |
| 8 | String | string |
| 11 | Boolean | bool |
| 14 | Decimal | float |
| 16 | SByte | int |
| 17 | Byte | int |
| 18 | Short | int |
| 19 | UInt16 | int |
| 20 | Int64 | int |

```xml
<DTS:Variable DTS:ObjectName="Counter" DTS:Namespace="User"
              DTS:DTSID="{33333333-0000-0000-0000-000000000001}"
              DTS:DataType="3">
  <DTS:VariableValue DTS:DataType="3">0</DTS:VariableValue>
</DTS:Variable>
```

**Variable vs parameter split** (build_pipeline_content): a User variable that is
*written* anywhere becomes a mutable Fabric **variable** (typed String, or
Boolean); a read-only one becomes a **parameter**. A variable counts as written
if it is a For Loop counter, an Expression Task target (`@[User::X] = ...`), or a
ForEach iterator variable. Author both a written and a read-only variable when a
fixture needs to prove the split.

---

## Control-flow tasks

Each task is a `DTS:Executable` inside `<DTS:Executables>`. The parser derives
the task type from `DTS:CreationName` (or, old format,
`DTS:ExecutableType`) via case-insensitive substring (`_task_type_from_ref`).

| `CreationName` contains | Task type | Translator activity | State |
|---|---|---|---|
| `Microsoft.ExecuteSQLTask` | ExecuteSQL | Script / SqlServerStoredProcedure | InActive |
| `Microsoft.DataFlowTask` / `DTS.Pipeline` | DataFlow | RefreshDataFlow (Gen2) **or** Copy | Gen2: Active · Copy: none |
| `Microsoft.ScriptTask` | Script | Script | InActive |
| `Microsoft.SendMailTask` | SendMail | Office365Email | InActive |
| `Microsoft.WebServiceTask` | WebService | WebActivity | InActive |
| `Microsoft.FTPTask` | FTP | Copy / Delete / Script | InActive |
| `Microsoft.ExpressionTask` | Expression | SetVariable | InActive |
| `Microsoft.ExecutePackageTask` | ExecutePackage | ExecutePipeline | InActive |
| `Microsoft.ExecuteProcessTask` | ExecuteProcess | WebActivity | InActive |
| `Microsoft.FileSystemTask` | FileSystem | Script | InActive |
| `Microsoft.BulkInsertTask` | BulkInsert | Copy | InActive |
| `STOCK:FOREACHLOOP` | ForEachLoop | ForEach | Active |
| `STOCK:FORLOOP` | ForLoop | Until | InActive |
| `STOCK:SEQUENCE` | Sequence | IfCondition (always-true) | Active |

### Execute SQL

```xml
<DTS:Executable DTS:ExecutableType="Microsoft.ExecuteSQLTask"
                DTS:ObjectName="Truncate Staging"
                DTS:DTSID="{44444444-0000-0000-0000-000000000001}">
  <DTS:ObjectData>
    <SQLTask:SqlTaskData
        xmlns:SQLTask="www.microsoft.com/sqlserver/dts/tasks/sqltask"
        SQLTask:Connection="{22222222-0000-0000-0000-000000000001}"
        SQLTask:SqlStatementSource="TRUNCATE TABLE stg.Orders;" />
  </DTS:ObjectData>
</DTS:Executable>
```

### Expression Task (→ SetVariable)

The expression text must be `@[User::Target] = <expr>`. The converter splits on
the first `=` to get the target variable and the value expression. The parser
reads the expression from the **element text** of an `<ExpressionTask>` (or
`<Expression>`) child — **not** from an attribute.

```xml
<DTS:Executable DTS:ExecutableType="Microsoft.ExpressionTask"
                DTS:ObjectName="Increment Counter"
                DTS:DTSID="{44444444-0000-0000-0000-000000000002}">
  <DTS:ObjectData>
    <ExpressionTask xmlns="www.microsoft.com/sqlserver/dts/tasks/expressiontask">@[User::Counter] = @[User::Counter] + 1</ExpressionTask>
  </DTS:ObjectData>
</DTS:Executable>
```

The parser pulls expression text from any child whose tag ends with
`ExpressionTask` or `Expression`, into `props["expression"]`. (Putting it in an
attribute will **not** be picked up.)

### FTP Task

The element must be `<FTPTaskData>` (the parser matches any tag ending in
`FTPTaskData`). Set `Connection` to an FTP connection manager's `DTSID` to wire
it up.

```xml
<DTS:Executable DTS:ExecutableType="Microsoft.FTPTask"
                DTS:ObjectName="Download File"
                DTS:DTSID="{44444444-0000-0000-0000-000000000003}">
  <DTS:ObjectData>
    <FTPTaskData xmlns="www.microsoft.com/sqlserver/dts/tasks/ftptask"
                 Operation="Receive"
                 RemotePath="/in/orders.csv"
                 LocalPath="C:\data"
                 Connection="{22222222-0000-0000-0000-000000000004}" />
  </DTS:ObjectData>
</DTS:Executable>
```

### Web Service Task (→ WebActivity)

Use the authentic `WebServiceTaskData` in the **webservicetask** namespace with
a child `<ServiceInfo>`. `ConnectionName` points at the HTTP connection manager
by **name**; `OutPutLocation` is the target variable (declare it). The parser
also accepts a bare scaffold form, but this one also loads in BIDS.

```xml
<DTS:Executable DTS:refId="Package\Get Weather"
                DTS:CreationName="Microsoft.WebServiceTask"
                DTS:ExecutableType="Microsoft.WebServiceTask"
                DTS:ObjectName="Get Weather"
                DTS:DTSID="{44444444-0000-0000-0000-00000000000A}"
                DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ObjectData>
    <WebServiceTaskData
        xmlns="www.microsoft.com/sqlserver/dts/tasks/webservicetask"
        ConnectionName="ApiEndpoint"
        WSDLFile=""
        OutputType="Variable"
        OutPutLocation="User::WeatherJson">
      <ServiceInfo ServiceName="Forecast" MethodName="GetCurrentWeather" />
    </WebServiceTaskData>
  </DTS:ObjectData>
</DTS:Executable>
```

### Send Mail Task (→ Office365Email)

Use `SendMailTask:SendMailTaskData` with `SendMailTask:`-prefixed attributes.
`MessageSourceType` is `DirectInput` / `FileConnection` / `Variable`. The parser
maps `To`/`Subject`/`MessageSource` into the Fabric Office 365 email activity.

```xml
<DTS:Executable DTS:refId="Package\Send Notification"
                DTS:CreationName="Microsoft.SendMailTask"
                DTS:ExecutableType="Microsoft.SendMailTask"
                DTS:ObjectName="Send Notification"
                DTS:DTSID="{44444444-0000-0000-0000-00000000000B}"
                DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ObjectData>
    <SendMailTask:SendMailTaskData
        xmlns:SendMailTask="www.microsoft.com/sqlserver/dts/tasks/sendmailtask"
        SendMailTask:SMTPServer="MailServer"
        SendMailTask:From="alerts@contoso.com"
        SendMailTask:To="ops@contoso.com"
        SendMailTask:Priority="Normal"
        SendMailTask:MessageSourceType="DirectInput"
        SendMailTask:Subject="Job complete"
        SendMailTask:MessageSource="The job finished successfully." />
  </DTS:ObjectData>
</DTS:Executable>
```

### Disabled task (→ InActive, description prefixed)

Set `DTS:Disabled="True"`. The parser records it; the converter emits
`state: InActive`, `onInactiveMarkAs: Succeeded`, and prefixes the description
with `[Disabled in original SSIS package]`.

```xml
<DTS:Executable DTS:ExecutableType="Microsoft.ScriptTask"
                DTS:ObjectName="Legacy Hook"
                DTS:Disabled="True"
                DTS:DTSID="{44444444-0000-0000-0000-000000000004}" />
```

---

## Containers

Containers nest `<DTS:Executables>` (and may carry their own
`<DTS:PrecedenceConstraints>`). The parser recurses into ForEach Loop, For Loop,
and Sequence.

### Sequence

```xml
<DTS:Executable DTS:ExecutableType="STOCK:SEQUENCE"
                DTS:ObjectName="Load Group"
                DTS:DTSID="{55555555-0000-0000-0000-000000000001}">
  <DTS:Executables>
    <!-- inner tasks -->
  </DTS:Executables>
</DTS:Executable>
```

### For Loop

```xml
<DTS:Executable DTS:ExecutableType="STOCK:FORLOOP"
                DTS:ObjectName="Retry Loop"
                DTS:DTSID="{55555555-0000-0000-0000-000000000002}"
                DTS:InitExpression="@Counter = 0"
                DTS:EvalExpression="@Counter &lt; 5"
                DTS:AssignExpression="@Counter = @Counter + 1">
  <DTS:Executables>
    <!-- inner tasks -->
  </DTS:Executables>
</DTS:Executable>
```

### ForEach Loop

```xml
The enumerator kind is read from the `ForEachEnumerator`'s `CreationName` (a
substring of `File` / `ADO` / `NodeList` / `Item`). The iterator variable comes
from a `ForEachVariableMapping`'s `VariableName`.

```xml
<DTS:Executable DTS:ExecutableType="STOCK:FOREACHLOOP"
                DTS:ObjectName="Per File"
                DTS:DTSID="{55555555-0000-0000-0000-000000000003}">
  <DTS:ForEachEnumerator DTS:CreationName="Microsoft.ForEachFileEnumerator">
    <DTS:ObjectData>
      <ForEachFileEnumerator
          xmlns="www.microsoft.com/sqlserver/dts/tasks/foreachfileenumerator"
          Folder="C:\in" FileSpec="*.csv" />
    </DTS:ObjectData>
  </DTS:ForEachEnumerator>
  <DTS:ForEachVariableMappings>
    <DTS:ForEachVariableMapping DTS:VariableName="User::CurrentFile" />
  </DTS:ForEachVariableMappings>
  <DTS:Executables>
    <!-- inner tasks -->
  </DTS:Executables>
</DTS:Executable>
```

---

## Precedence constraints

Reference the `From`/`To` tasks by **`DTSID`** (proven form) or by SSIS refId
path (`Package\<Task ObjectName>`) — the converter resolves either.

```xml
<DTS:PrecedenceConstraint DTS:ObjectName="A -> B"
                          DTS:DTSID="{66666666-0000-0000-0000-000000000001}"
                          DTS:From="{44444444-0000-0000-0000-000000000001}"
                          DTS:To="{44444444-0000-0000-0000-000000000002}"
                          DTS:EvalOp="0"
                          DTS:Value="0" />
```

- `EvalOp`: `0`=Constraint, `1`=Expression, `2`=Expression **and** Constraint,
  `3`=Expression **or** Constraint.
- `Value`: `0`=Success, `1`=Failure, `2`=Completion → Fabric `dependsOn`
  conditions Succeeded / Failed / Completed.

---

## Data flows (the high-value, tricky part)

A Data Flow task wraps a `<pipeline>` with `<components>` and `<paths>`. The
parser reads `componentClassID`, the property bag, connection refs, and
input/output columns. The classifier
([dataflow.py](../../ssis2fabric/converters/dataflow.py) `_classify_component`)
labels each component **source / destination / transform** by:

1. **GUID lookup** (old-format class IDs) — see `_GUID_CATEGORY`.
2. **Class-name substring** — e.g. `Microsoft.OLEDBSource`,
   `Microsoft.OLEDBDestination`, `Microsoft.DerivedColumn`.
3. **Component-name heuristics** — name contains `source`/`reader`→source,
   `destination`/`dest`/`writer`/`load`→destination.

### Copy-candidate routing (important for fixtures)

`is_copy_candidate(df)` is **true** when the flow has exactly **1 source, 1
destination, and 0 transforms**. Such flows are **skipped** by the Gen2
converter and emitted as a native **Copy** activity in the pipeline instead. Add
even one transform component to force the **Dataflow Gen2** path.

### Pure copy flow (source → destination, no transforms → Copy activity)

```xml
<DTS:Executable DTS:ExecutableType="Microsoft.DataFlowTask"
                DTS:ObjectName="Copy Orders"
                DTS:DTSID="{77777777-0000-0000-0000-000000000001}">
  <DTS:ObjectData>
    <pipeline xmlns="www.microsoft.com/SqlServer/Dts/Pipeline">
      <components>
        <component id="1" name="OLE DB Source"
                   componentClassID="Microsoft.OLEDBSource">
          <connections>
            <connection connectionManagerID="{22222222-0000-0000-0000-000000000001}" />
          </connections>
          <properties>
            <property name="OpenRowset">dbo.Orders</property>
          </properties>
          <outputs>
            <output><outputColumns>
              <outputColumn id="11" name="OrderID" dataType="i4" />
            </outputColumns></output>
          </outputs>
        </component>
        <component id="2" name="OLE DB Destination"
                   componentClassID="Microsoft.OLEDBDestination">
          <connections>
            <connection connectionManagerID="{22222222-0000-0000-0000-000000000001}" />
          </connections>
          <properties>
            <property name="OpenRowset">stg.Orders</property>
          </properties>
        </component>
      </components>
      <paths>
        <path id="100" name="p" startId="1" endId="2" />
      </paths>
    </pipeline>
  </DTS:ObjectData>
</DTS:Executable>
```

### Transforming flow (source → derived column → destination → Dataflow Gen2)

Insert a transform between source and destination so `is_copy_candidate` is
false:

```xml
<component id="3" name="Derived Column"
           componentClassID="Microsoft.DerivedColumn">
  <properties>
    <property name="Expression">UPPER([City])</property>
  </properties>
</component>
```

…and add paths `1→3` and `3→2`.

---

## Assembling a fixture

A good fixture is **minimal and targeted**: include only the constructs needed
to exercise the code path under test, plus the one or two supporting pieces they
require (e.g. a connection a Data Flow references). Keep GUIDs unique and
human-trackable (the prefix-per-category scheme above helps).

Put fixtures in `tests/fixtures/<name>.dtsx`. One already exists:
[tests/fixtures/tier1_fixture.dtsx](../../tests/fixtures/tier1_fixture.dtsx)
(FTP connection + Expression Task + pure-copy Data Flow + written/read-only
variables).

---

## Testing the translator with a fixture

### Quick dry-run (no auth, writes JSON artifacts)

```powershell
python -m ssis2fabric --dtsx tests/fixtures/<name>.dtsx `
  --workspace-id 00000000-0000-0000-0000-000000000000 `
  --dry-run --output-dir <out_dir>
```

Artifacts written:

| File | Contents |
|---|---|
| `pipeline_<PackageObjectName>.json` | item definition; one base64 part `pipeline-content.json` |
| `connections.json` | array of connection payloads |
| `dataflow_<name>.json` | Dataflow Gen2 item def (parts `queryMetadata.json` + `mashup.pq`) |

Note: the pipeline file is named after the package's `DTS:ObjectName`, **not**
the `.dtsx` filename (e.g. a package named `Tier1Fixture` →
`pipeline_Tier1Fixture.json`).

### pytest harness — two layers

Use **direct function calls** for precise unit assertions and a few **dry-run +
decode** smoke tests for end-to-end coverage. A `conftest.py` helper keeps it
DRY.

```python
# tests/conftest.py
import base64, json, subprocess, sys
from pathlib import Path
import pytest

from ssis2fabric.parser import parse_dtsx
from ssis2fabric.converters.pipeline import build_pipeline_content

FIXTURES = Path(__file__).parent / "fixtures"
DUMMY_WS = "00000000-0000-0000-0000-000000000000"


@pytest.fixture
def pipeline_content():
    """Parse a fixture and build pipeline-content.json as a dict (direct call)."""
    def _build(fixture_name, conn_id_map=None, df_id_map=None):
        pkg = parse_dtsx(str(FIXTURES / fixture_name))
        return build_pipeline_content(
            pkg, conn_id_map or {}, df_id_map or {}, DUMMY_WS
        )
    return _build


def decode_part(item_def: dict, path: str) -> str:
    """Return the decoded text of a named base64 part from an item definition."""
    for part in item_def["definition"]["parts"]:
        if part["path"] == path:
            return base64.b64decode(part["payload"]).decode("utf-8")
    raise KeyError(path)


def run_dry(tmp_path, fixture_name) -> Path:
    """Run the CLI in dry-run mode; return the output dir."""
    out = tmp_path / "out"
    subprocess.run(
        [sys.executable, "-m", "ssis2fabric",
         "--dtsx", str(FIXTURES / fixture_name),
         "--workspace-id", DUMMY_WS, "--dry-run",
         "--output-dir", str(out)],
        check=True, capture_output=True, text=True,
    )
    return out
```

#### Layer 1 — direct-call unit test

```python
def test_expression_task_becomes_setvariable(pipeline_content):
    content = pipeline_content("tier1_fixture.dtsx")
    acts = {a["name"]: a for a in content["properties"]["activities"]}
    inc = acts["Increment Counter"]
    assert inc["type"] == "SetVariable"
    assert inc["state"] == "InActive"


def test_written_var_is_variable_not_parameter(pipeline_content):
    content = pipeline_content("tier1_fixture.dtsx")["properties"]
    assert "Counter" in content["variables"]      # written → mutable variable
    assert "Threshold" in content["parameters"]   # read-only → parameter


def test_pure_copy_flow_is_copy_activity(pipeline_content):
    content = pipeline_content("tier1_fixture.dtsx")
    acts = {a["name"]: a for a in content["properties"]["activities"]}
    assert acts["Copy Orders"]["type"] == "Copy"
    # A Copy activity emitted from an enabled flow carries no explicit "state"
    # key (it defaults to active); only disabled tasks get state == "InActive".
    assert acts["Copy Orders"].get("state") is None
```

#### Layer 2 — dry-run + decode smoke test

```python
def test_dry_run_emits_decodable_pipeline(tmp_path):
    out = run_dry(tmp_path, "tier1_fixture.dtsx")
    # Artifact is named after the package ObjectName — glob to stay robust.
    pipeline_file = next(out.glob("pipeline_*.json"))
    item_def = json.loads(pipeline_file.read_text())
    content = json.loads(decode_part(item_def, "pipeline-content.json"))
    names = [a["name"] for a in content["properties"]["activities"]]
    assert "Copy Orders" in names
```

For a Dataflow Gen2 fixture, decode the `mashup.pq` and `queryMetadata.json`
parts the same way and assert on the M text (e.g. `Sql.Database`,
`Value.NativeQuery`, or `// TODO` for steps needing manual fix-up).

---

## Construct → translator behavior cheat-sheet

When authoring a fixture, know what each construct *should* produce so the
assertions are meaningful:

- **OLEDB/ADO.NET CM** → SQL connection (Basic creds).
- **FTP CM** → FTP connection (server from `ServerName=`).
- **SMTP / unknown CM** → dummy SQL, `skipTestConnection: true`.
- **Expression Task** → `SetVariable`, InActive, target split on first `=`.
- **Pure copy Data Flow (1src/1dst/0xform)** → `Copy` (no explicit `state`).
- **Data Flow with ≥1 transform** → Dataflow Gen2 (`mashup.pq` + `queryMetadata.json`).
- **Written User var** → mutable pipeline `variable` (String/Boolean).
- **Read-only User var** → pipeline `parameter` (typed by DataType).
- **`DTS:Disabled="True"`** → InActive, description prefixed `[Disabled in original SSIS package]`.
- **For Loop** → `Until`, InActive (condition is a TODO).
- **Sequence** → `IfCondition` always-true, Active.
- **ForEach Loop** → `ForEach`, Active, inner activities recursed.

---

## Anti-patterns

- ✗ **Wrong `CreationName`.** `DTS:ExecutableType="ExecuteSQL"` parses as
  `Unknown`. Use the full `Microsoft.ExecuteSQLTask`.
- ✗ **Duplicate `DTSID`s.** Breaks precedence resolution; always unique GUIDs.
- ✗ **Expecting a Copy activity from a flow with a transform.** Any transform
  flips it to the Dataflow Gen2 path. Conversely, a 1-source/1-dest/0-transform
  flow will **not** produce a Gen2 dataflow.
- ✗ **Expression Task without `@[User::X] =`.** The converter can't find a target
  variable and the SetVariable will be malformed.
- ✗ **Bloated fixtures.** Don't include 12 tasks to test one mapping. Minimal,
  targeted fixtures fail loudly and stay readable.
- ✗ **Editing a fixture to make a failing test pass** when the bug is in the
  translator. Fix the converter, not the fixture.
- ✗ **`System::` variables expecting output.** They are silently skipped — only
  `User::` variables convert.
