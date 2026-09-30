$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Encode([string]$value) {
  return $value.Replace('%','%25').Replace("`t",'%09').Replace("`r",'%0D').Replace("`n",'%0A')
}
function Decode([string]$value) {
  $position = $value.IndexOf('%')
  while ($position -ge 0) {
    if ($position + 2 -ge $value.Length -or $value.Substring($position + 1, 2) -notmatch '^[0-9A-Fa-f]{2}$') { throw 'invalid escape' }
    $position = $value.IndexOf('%', $position + 3)
  }
  return [regex]::Replace($value, '%([0-9A-Fa-f]{2})', { param($m) [char][Convert]::ToInt32($m.Groups[1].Value,16) })
}
function Canonical([string]$name, [string]$realm='ExampleRealm') {
  $parts = $name.Trim() -split '-',2
  if ($parts.Count -eq 2) { $name,$realm = $parts[0],$parts[1] }
  return (($name -replace '\s','') + '-' + ($realm -replace '\s','')).ToLowerInvariant()
}

# Deterministic codec round trips, including control delimiters and percent sequences.
$fixtures = @('', 'simple', "tab`tline", "line1`nline2", '%09 literal', 'Ångström-ExampleRealm')
foreach ($fixture in $fixtures) { Assert ((Decode (Encode $fixture)) -ceq $fixture) "codec round-trip failed: $fixture" }
$random = [Random]::new(16001)
for ($i=0; $i -lt 1000; $i++) {
  $chars = for ($j=0; $j -lt $random.Next(0,128); $j++) { [char]$random.Next(32,127) }
  $value = -join $chars
  Assert ((Decode (Encode $value)) -ceq $value) "fuzz round-trip failed at $i"
}
foreach ($bad in @('%','%0','%XZ','%0Z','abc%Q1')) {
  $failed = $false; try { Decode $bad | Out-Null } catch { $failed = $true }
  Assert $failed "malformed escape accepted: $bad"
}

# Duplicate/name normalization fixture.
Assert ((Canonical 'Alice-My Realm') -eq (Canonical 'ALICE-myrealm')) 'realm/name case duplicate was not canonicalized'
Assert ((Canonical ' Alice ' 'My Realm') -eq 'alice-myrealm') 'space normalization failed'

$source = (Get-Content (Join-Path $root '*.lua') -Raw) -join "`n"
Assert (-not $source.Contains('tostring(')) 'unchecked stringify token present'
Assert (-not $source.Contains('SendAddonMessage')) 'network-sharing API present'
Assert (-not $source.Contains('C_ChatInfo.SendAddonMessage')) 'network-sharing API present'
Assert ($source.Contains('local MAX_BYTES = 1024 * 1024')) '1 MiB import bound missing'
Assert ($source.Contains('local MAX_RECORDS = 5000')) 'record bound missing'
Assert ($source.Contains('WL.MAX_ENCOUNTERS = 40')) 'encounter bound missing'
Assert ($source.Contains('WL.MAX_TIMELINE = 100')) 'timeline bound missing'
Assert ($source.Contains('-- Message text is intentionally ignored and never persisted.')) 'chat privacy invariant missing'
Assert ($source.Contains('if not self:CreateBackup("Before import")')) 'transactional import backup gate missing'

# Version agreement and required privacy docs.
$toc = Get-Content (Join-Path $root 'WayfarerLedger.toc') -Raw
Assert ($toc.Contains('## Version: 0.2.0-rc.1')) 'TOC candidate version mismatch'
Assert ($source.Contains('WL.VERSION = "0.2.0-rc.1"')) 'Lua candidate version mismatch'
Assert (Test-Path (Join-Path $root 'PRIVACY.md')) 'privacy documentation missing'
Assert (Test-Path (Join-Path $root 'TESTING.md')) 'smoke-test documentation missing'

Write-Output 'Deterministic codec fuzz, normalization, privacy invariants, bounds, and version checks passed.'
