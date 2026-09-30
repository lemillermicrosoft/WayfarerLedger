$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$version = '0.2.0-rc.1'
$dist = Join-Path $root 'dist'
$out = Join-Path $dist "WayfarerLedger-$version.zip"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $out) { Remove-Item $out }
$files = @('WayfarerLedger.toc','Core.lua','Codec.lua','UI.lua','Options.lua','README.md','CHANGELOG.md','PRIVACY.md','TESTING.md','LICENSE','PREFLIGHT.md')
Add-Type -AssemblyName System.IO.Compression
$stream = [System.IO.File]::Open($out, [System.IO.FileMode]::CreateNew)
try {
  $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
  try {
    foreach ($file in $files) {
      $entry = $archive.CreateEntry("WayfarerLedger/$file", [System.IO.Compression.CompressionLevel]::Optimal)
      $input = [System.IO.File]::OpenRead((Join-Path $root $file))
      $output = $entry.Open()
      try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
    }
  } finally { $archive.Dispose() }
} finally { $stream.Dispose() }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$check = [System.IO.Compression.ZipFile]::OpenRead($out)
try {
  $names = @($check.Entries | ForEach-Object FullName)
  if ($names.Count -ne $files.Count) { throw "Package contains $($names.Count) entries; expected $($files.Count)." }
  foreach ($file in $files) {
    $expected = "WayfarerLedger/$file"
    if ($names -notcontains $expected) { throw "Package missing $expected" }
  }
  foreach ($name in $names) {
    if (-not $name.StartsWith('WayfarerLedger/') -or $name.Contains('\')) { throw "Invalid package path: $name" }
  }
} finally { $check.Dispose() }
Write-Output $out
