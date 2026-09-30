$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$version = '0.1.0-alpha'
$out = Join-Path $root "WayfarerLedger-$version.zip"
if (Test-Path $out) { Remove-Item $out }
$files = @('WayfarerLedger.toc','Core.lua','Codec.lua','UI.lua','Options.lua','README.md','CHANGELOG.md','LICENSE','PREFLIGHT.md')
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
Write-Output $out
