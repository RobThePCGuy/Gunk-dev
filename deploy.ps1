# Builds the Gunk mod zip (with explicit directory entries) and deploys it to the game's mod folder.
# Run with the game CLOSED, then launch in VR to load the mod. Portable: reads source next to this script and
# deploys via $env:USERPROFILE, so it works on any machine.
$ErrorActionPreference = 'Stop'
$root    = $PSScriptRoot   # source lives next to this script (install-independent)
$modName = 'Gunk'
$src     = Join-Path $root $modName
$dist    = Join-Path $root 'dist'
$zip     = Join-Path $dist "$modName.zip"
$targets = @(
  "$env:USERPROFILE\AppData\LocalLow\ErThu\Ancient_Dungeon\ADVR_Mods"   # the verified mod load path
)

if (Get-Process -Name 'Ancient_Dungeon' -ErrorAction SilentlyContinue) {
  Write-Warning 'Ancient_Dungeon.exe is running - close the game before deploying, then re-run.'
}
$fileCount = (Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue).Count
if ($fileCount -lt 1) { throw "Source '$src' has no files - refusing to build an empty zip." }
# The ADVR linter rejects the ';' character anywhere in a .lua (even comments). Block it here.
$badLua = Get-ChildItem $src -Recurse -Filter *.lua | Where-Object { (Get-Content $_.FullName -Raw) -match ';' }
if ($badLua) { throw "Semicolon found in: $($badLua.FullName -join ', ') - remove all ';' before deploying." }
Write-Output "Source has $fileCount file(s) under $src"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $zip) { Remove-Item $zip -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  $null = $archive.CreateEntry("$modName/")                       # explicit root dir entry
  Get-ChildItem $src -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length + 1).Replace('\','/')
    if ($_.PSIsContainer) {
      $null = $archive.CreateEntry("$modName/$rel/")              # explicit folder entry
    } else {
      $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive, $_.FullName, "$modName/$rel",
        [System.IO.Compression.CompressionLevel]::Optimal)
    }
  }
} finally { $archive.Dispose() }

foreach ($t in $targets) {
  if (Test-Path $t) {
    Copy-Item $zip (Join-Path $t "$modName.zip") -Force
    Write-Output "Deployed -> $t\$modName.zip"
  } else {
    Write-Warning "Target missing: $t"
  }
}

# Force a clean re-extraction. The game caches extracted zips under extracted_content and does NOT reliably
# re-extract when the zip changes -- a stale extraction means the game runs OLD code and every test is invalid.
# Deleting our extracted folder guarantees the next launch extracts the freshly-deployed zip.
$extracted = "$env:USERPROFILE\AppData\LocalLow\ErThu\Ancient_Dungeon\extracted_content\$modName"
if (Test-Path $extracted) {
  Remove-Item $extracted -Recurse -Force -ErrorAction SilentlyContinue
  Write-Output "Cleared stale extraction -> $extracted"
}
Write-Output "=== zip entries ==="
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
$z.Entries | ForEach-Object { $_.FullName }
$z.Dispose()
Write-Output 'Done. Launch the game in VR to load the mod.'
