# Builds dist/ForeverRings-<version>.zip for a manual upload or local testing.
# Releases normally go through GitHub Actions (push a vX.Y.Z tag).
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$version = (git -C $root describe --tags --always 2>$null) -replace '^v', ''
if (-not $version) { $version = "dev" }

$stage = Join-Path $root "dist\ForeverRings"
Remove-Item -Recurse -Force (Join-Path $root "dist") -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null

$files = "ForeverRings.toc", "Bindings.xml", "Snippets.lua", "Data.lua", "Display.lua", "Core.lua", "Config.lua", "README.md", "CHANGELOG.md", "LICENSE"
foreach ($f in $files) { Copy-Item (Join-Path $root $f) $stage }
$toc = Join-Path $stage "ForeverRings.toc"
$text = [IO.File]::ReadAllText($toc) -replace '@project-version@', $version
[IO.File]::WriteAllText($toc, $text, (New-Object Text.UTF8Encoding $false))

$zip = Join-Path $root "dist\ForeverRings-$version.zip"
Compress-Archive -Path $stage -DestinationPath $zip
Write-Output $zip
