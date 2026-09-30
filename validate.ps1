$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$toc = Get-Content (Join-Path $root 'WayfarerLedger.toc')
if ($toc -notcontains '## Interface: 16001') { throw 'Wrong Interface value' }
foreach ($line in $toc) {
  if ($line -match '^[^#].*\.lua$' -and -not (Test-Path (Join-Path $root $line))) { throw "Missing TOC file: $line" }
}
$required = @('WayfarerLedgerDB','WayfarerLedgerCharDB','issecretvalue','GROUP_ROSTER_UPDATE','Settings.RegisterCanvasLayoutCategory','ExportData','ImportData')
$source = (Get-Content (Join-Path $root '*.lua') -Raw) -join "`n"
foreach ($needle in $required) { if (-not $source.Contains($needle)) { throw "Missing required feature token: $needle" } }
$opens = ([regex]::Matches($source, '\b(function|if|for|while|repeat|do)\b')).Count
$closes = ([regex]::Matches($source, '\b(end|until)\b')).Count
if ($closes -lt 1 -or $opens -lt 1) { throw 'Lua structure sanity check failed' }
Write-Output 'Static validation passed: TOC, listed files, Interface, and required feature markers.'
