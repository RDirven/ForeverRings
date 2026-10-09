# Draws assets/logo.png (400x400): a ring of eight slots with one highlighted.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force (Join-Path $root "assets") | Out-Null

$size = 400
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = "AntiAlias"
$g.Clear([System.Drawing.Color]::FromArgb(255, 16, 20, 30))

$accent = [System.Drawing.Color]::FromArgb(255, 89, 191, 255)
$slot = [System.Drawing.Color]::FromArgb(255, 52, 60, 78)
$c = $size / 2

# Faint guide ring
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 89, 191, 255)), 6
$g.DrawEllipse($pen, $c - 120, $c - 120, 240, 240)

for ($i = 0; $i -lt 8; $i++) {
	$a = [Math]::PI * 2 * $i / 8
	$x = $c + [Math]::Sin($a) * 120
	$y = $c - [Math]::Cos($a) * 120
	$r = if ($i -eq 1) { 44 } else { 34 }
	$brush = New-Object System.Drawing.SolidBrush ($(if ($i -eq 1) { $accent } else { $slot }))
	$g.FillEllipse($brush, $x - $r, $y - $r, $r * 2, $r * 2)
}

# Stick in the middle, tilted toward the highlighted slot
$g.FillEllipse((New-Object System.Drawing.SolidBrush $slot), $c - 46, $c - 46, 92, 92)
$g.FillEllipse((New-Object System.Drawing.SolidBrush $accent), $c - 26 + 14, $c - 26 - 14, 52, 52)

$out = Join-Path $root "assets\logo.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output $out
