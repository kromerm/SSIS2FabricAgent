---
name: ssis-authoring
description: >-
  Generate brand-new, designer-valid SSIS .dtsx packages from a natural-language
  prompt. Turns a request like "load a CSV into SQL Server and email me on
  failure" into a complete .dtsx that opens in Visual Studio / SSDT (SQL Server
  Data Tools). Provides copy-pasteable, BIDS-loadable DTSX fragments for
  connection managers, control-flow tasks, data flows, containers, precedence
  constraints, variables, and parameters, plus a prompt-to-package assembly
  workflow.
  WHEN: "create an SSIS package", "generate a .dtsx", "build me an SSIS
  package that ...", "make a DTSX with a Data Flow / Execute SQL / Send Mail /
  FTP / ForEach loop", "author an SSIS ETL package", "scaffold an SSIS package
  from this description", "write SSIS XML for X".
domain: ssis, dtsx, ssdt, etl, sql-server, integration-services
source: WeatherToEmail.dtsx (reference designer-valid package), SSIS DTSX schema
---

# SSIS Package Generator

## What this skill does

Generate **new SSIS `.dtsx` packages from a user's prompt**. The user describes
an ETL or automation job in plain language; this skill emits a complete,
well-formed `.dtsx` that **opens in the Visual Studio / SSDT SSIS designer**.

This is **not** a translator and **not** a test-fixture generator. The artifact
is a real SSIS package the user can open, finish wiring (credentials, exact
table/column mappings), and run.

### Fidelity bar: designer-open is the contract

The package **must open in the SSIS designer without a load error**
(`0xC001001D`, `0xC0010014`, "expected attribute not found"). **Running** it
end-to-end is best-effort — generated packages are *scaffolds*: the structure,
tasks, connections, and wiring are correct, but the user supplies real server
names, credentials, file paths, and finalizes data-flow column mappings in the
designer.

State this explicitly when you deliver a package: *"This opens in SSDT as a
scaffold. Replace the placeholder connection strings / paths and confirm the
Data Flow column mappings before running."*

---

## The golden rule: author what the designer can load (BIDS-load rules)

The SSIS designer (BIDS) is **strict**. The loader (`CPackage::LoadFromXML`)
tries to parse every element in the `DTS` namespace as a *known* structural
element and rejects the file if a required attribute is missing. Follow these
rules or the package won't open:

1. **Never invent a `DTS:`-namespaced element.** If it isn't a real DTS
   structural node, the loader fails it. Example trap: there is no
   `<DTS:HttpConnectionManager>`. The real node is `<DTS:HttpConnection>` with
   the URL on a `DTS:ServerURL` **attribute**, nested inside the connection
   manager's inner `<DTS:ConnectionManager>`.
2. **Put task-specific data in its own task namespace**, not the DTS namespace.
   Execute SQL → `SQLTask:SqlTaskData` (sqltask ns); Send Mail →
   `SendMailTask:SendMailTaskData` (sendmailtask ns); Web Service →
   `WebServiceTaskData` (webservicetask ns); FTP → `FTPTaskData` (ftptask ns).
3. **Give every task host the standard attributes:** `DTS:refId`,
   `DTS:ObjectName`, `DTS:DTSID`, `DTS:CreationName`, `DTS:ExecutableType`,
   `DTS:LocaleID="-1"`, `DTS:ThreadHint="0"`, and an empty `<DTS:Variables />`
   child.
4. **Declare every variable a task references.** If a task reads/writes
   `User::Foo`, add a matching `<DTS:Variable>` — an undeclared reference is an
   unresolved-reference load error.
5. **Set `DTS:ProtectionLevel="0"` (DontSaveSensitive) on the package.** Then
   the loader will not expect DPAPI-encrypted `<DTS:Property Encrypted="1">`
   blobs (passwords). **Never hand-author encrypted blobs** — empty or foreign
   encrypted text aborts the load. Leave passwords out; the user enters them.
6. **Use refId paths for precedence** (`Package\Task Name`) plus
   `DTS:LogicalAnd="True"` — the most reliable form.

`WeatherToEmail.dtsx` at the repo root is the **reference package** that opens
cleanly in the designer. When unsure about a structure, mirror it.

---

## DTSX anatomy

### Namespaces

```text
DTS       = www.microsoft.com/SqlServer/Dts
SQLTask   = www.microsoft.com/sqlserver/dts/tasks/sqltask
pipeline  = www.microsoft.com/SqlServer/Dts/Pipeline
```

Task-data namespaces (one per task type):

```text
sqltask         = www.microsoft.com/sqlserver/dts/tasks/sqltask
sendmailtask    = www.microsoft.com/sqlserver/dts/tasks/sendmailtask
webservicetask  = www.microsoft.com/sqlserver/dts/tasks/webservicetask
ftptask         = www.microsoft.com/sqlserver/dts/tasks/ftptask
expressiontask  = www.microsoft.com/sqlserver/dts/tasks/expressiontask
```

### Package skeleton

```xml
<?xml version="1.0" encoding="utf-8"?>
<DTS:Executable
    xmlns:DTS="www.microsoft.com/SqlServer/Dts"
    DTS:refId="Package"
    DTS:CreationName="Microsoft.Package"
    DTS:DTSID="{A0000000-0000-0000-0000-0000000000FF}"
    DTS:ExecutableType="Microsoft.Package"
    DTS:LocaleID="1033"
    DTS:ObjectName="MyPackage"
    DTS:PackageFormatVersion="8"
    DTS:ProtectionLevel="0"
    DTS:VersionGUID="{B0000000-0000-0000-0000-0000000000FF}">

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

### Identity & naming rules

- Every `DTS:DTSID` is a brace-wrapped GUID. Make each **unique** — duplicate
  IDs collide in connection/precedence resolution.
- A connection manager's `refId` is `Package.ConnectionManagers[<ObjectName>]`.
- A task's `refId` is `Package\<ObjectName>` (the ObjectName is the addressable
  path segment used by precedence constraints).
- Use a stable GUID-prefix-per-category scheme so generated packages stay
  human-trackable (e.g. `C…` = connections, `D…` = variables, `E…` = tasks,
  `F…` = precedence). This is a convention, not a requirement.

---

## Connection managers

Set `DTS:CreationName` to the SSIS connection type. Common ones:

| Source/target | `DTS:CreationName` |
|---|---|
| SQL Server (OLE DB) | `OLEDB` |
| SQL Server (ADO.NET) | `ADO.NET` |
| Flat file (CSV/TXT) | `FLATFILE` |
| File / folder | `FILE` |
| Excel | `EXCEL` |
| FTP | `FTP` |
| SMTP (email) | `SMTP` |
| HTTP / REST | `HTTP` |

### OLE DB / SQL Server

```xml
<DTS:ConnectionManager
    DTS:refId="Package.ConnectionManagers[TargetDb]"
    DTS:ObjectName="TargetDb"
    DTS:DTSID="{C2000000-0000-0000-0000-000000000002}"
    DTS:CreationName="OLEDB">
  <DTS:ObjectData>
    <DTS:ConnectionManager
        DTS:ConnectionString="Data Source=localhost;Initial Catalog=AdventureWorks;Provider=SQLNCLI11;Integrated Security=SSPI;" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

> Use `Integrated Security=SSPI` for the scaffold so no password blob is needed.
> If the user needs SQL auth, leave the password out and note it must be set in
> the designer.

### Flat File (CSV)

A Flat File connection manager **loads** with just the delimited-format
attributes below. Do **not** hand-author a `<DTS:FlatFileColumns>` child — the
element/attribute schema for columns is strict and a malformed columns block
makes the whole package fail to load (`0xC0010018`). Emit the column-less
scaffold and let the user define columns in the designer (Flat File Connection
Manager Editor → Columns), where SSIS generates the correct metadata.

```xml
<DTS:ConnectionManager
    DTS:refId="Package.ConnectionManagers[OrdersCsv]"
    DTS:ObjectName="OrdersCsv"
    DTS:DTSID="{C4000000-0000-0000-0000-000000000004}"
    DTS:CreationName="FLATFILE">
  <DTS:ObjectData>
    <DTS:ConnectionManager
        DTS:Format="Delimited"
        DTS:LocaleID="1033"
        DTS:HeaderRowDelimiter=""
        DTS:ColumnNamesInFirstDataRow="True"
        DTS:RowDelimiter=""
        DTS:TextQualifier=""
        DTS:CodePage="1252"
        DTS:ConnectionString="C:\data\orders.csv" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

> Attribute set verified against runtime-generated XML. Include `DTS:LocaleID`
> and `DTS:CodePage`; leave `DTS:HeaderRowDelimiter`, `DTS:RowDelimiter`, and
> `DTS:TextQualifier` empty. Omit `DTS:HeaderRowsToSkip`.

### Excel

```xml
<DTS:ConnectionManager
    DTS:refId="Package.ConnectionManagers[SalesXlsx]"
    DTS:ObjectName="SalesXlsx"
    DTS:DTSID="{C5000000-0000-0000-0000-000000000005}"
    DTS:CreationName="EXCEL">
  <DTS:ObjectData>
    <DTS:ConnectionManager
        DTS:ConnectionString="Provider=Microsoft.ACE.OLEDB.12.0;Data Source=C:\data\sales.xlsx;Extended Properties=&quot;Excel 12.0 XML;HDR=YES&quot;;" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

### FTP

```xml
<DTS:ConnectionManager
    DTS:refId="Package.ConnectionManagers[Ftp_Server]"
    DTS:ObjectName="Ftp_Server"
    DTS:DTSID="{C6000000-0000-0000-0000-000000000006}"
    DTS:CreationName="FTP">
  <DTS:ObjectData>
    <DTS:ConnectionManager
        DTS:ServerName="ftp.example.com"
        DTS:ServerPort="21"
        DTS:ConnectionString="ftp.example.com" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

### SMTP (email)

The SMTP connection manager's `<DTS:ObjectData>` uses a special
`<SmtpConnectionManager>` element (no `DTS:` prefix) — **not** the generic
`<DTS:ConnectionManager>`. Using the generic element makes the package fail to
load (`0xC0010018`).

```xml
<DTS:ConnectionManager
    DTS:refId="Package.ConnectionManagers[MailServer]"
    DTS:ObjectName="MailServer"
    DTS:DTSID="{C3000000-0000-0000-0000-000000000003}"
    DTS:CreationName="SMTP">
  <DTS:ObjectData>
    <SmtpConnectionManager
        ConnectionString="SmtpServer=smtp.office365.com;UseWindowsAuthentication=False;EnableSsl=True;" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

### HTTP / REST

```xml
<DTS:ConnectionManager
    DTS:refId="Package.ConnectionManagers[WeatherApi]"
    DTS:ObjectName="WeatherApi"
    DTS:DTSID="{C1000000-0000-0000-0000-000000000001}"
    DTS:CreationName="HTTP">
  <DTS:ObjectData>
    <DTS:ConnectionManager
        DTS:ConnectionString="https://api.example.com/data">
      <DTS:HttpConnection DTS:ServerURL="https://api.example.com/data" />
    </DTS:ConnectionManager>
  </DTS:ObjectData>
</DTS:ConnectionManager>
```

> Mirror the URL in **both** the inner `DTS:ConnectionString` and the
> `DTS:HttpConnection`'s `DTS:ServerURL`. With package `ProtectionLevel="0"`,
> omit the `ServerPassword`/`ProxyPassword` encrypted blobs entirely.

---

## Variables & parameters

### Variables

`User::` variables hold runtime state. `DataType` is a numeric code:

| Code | Type | | Code | Type |
|---|---|---|---|---|
| 3 | Int32 | | 11 | Boolean |
| 5 | Double | | 13 | String (BSTR) |
| 7 | DateTime | | 14 | Decimal |
| 8 | String | | 20 | Int64 |

```xml
<DTS:Variable
    DTS:ObjectName="Counter"
    DTS:DTSID="{D1000000-0000-0000-0000-000000000001}"
    DTS:CreationName=""
    DTS:Namespace="User"
    DTS:IncludeInDebugDump="2345">
  <DTS:VariableValue DTS:DataType="3">0</DTS:VariableValue>
</DTS:Variable>
```

### Variables with an expression

Set `DTS:EvaluateAsExpression="True"` and put the SSIS expression in
`DTS:Expression`:

```xml
<DTS:Variable
    DTS:ObjectName="TodayPath"
    DTS:DTSID="{D2000000-0000-0000-0000-000000000002}"
    DTS:CreationName=""
    DTS:Namespace="User"
    DTS:EvaluateAsExpression="True"
    DTS:Expression="&quot;C:\\in\\&quot; + (DT_WSTR, 8) (DT_DBDATE) GETDATE()">
  <DTS:VariableValue DTS:DataType="8"></DTS:VariableValue>
</DTS:Variable>
```

### Project / package parameters

Package parameters live in a `<DTS:PackageParameters>` block (sibling of
`<DTS:Variables>`):

```xml
<DTS:PackageParameters>
  <DTS:PackageParameter
      DTS:ObjectName="BatchSize"
      DTS:DTSID="{D9000000-0000-0000-0000-000000000009}"
      DTS:CreationName=""
      DTS:DataType="3">
    <DTS:Property DTS:Name="ParameterValue" DTS:DataType="3">1000</DTS:Property>
  </DTS:PackageParameter>
</DTS:PackageParameters>
```

> Reference a parameter in an expression as `@[$Package::BatchSize]`.

---

## Control-flow tasks

Each task is a `<DTS:Executable>` inside `<DTS:Executables>`. Always include the
full host attribute set (refId, ObjectName, DTSID, CreationName, ExecutableType,
LocaleID="-1", ThreadHint="0") and an empty `<DTS:Variables />`.

| Task | `DTS:CreationName` / `DTS:ExecutableType` |
|---|---|
| Execute SQL | `Microsoft.ExecuteSQLTask` |
| Data Flow | `Microsoft.Pipeline` |
| Script | `Microsoft.ScriptTask` |
| Send Mail | `Microsoft.SendMailTask` |
| FTP | `Microsoft.FTPTask` |
| Expression | `Microsoft.ExpressionTask` |
| File System | `Microsoft.FileSystemTask` |
| Execute Process | `Microsoft.ExecuteProcessTask` |
| Execute Package | `Microsoft.ExecutePackageTask` |
| Web Service | `Microsoft.WebServiceTask` |

### Execute SQL

```xml
<DTS:Executable
    DTS:refId="Package\Truncate Staging"
    DTS:ObjectName="Truncate Staging"
    DTS:DTSID="{E1000000-0000-0000-0000-000000000001}"
    DTS:CreationName="Microsoft.ExecuteSQLTask"
    DTS:ExecutableType="Microsoft.ExecuteSQLTask"
    DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ObjectData>
    <SQLTask:SqlTaskData
        xmlns:SQLTask="www.microsoft.com/sqlserver/dts/tasks/sqltask"
        SQLTask:Connection="{C2000000-0000-0000-0000-000000000002}"
        SQLTask:SqlStatementSourceType="DirectInput"
        SQLTask:SqlStatementSource="TRUNCATE TABLE stg.Orders;" />
  </DTS:ObjectData>
</DTS:Executable>
```

> `SQLTask:Connection` is the **DTSID** of the OLE DB connection manager.

### Send Mail

```xml
<DTS:Executable
    DTS:refId="Package\Send Notification"
    DTS:ObjectName="Send Notification"
    DTS:DTSID="{E3000000-0000-0000-0000-000000000003}"
    DTS:CreationName="Microsoft.SendMailTask"
    DTS:ExecutableType="Microsoft.SendMailTask"
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

> `SMTPServer` references the SMTP connection manager by **ObjectName**.

### Expression Task

The expression assigns to a variable: `@[User::Target] = <expr>`. Put it in the
**element text** of the namespaced `<ExpressionTask>` node:

```xml
<DTS:Executable
    DTS:refId="Package\Increment Counter"
    DTS:ObjectName="Increment Counter"
    DTS:DTSID="{E4000000-0000-0000-0000-000000000004}"
    DTS:CreationName="Microsoft.ExpressionTask"
    DTS:ExecutableType="Microsoft.ExpressionTask"
    DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ObjectData>
    <ExpressionTask xmlns="www.microsoft.com/sqlserver/dts/tasks/expressiontask">@[User::Counter] = @[User::Counter] + 1</ExpressionTask>
  </DTS:ObjectData>
</DTS:Executable>
```

### FTP Task

```xml
<DTS:Executable
    DTS:refId="Package\Download File"
    DTS:ObjectName="Download File"
    DTS:DTSID="{E5000000-0000-0000-0000-000000000005}"
    DTS:CreationName="Microsoft.FTPTask"
    DTS:ExecutableType="Microsoft.FTPTask"
    DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ObjectData>
    <FTPTaskData xmlns="www.microsoft.com/sqlserver/dts/tasks/ftptask"
                 Operation="Receive"
                 RemotePath="/in/orders.csv"
                 LocalPath="C:\data"
                 Connection="{C6000000-0000-0000-0000-000000000006}" />
  </DTS:ObjectData>
</DTS:Executable>
```

> `Connection` is the **DTSID** of the FTP connection manager.

### Script Task (scaffold)

```xml
<DTS:Executable
    DTS:refId="Package\Custom Logic"
    DTS:ObjectName="Custom Logic"
    DTS:DTSID="{E6000000-0000-0000-0000-000000000006}"
    DTS:CreationName="Microsoft.ScriptTask"
    DTS:ExecutableType="Microsoft.ScriptTask"
    DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ObjectData>
    <ScriptProject />
  </DTS:ObjectData>
</DTS:Executable>
```

> The designer will offer to generate the script project when the task is
> opened. Note to the user that they add the C#/VB body in SSDT.

### Disabled task

Set `DTS:Disabled="True"` on the executable host.

---

## Data flows

A Data Flow task (`Microsoft.Pipeline`) wraps a `<pipeline>` element. A
**populated** pipeline (sources, transforms, destinations, paths) is the single
hardest part of the DTSX format to hand-author: every component needs fully
specified `<inputs>`/`<outputs>` with `id`/`refId`/`lineageId` wiring,
`externalMetadataColumns`, connections referenced by `connectionManagerRefId`
(not raw GUID), and `<path>` elements whose `startId`/`endId` point at the
**output and input ids** (not component ids). A single mismatch makes the whole
package fail to load.

**Default to an empty Data Flow task.** It is guaranteed designer-valid: the
package opens, the Data Flow task appears on the canvas, and the user adds and
wires components in the designer (where SSIS generates the lineage metadata
correctly). This satisfies the "must open in the designer" bar.

```xml
<DTS:Executable
    DTS:refId="Package\Load Orders"
    DTS:ObjectName="Load Orders"
    DTS:DTSID="{E7000000-0000-0000-0000-000000000007}"
    DTS:CreationName="Microsoft.Pipeline"
    DTS:ExecutableType="Microsoft.Pipeline"
    DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ObjectData>
    <pipeline version="1">
      <components />
      <paths />
    </pipeline>
  </DTS:ObjectData>
</DTS:Executable>
```

Common component class IDs (for reference when the user later builds the flow,
or if you attempt a populated pipeline against a known-good sample):

| Role | `componentClassID` |
|---|---|
| OLE DB Source | `Microsoft.OLEDBSource` |
| Flat File Source | `Microsoft.FlatFileSource` |
| Excel Source | `Microsoft.ExcelSource` |
| Derived Column | `Microsoft.DerivedColumn` |
| Data Conversion | `Microsoft.DataConvert` |
| Lookup | `Microsoft.Lookup` |
| Conditional Split | `Microsoft.ConditionalSplit` |
| Aggregate | `Microsoft.Aggregate` |
| Sort | `Microsoft.Sort` |
| OLE DB Destination | `Microsoft.OLEDBDestination` |
| Flat File Destination | `Microsoft.FlatFileDestination` |

> Do not emit a populated pipeline unless you are copying the exact structure
> from a known-good sample package and validating it with the runtime load check
> below. The empty Data Flow task is the safe, designer-valid default.

### Populated pipelines are package-format-coupled (runtime-verified)

A populated `<pipeline>` only loads inside a package of the **matching format
generation**. This is verified, not theoretical:

- The classic verbose pipeline (components with numeric `id`s, `<outputColumn>`/
  `<externalMetadataColumn>` lineage, `<connection ... connectionManagerID="{GUID}">`,
  `<path startId="…" endId="…">`) loads **only** inside an old-format package
  (`DTS:ExecutableType="MSDTS.Package.1"`, `PackageFormatVersion` 2, control flow
  expressed as `<DTS:Property>` elements and `DTS.Pipeline.1` executables).
- Embedding that same verbose pipeline inside a modern attribute-based package
  (`Microsoft.Package`, `PackageFormatVersion` 8) **fails to load** with a cascade
  of `0xC001001C "references ID … but no object in the package has this ID"` —
  the v8 loader resolves pipeline metadata by `refId`, not by the legacy numeric
  ids. Adding `connectionManagerRefId` does not fix it; the generations are not
  interchangeable.

**To ship a runtime-valid populated data flow, author the WHOLE package in the
old format and reuse a known-good pipeline block verbatim.** Proven facts:

- Pipeline-internal ids are scoped **per data flow**, so the same known-good
  pipeline block can be reused for multiple data flows in one package — only the
  *executable* `DTSID` and `ObjectName` must be unique across the package.
- The designer-layout `<DTS:PackageVariable>` blocks (namespace `dts-designer-1.0`,
  `dwd:Layout`) are **optional** — strip them and the package still loads; the
  designer regenerates layout on open.
- A minimal old-format package is: root `<DTS:Executable
  DTS:ExecutableType="MSDTS.Package.1">` → package `<DTS:Property>` block
  (`PackageFormatVersion`=2, `ProtectionLevel`=0, …) → one `<DTS:ConnectionManager>`
  per connection → one `<DTS:Executable DTS:ExecutableType="DTS.Pipeline.1">` per
  data flow (each wrapping its `<DTS:ObjectData><pipeline …></DTS:ObjectData>`) →
  trailing package `ObjectName`/`DTSID`/`CreationName=MSDTS.Package.1` properties.
- `DualForecastLoad.dtsx` in this repo is a runtime-verified example: two
  populated data flows (OLE DB Source → Derived Column → Excel Destination),
  `LOAD OK (Executables=2, Connections=2)`.

When the user wants a populated data flow that opens in SSDT, prefer this
old-format route over hand-authoring lineage into a modern package. The empty
Data Flow task remains the safe default for modern (`Microsoft.Package`) output.

---

## Containers

Containers nest their own `<DTS:Executables>` (and may carry their own
`<DTS:PrecedenceConstraints>`).

### Sequence

```xml
<DTS:Executable
    DTS:refId="Package\Load Group"
    DTS:ObjectName="Load Group"
    DTS:DTSID="{E8000000-0000-0000-0000-000000000008}"
    DTS:CreationName="STOCK:SEQUENCE"
    DTS:ExecutableType="STOCK:SEQUENCE"
    DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:Executables>
    <!-- inner tasks -->
  </DTS:Executables>
</DTS:Executable>
```

### For Loop

```xml
<DTS:Executable
    DTS:refId="Package\Retry Loop"
    DTS:ObjectName="Retry Loop"
    DTS:DTSID="{E9000000-0000-0000-0000-000000000009}"
    DTS:CreationName="STOCK:FORLOOP"
    DTS:ExecutableType="STOCK:FORLOOP"
    DTS:LocaleID="-1" DTS:ThreadHint="0"
    DTS:InitExpression="@Counter = 0"
    DTS:EvalExpression="@Counter &lt; 5"
    DTS:AssignExpression="@Counter = @Counter + 1">
  <DTS:Variables />
  <DTS:Executables>
    <!-- inner tasks -->
  </DTS:Executables>
</DTS:Executable>
```

### ForEach Loop (over files)

```xml
<DTS:Executable
    DTS:refId="Package\Per File"
    DTS:ObjectName="Per File"
    DTS:DTSID="{EA000000-0000-0000-0000-00000000000A}"
    DTS:CreationName="STOCK:FOREACHLOOP"
    DTS:ExecutableType="STOCK:FOREACHLOOP"
    DTS:LocaleID="-1" DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ForEachEnumerator
      DTS:refId="Package\Per File.ForEachEnumerator"
      DTS:CreationName="Microsoft.ForEachFileEnumerator"
      DTS:ObjectName="FileEnumerator">
    <DTS:ObjectData>
      <ForEachFileEnumerator
          xmlns="www.microsoft.com/sqlserver/dts/tasks/foreachfileenumerator"
          Folder="C:\in" FileSpec="*.csv" />
    </DTS:ObjectData>
  </DTS:ForEachEnumerator>
  <DTS:ForEachVariableMappings>
    <DTS:ForEachVariableMapping
        DTS:refId="Package\Per File.ForEachVariableMapping"
        DTS:DTSID="{EB000000-0000-0000-0000-00000000000B}"
        DTS:VariableName="User::CurrentFile"
        DTS:ValueIndex="0" />
  </DTS:ForEachVariableMappings>
  <DTS:Executables>
    <!-- inner tasks -->
  </DTS:Executables>
</DTS:Executable>
```

> Declare `User::CurrentFile` (String, code 8) in `<DTS:Variables>`.

---

## Precedence constraints

Wire tasks by **refId path** (`Package\<ObjectName>`). `DTS:Value`: `0`=Success,
`1`=Failure, `2`=Completion. `DTS:EvalOp`: `0`=Constraint, `1`=Expression,
`2`=Expression **and** Constraint, `3`=Expression **or** Constraint.

```xml
<DTS:PrecedenceConstraint
    DTS:refId="Package.PrecedenceConstraints[Truncate to Load]"
    DTS:ObjectName="Truncate to Load"
    DTS:DTSID="{F1000000-0000-0000-0000-000000000001}"
    DTS:From="Package\Truncate Staging"
    DTS:To="Package\Load Orders"
    DTS:LogicalAnd="True"
    DTS:EvalOp="0"
    DTS:Value="0" />
```

> For an "on failure → send email" branch, set `DTS:Value="1"` on the
> constraint from the work task to the Send Mail task.

---

## Prompt → package assembly workflow

1. **Parse the intent.** Identify: data sources & sinks → connection managers;
   the verbs (load, transform, run SQL, email, download, loop) → tasks; the
   ordering words (then, after, on success/failure) → precedence; any state
   (counters, file paths, dates) → variables/parameters.
2. **Pick the minimal construct set.** One connection manager per distinct
   source/sink. One task per action. Add a Data Flow only when rows move between
   stores; use Execute SQL for set-based work that stays in one database.
3. **Allocate identities.** Assign unique DTSIDs (prefix-per-category), refIds,
   and ObjectNames up front so tasks, connections, and precedence all
   cross-reference cleanly.
4. **Emit in package order:** ConnectionManagers → (PackageParameters) →
   Variables → Executables → PrecedenceConstraints.
5. **Wire references by the right key:** connection refs from tasks use the
   **DTSID**; Send Mail's `SMTPServer` and Web Service's `ConnectionName` use
   the connection **ObjectName**; precedence uses **refId paths**.
6. **Default to a runnable-shaped scaffold.** Use `Integrated Security=SSPI`,
   `ProtectionLevel="0"`, plausible placeholder servers/paths, and no encrypted
   blobs.
7. **Deliver with a finish-the-wiring note** listing every placeholder the user
   must replace (servers, credentials, file paths, Data Flow column mappings).

### Worked shape: "Load a CSV into SQL Server, email me if it fails"

- Connection managers: `OrdersCsv` (FLATFILE), `TargetDb` (OLEDB), `MailServer`
  (SMTP).
- Tasks: `Load Orders` (Data Flow: Flat File Source → OLE DB Destination),
  `Send Failure Alert` (Send Mail).
- Precedence: `Load Orders → Send Failure Alert` with `DTS:Value="1"` (failure).

---

## Validating the package opens

Generated `.dtsx` is well-formed XML. To confirm designer-load fidelity:

- **Well-formedness:** the file must parse as XML (no unescaped `&`, `<`, `>`;
  use `&amp;` in URLs/connection strings).
- **Required attributes:** every task host has refId / ObjectName / DTSID /
  CreationName / ExecutableType; the package has ProtectionLevel and
  PackageFormatVersion.
- **No dangling references:** every connection DTSID a task cites exists; every
  `User::` variable a task/loop cites is declared; every precedence From/To
  refId names a real task.
- **Runtime load check (the reliable test):** load the package with the same
  managed SSIS runtime the designer uses. This catches malformed connection
  managers, bad data-flow pipelines, and wrong task-data elements that
  well-formedness checks miss. Run under **Windows PowerShell 5.1**
  (`powershell.exe`, .NET Framework) — the runtime assembly will not work under
  PowerShell 7 / .NET. Pass an `IDTSEvents` sink to surface the specific
  `0xC001…` error and the offending node:

  ```powershell
  $asm = (Get-ChildItem "C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.ManagedDTS" -Recurse -Filter Microsoft.SqlServer.ManagedDTS.dll | Select-Object -First 1).FullName
  Add-Type -Path $asm
  $cs = @"
  using System; using System.Collections.Generic;
  using Microsoft.SqlServer.Dts.Runtime;
  public class CollectingEvents : DefaultEvents {
    public List<string> Errors = new List<string>();
    public override bool OnError(DtsObject s,int code,string sub,string desc,string hf,int hc,string id){
      Errors.Add(string.Format("0x{0:X8} {1}", code, desc)); return false; }
  }
  "@
  Add-Type -TypeDefinition $cs -ReferencedAssemblies $asm
  $ev = New-Object CollectingEvents
  $app = New-Object Microsoft.SqlServer.Dts.Runtime.Application
  try { $p = $app.LoadPackage((Resolve-Path .\MyPackage.dtsx), $ev); "LOAD OK: $($p.Name)" }
  catch { "LOAD FAILED"; $ev.Errors | ForEach-Object { $_ } }
  ```

  `LOAD OK` means it will open in SSDT. A `LOAD FAILED` line such as
  `0xC0010018 Error loading value "…" from node "DTS:ConnectionManagers"` points
  straight at the offending construct.
- **Open in SSDT** (final confirmation): add the `.dtsx` to an Integration
  Services project in Visual Studio and open it. A clean load = success.

A quick well-formedness check in PowerShell:

```powershell
[xml](Get-Content -Raw .\MyPackage.dtsx) | Out-Null; "well-formed"
```

---

## Anti-patterns

- ✗ **Inventing `DTS:`-namespaced elements** (e.g. `<DTS:HttpConnectionManager>`,
  `<DTS:SendMailTask>`). The loader rejects unknown DTS structural nodes. Use
  the authentic namespaced task-data forms.
- ✗ **Hand-authoring encrypted password blobs.** Set `ProtectionLevel="0"` and
  omit them; the user supplies credentials in the designer.
- ✗ **Referencing an undeclared `User::` variable.** Always add a matching
  `<DTS:Variable>`.
- ✗ **Duplicate DTSIDs.** Break connection/precedence resolution. Keep every
  GUID unique.
- ✗ **Wrong reference key.** Connection refs from tasks use the DTSID; Send Mail
  / Web Service reference the connection by ObjectName; precedence uses refId
  paths. Mixing these up breaks the load or leaves tasks unwired.
- ✗ **Unescaped `&` in URLs / connection strings.** Use `&amp;` — a bare `&`
  makes the XML malformed and nothing opens.
- ✗ **Over-stuffed packages.** Generate the minimal set of constructs the prompt
  asks for; a focused scaffold is easier to finish and verify.
- ✗ **Claiming it will run as-is.** Be explicit that it opens as a scaffold and
  list the placeholders to replace.
