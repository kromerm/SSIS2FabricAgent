param([Parameter(Mandatory=$true)][string]$Path)

# Validates a .dtsx with the real SSIS managed runtime AND captures detailed
# load errors via an IDTSEvents sink. Run under Windows PowerShell 5.1.
$full = (Resolve-Path $Path).Path
$asm = (Get-ChildItem "C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.ManagedDTS" -Recurse -Filter Microsoft.SqlServer.ManagedDTS.dll | Select-Object -First 1).FullName
Add-Type -Path $asm

$cs = @"
using System;
using System.Collections.Generic;
using Microsoft.SqlServer.Dts.Runtime;
public class CollectingEvents : DefaultEvents {
    public List<string> Errors = new List<string>();
    public override bool OnError(DtsObject source, int errorCode, string subComponent, string description, string helpFile, int helpContext, string idofInterfaceWithError) {
        Errors.Add(string.Format("0x{0:X8} [{1}] {2}", errorCode, subComponent, description));
        return false;
    }
}
"@
Add-Type -TypeDefinition $cs -ReferencedAssemblies $asm

$ev = New-Object CollectingEvents
$app = New-Object Microsoft.SqlServer.Dts.Runtime.Application
try {
    $pkg = $app.LoadPackage($full, $ev)
    Write-Host "LOAD OK: $($pkg.Name)  (Executables=$($pkg.Executables.Count), Connections=$($pkg.Connections.Count))"
    exit 0
} catch {
    Write-Host "LOAD FAILED: $($_.Exception.Message)"
    if ($ev.Errors.Count -gt 0) {
        Write-Host "--- detailed errors ---"
        $ev.Errors | ForEach-Object { Write-Host $_ }
    }
    exit 1
}
