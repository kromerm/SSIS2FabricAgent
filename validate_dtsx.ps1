param([string]$Path)
$x = [xml](Get-Content -Raw $Path)
$DTS = 'www.microsoft.com/SqlServer/Dts'
$ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
$ns.AddNamespace('DTS', $DTS)
$ns.AddNamespace('pl', 'www.microsoft.com/SqlServer/Dts/Pipeline')

$cmIds = $x.SelectNodes('//DTS:ConnectionManager[@DTS:DTSID]', $ns) | ForEach-Object { $_.GetAttribute('DTSID', $DTS) }
Write-Host "Connection DTSIDs: $($cmIds -join ', ')"

$plRefs = $x.SelectNodes('//pl:connection', $ns) | ForEach-Object { $_.connectionManagerID }
$missing = $plRefs | Where-Object { $_ -and ($cmIds -notcontains $_) }
if ($missing) { Write-Host "DANGLING pipeline connection refs: $($missing -join ', ')" } else { Write-Host "Pipeline connection refs OK" }

$taskPaths = $x.SelectNodes('//DTS:Executables/DTS:Executable[@DTS:refId]', $ns) | ForEach-Object { $_.GetAttribute('refId', $DTS) }
Write-Host "Task refIds: $($taskPaths -join ' | ')"

$pcs = $x.SelectNodes('//DTS:PrecedenceConstraint', $ns)
foreach ($pc in $pcs) {
  $from = $pc.GetAttribute('From', $DTS)
  $to = $pc.GetAttribute('To', $DTS)
  $okF = $taskPaths -contains $from
  $okT = $taskPaths -contains $to
  Write-Host "PC From='$from'($okF) To='$to'($okT)"
}

$allIds = $x.SelectNodes('//*[@DTS:DTSID]', $ns) | ForEach-Object { $_.GetAttribute('DTSID', $DTS) }
$dups = $allIds | Group-Object | Where-Object { $_.Count -gt 1 }
if ($dups) { Write-Host "DUPLICATE DTSIDs: $($dups.Name -join ', ')" } else { Write-Host "All DTSIDs unique" }
