# Builds dist/ForeverRings-<version>.zip for a manual CurseForge upload.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$version = (Select-String -Path "$root\ForeverRings.toc" -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()

$stage = Join-Path $root "dist\ForeverRings"
Remove-Item -Recurse -Force (Join-Path $root "dist") -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null

$files = "ForeverRings.toc", "Bindings.xml", "Snippets.lua", "Data.lua", "Display.lua", "Core.lua", "README.md", "CHANGELOG.md", "LICENSE"
foreach ($f in $files) { Copy-Item (Join-Path $root $f) $stage }

$zip = Join-Path $root "dist\ForeverRings-$version.zip"
Compress-Archive -Path $stage -DestinationPath $zip
Write-Output $zip
