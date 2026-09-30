$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$toc = Get-Content (Join-Path $root 'WayfarerLedger.toc')
if ($toc -notcontains '## Interface: 16001') { throw 'Wrong Interface value' }
if ($toc -notcontains '## Version: 0.2.0-rc.1') { throw 'Wrong candidate version' }
foreach ($line in $toc) {
  if ($line -match '^[^#].*\.lua$' -and -not (Test-Path (Join-Path $root $line))) { throw "Missing TOC file: $line" }
}
$required = @(
  'WayfarerLedgerDB','WayfarerLedgerCharDB','issecretvalue','SafeBooleanCall','GROUP_ROSTER_UPDATE',
  'Settings.RegisterCanvasLayoutCategory','ResetWindowPosition','ExportData','ImportData','MAX_RECORDS',
  'appearance = "blizzard"','NormalizeAppearance','Bronze / custom','WL.MAX_ENCOUNTERS = 40',
  'WL.MAX_TIMELINE = 100','MoveRecord','ResetScope','CreateBackup','recentEncounterText','markerFilter',
  '-- Message text is intentionally ignored and never persisted.'
)
$source = (Get-Content (Join-Path $root '*.lua') -Raw) -join "`n"
foreach ($needle in $required) { if (-not $source.Contains($needle)) { throw "Missing required feature token: $needle" } }
if ($source.Contains('tostring(')) { throw 'Code must not stringify unchecked values' }
foreach ($unsafe in @('if not UnitExists(', 'if UnitIsUnit(', 'IsInRaid and IsInRaid()', 'SendAddonMessage', 'C_ChatInfo.SendAddonMessage')) {
  if ($source.Contains($unsafe)) { throw "Unsafe or disallowed token: $unsafe" }
}
if (-not ($toc -match '^## X-Curse-Project-ID:\s*\d+$')) { throw 'Missing numeric CurseForge project ID' }
if ($toc -match '^## IconTexture: Interface\\Icons') { throw 'Blizzard inventory icon must not be packaged' }
if ($source.Contains('SetAtlas(')) { throw 'Atlas textures must not be stretched or used by appearance code' }
foreach ($doc in @('README.md','CHANGELOG.md','PRIVACY.md','TESTING.md')) { if (-not (Test-Path (Join-Path $root $doc))) { throw "Missing $doc" } }

& (Join-Path $root 'tests\run.ps1')
Write-Output 'Static validation passed: manifest, privacy invariants, feature markers, and deterministic data tests.'
